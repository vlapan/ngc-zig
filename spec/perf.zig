const std = @import("std");
const perf_helpers = @import("perf_helpers");

const parse_data = @import("data/perf_parse.zig");
const output_data = @import("data/perf_output.zig");

const snapshot_path = "spec/snapshots/perf-baselines.snap";
const record_flag = "--record";

const MIN_BATCHES: usize = 20;
const MAX_BATCHES: usize = 2000;
const MAX_BUDGET_MS: u64 = 1000;
const TARGET_BATCH_NS: u64 = 1_000_000;
const NEAR_MIN_WINDOW: f64 = 1.01;
const NEAR_MIN_REQUIRED: usize = 5;
const PCTL_STALL: usize = 20;
const PCTL_SMOOTHING: usize = 5;
const PCTL_THRESHOLD: f64 = 0.0001;
const MIN_AFTER_MIN: usize = 20;

const ConvergenceStat = enum { mean, median, t50, t75 };

const CL = perf_helpers.cache_line;

const BatchStats = struct {
    times_ns: [MAX_BATCHES]u64 align(CL),
    count: usize,

    fn add(s: *@This(), elapsed_ns: u64) void {
        s.times_ns[s.count] = elapsed_ns;
        s.count += 1;
    }

    fn t50(s: *const @This()) u64 {
        const asc = struct {
            fn lt(_: void, a: u64, b: u64) bool {
                return a < b;
            }
        }.lt;
        var copy = s.times_ns;
        std.mem.sort(u64, copy[0..s.count], {}, asc);
        const discard = s.count * 25 / 100;
        const kept = s.count - 2 * discard;
        var sum: u64 = 0;
        for (copy[discard .. discard + kept]) |v| sum += v;
        return sum / @as(u64, @intCast(kept));
    }

    fn t75(s: *const @This()) u64 {
        const asc = struct {
            fn lt(_: void, a: u64, b: u64) bool {
                return a < b;
            }
        }.lt;
        var copy = s.times_ns;
        std.mem.sort(u64, copy[0..s.count], {}, asc);
        const kept = s.count * 75 / 100;
        var sum: u64 = 0;
        for (copy[0..kept]) |v| sum += v;
        return sum / @as(u64, @intCast(kept));
    }

    fn mean(s: *const @This()) u64 {
        var sum: u64 = 0;
        for (s.times_ns[0..s.count]) |v| sum += v;
        return sum / @as(u64, @intCast(s.count));
    }

    fn median(s: *const @This()) u64 {
        const asc = struct {
            fn lt(_: void, a: u64, b: u64) bool {
                return a < b;
            }
        }.lt;
        var copy = s.times_ns;
        std.mem.sort(u64, copy[0..s.count], {}, asc);
        return copy[s.count / 2];
    }

    fn min(s: *const @This()) u64 {
        var m: u64 = std.math.maxInt(u64);
        for (s.times_ns[0..s.count]) |v| m = @min(m, v);
        return m;
    }

    fn max(s: *const @This()) u64 {
        var m: u64 = 0;
        for (s.times_ns[0..s.count]) |v| m = @max(m, v);
        return m;
    }
};

fn preheat() void {
    var x: u64 = 0;
    for (0..200_000_000) |_| {
        x += 1;
        std.mem.doNotOptimizeAway(x);
    }
}

const MeasuredRow = struct {
    id: []const u8,
    label: []const u8,
    iterations: usize,
    min_ns: u64,
    batch_count: usize,
};

fn writeSnapshot(io: std.Io, rows: []const MeasuredRow) !void {
    const file = try std.Io.Dir.cwd().createFile(io, snapshot_path, .{});
    defer file.close(io);

    var buf: [8192]u8 = undefined;
    var fw = file.writer(io, &buf);
    var w = &fw.interface;

    try w.print("# ngc-perf snapshot — last recorded measurements (min)\n", .{});
    try w.print("# Format: id | label | min_ns | iterations\n", .{});
    for (rows) |r| {
        try w.print("{s} | {s} | {d} | {d}\n", .{ r.id, r.label, r.min_ns, r.iterations });
    }
    try w.flush();
}

const Snapshot = struct {
    map: std.StringHashMap(u64),
    content: []u8,
    allocator: std.mem.Allocator,

    fn init(gpa: std.mem.Allocator) Snapshot {
        return .{ .map = std.StringHashMap(u64).init(gpa), .content = &.{}, .allocator = gpa };
    }

    fn deinit(s: *Snapshot) void {
        s.map.deinit();
        if (s.content.len > 0) s.allocator.free(s.content);
    }

    fn load(gpa: std.mem.Allocator, io: std.Io) !Snapshot {
        const file = std.Io.Dir.cwd().openFile(io, snapshot_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return Snapshot.init(gpa),
            else => |e| return e,
        };
        defer file.close(io);

        var buf: [4096]u8 = undefined;
        var fr = file.reader(io, &buf);
        var r = &fr.interface;
        const content = try r.allocRemaining(gpa, std.Io.Limit.limited(10_000));

        var map = std.StringHashMap(u64).init(gpa);
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \r");
            if (line.len == 0 or line[0] == '#') continue;
            var fields = std.mem.splitSequence(u8, line, " | ");
            const id = std.mem.trim(u8, fields.next() orelse continue, " ");
            _ = fields.next() orelse continue;
            const min_ns = std.fmt.parseInt(u64, std.mem.trim(u8, fields.next() orelse continue, " "), 10) catch continue;
            try map.put(id, min_ns);
        }
        return .{ .map = map, .content = content, .allocator = gpa };
    }
};

fn formatDelta(buf: []u8, current: u64, last: u64) []const u8 {
    if (last == 0) return "-";
    const delta: f64 = (@as(f64, @floatFromInt(current)) - @as(f64, @floatFromInt(last))) / @as(f64, @floatFromInt(last)) * 100.0;
    const formatted = if (delta >= 0)
        std.fmt.bufPrint(buf, "+{d:.1}%", .{delta})
    else
        std.fmt.bufPrint(buf, "{d:.1}%", .{delta});
    return formatted catch "ERR";
}

fn getBatchIters(comptime Module: type, row: anytype) usize {
    const probe_budget_ns: u64 = 5_000_000;
    const min_probe_batches: usize = 10;
    const probe_batch_target_ns: u64 = 500_000;
    const min_probe_iters_per_batch: usize = 1000;
    const probe_sma_window: usize = 5;
    const probe_stall_needed: usize = 5;
    const probe_threshold: f64 = 0.05;

    const t0 = perf_helpers.now();
    _ = Module.run(row, 1000);
    const quick_ns = @max(@as(f64, @floatFromInt(perf_helpers.now() - t0)) / 1000.0, 0.5);

    var batch_iters = @as(u64, @intFromFloat(@as(f64, @floatFromInt(probe_batch_target_ns)) / quick_ns));
    batch_iters = @max(batch_iters, min_probe_iters_per_batch);

    var ns_samples: [100]f64 = undefined;
    var ns_count: usize = 0;
    var ring: [probe_sma_window]f64 = undefined;
    var ring_count: usize = 0;
    var ring_pos: usize = 0;
    var prev_sma: f64 = 0;
    var stall: usize = 0;
    const probe_start = perf_helpers.now();

    while (ns_count < 100) {
        const batch_start = perf_helpers.now();
        _ = Module.run(row, batch_iters);
        const sample_ns = @as(f64, @floatFromInt(perf_helpers.now() - batch_start)) / @as(f64, @floatFromInt(batch_iters));
        ns_samples[ns_count] = sample_ns;
        ns_count += 1;

        if (ns_count >= min_probe_batches and perf_helpers.now() - probe_start > probe_budget_ns) break;

        if (ring_count < probe_sma_window) {
            ring[ring_count] = sample_ns;
            ring_count += 1;
        } else {
            ring[ring_pos] = sample_ns;
            ring_pos = (ring_pos + 1) % probe_sma_window;
        }

        if (ring_count >= probe_sma_window) {
            var sum: f64 = 0;
            for (ring) |v| sum += v;
            const sma = sum / @as(f64, @floatFromInt(probe_sma_window));
            if (prev_sma != 0) {
                if (@abs((sma - prev_sma) / prev_sma) <= probe_threshold) {
                    stall += 1;
                    if (stall >= probe_stall_needed and ns_count >= min_probe_batches) break;
                } else {
                    stall = 0;
                }
            }
            prev_sma = sma;
        }
    }

    const asc = struct {
        fn lt(_: void, a: f64, b: f64) bool {
            return a < b;
        }
    }.lt;
    std.mem.sort(f64, ns_samples[0..ns_count], {}, asc);
    const kept = @max(ns_count * 25 / 100, 1);
    var sum: f64 = 0;
    for (ns_samples[0..kept]) |v| sum += v;
    const t25_ns = sum / @as(f64, @floatFromInt(kept));

    const main_iters = @as(u64, @intFromFloat(@as(f64, @floatFromInt(TARGET_BATCH_NS)) / t25_ns));
    return @max(main_iters, 100);
}

fn runModule(comptime Module: type, metric: ConvergenceStat, snapshot: *const std.StringHashMap(u64), results: *std.ArrayListUnmanaged(MeasuredRow), gpa: std.mem.Allocator) !void {
    std.debug.print("=== {s} ===\n", .{Module.title});

    const hdr = "  {s:<30} {s:>8} {s:>7} {s:>7}";
    std.debug.print(hdr ++ "\n", .{ "Benchmark", "Min", "Batches", "Delta" });
    std.debug.print("  {s:-<30} {s:-<8} {s:-<7} {s:-<7}\n", .{ "", "", "", "" });

    for (&Module.rows) |row| {
        const batch_iters = getBatchIters(Module, row);
        var stats = BatchStats{ .times_ns = undefined, .count = 0 };
        var running_min: u64 = std.math.maxInt(u64);
        var running_max: u64 = 0;
        var near_min: usize = 0;
        var min_stall: usize = 0;
        var stat_ring: [PCTL_SMOOTHING]u64 = undefined;
        var stat_ring_count: usize = 0;
        var stat_ring_pos: usize = 0;
        var prev_sma: f64 = 0;
        var stat_stall: usize = 0;
        var sma_ema_delta: f64 = 0;
        var budget_hit = false;
        const batch_start = perf_helpers.now();

        while (stats.count < MAX_BATCHES) {
            const elapsed_ns = Module.run(row, batch_iters);
            stats.add(elapsed_ns);

            if (elapsed_ns > running_max) running_max = elapsed_ns;

            if (elapsed_ns < running_min) {
                running_min = elapsed_ns;
                near_min = 1;
                min_stall = 0;
            } else if (elapsed_ns <= @as(u64, @intFromFloat(@as(f64, @floatFromInt(running_min)) * NEAR_MIN_WINDOW))) {
                near_min += 1;
                min_stall += 1;
            } else {
                min_stall += 1;
            }

            if (stats.count >= MIN_BATCHES) {
                const cur_stat = switch (metric) {
                    .mean => stats.mean(),
                    .median => stats.median(),
                    .t50 => stats.t50(),
                    .t75 => stats.t75(),
                };
                if (stat_ring_count < PCTL_SMOOTHING) {
                    stat_ring[stat_ring_count] = cur_stat;
                    stat_ring_count += 1;
                } else {
                    stat_ring[stat_ring_pos] = cur_stat;
                    stat_ring_pos = (stat_ring_pos + 1) % PCTL_SMOOTHING;
                }

                if (stat_ring_count >= PCTL_SMOOTHING) {
                    var sum: u64 = 0;
                    for (stat_ring) |v| sum += v;
                    const sma = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(PCTL_SMOOTHING));
                    if (prev_sma != 0) {
                        const delta = (sma - prev_sma) / prev_sma;
                        if (sma_ema_delta == 0) sma_ema_delta = delta;
                        sma_ema_delta = sma_ema_delta * 0.8 + delta * 0.2;
                        if (@abs(delta) <= PCTL_THRESHOLD and sma_ema_delta > -0.001) {
                            stat_stall += 1;
                        } else {
                            stat_stall = 0;
                        }
                    }
                    prev_sma = sma;
                }

                if (stat_stall >= PCTL_STALL and near_min >= NEAR_MIN_REQUIRED and min_stall >= MIN_AFTER_MIN) break;
            }

            if (perf_helpers.now() - batch_start > MAX_BUDGET_MS * std.time.ns_per_ms) {
                budget_hit = true;
                break;
            }
        }

        const mn = stats.min();
        const bcount = stats.count;
        const min_ns_per_iter: f64 = @as(f64, @floatFromInt(mn)) / @as(f64, @floatFromInt(batch_iters));

        const last = snapshot.get(row.id);
        var delta_label: [16]u8 = undefined;
        const delta_str = if (last) |last_min|
            formatDelta(&delta_label, mn, last_min)
        else
            @as([]const u8, "   -");

        const budget_flag = if (budget_hit) " BUDGET" else "";

        try results.append(gpa, .{
            .id = row.id,
            .label = row.label,
            .iterations = batch_iters,
            .min_ns = mn,
            .batch_count = bcount,
        });

        std.debug.print("  {s:<30} {d:>6.2}ns {d:>7} {s:>7}{s}\n", .{
            row.id,    min_ns_per_iter, bcount,
            delta_str, budget_flag,
        });
    }
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const args = init.minimal.args.vector;
    var is_record = false;
    var metric: ConvergenceStat = .t75;
    for (args) |arg| {
        const s = std.mem.sliceTo(arg, 0);
        if (std.mem.eql(u8, s, record_flag)) {
            is_record = true;
        } else if (std.mem.eql(u8, s, "mean")) {
            metric = .mean;
        } else if (std.mem.eql(u8, s, "median")) {
            metric = .median;
        } else if (std.mem.eql(u8, s, "t50")) {
            metric = .t50;
        } else if (std.mem.eql(u8, s, "t75")) {
            metric = .t75;
        }
    }

    preheat();

    var snapshot = try Snapshot.load(gpa, io);
    defer snapshot.deinit();

    var results = std.ArrayListUnmanaged(MeasuredRow){ .items = &.{}, .capacity = 0 };

    try runModule(parse_data.Scan, metric, &snapshot.map, &results, gpa);
    try runModule(parse_data.ParseInt, metric, &snapshot.map, &results, gpa);
    try runModule(output_data.Cidr, metric, &snapshot.map, &results, gpa);
    try runModule(output_data.FormatV4, metric, &snapshot.map, &results, gpa);
    try runModule(output_data.FormatV6, metric, &snapshot.map, &results, gpa);

    if (is_record) {
        try writeSnapshot(io, results.items);
        std.debug.print("\nSnapshot written to " ++ snapshot_path ++ " ({d} entries).\n", .{results.items.len});
    } else {
        std.debug.print("\n{d} benchmarks reported.\n", .{results.items.len});
    }
}
