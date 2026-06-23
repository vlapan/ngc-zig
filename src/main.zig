const std = @import("std");
const lib = @import("lib");
const build_options = @import("build_options.zig");

pub const std_options: std.Options = .{
    .networking = false,
    .log_level = .err,
    .http_disable_tls = true,
};

pub fn main(init: std.process.Init) void {
    const alloc = init.arena.allocator();

    const config = lib.config.parseArgs(init, alloc) catch |err| {
        switch (err) {
            error.HelpRequested, error.VersionRequested => std.process.exit(0),
            error.InvalidArgs, error.MissingValue, error.UnknownArgument, error.OutOfMemory => std.process.exit(1),
        }
    };

    const result = run(init.io, alloc, config) catch {
        std.process.exit(1);
    };
    printTelemetry(result);
}

pub const RunResult = struct {
    elapsed_ms: i64,
    v4_stats: lib.parse.Stats,
    v6_stats: lib.parse.Stats,
    static_stats: lib.parse.Stats,
    v4_cidrs: usize,
    v6_cidrs: usize,
    v4_countries: usize,
    v6_countries: usize,
    v4_flattened: usize,
    v6_flattened: usize,
    v4_segments: usize,
    v6_segments: usize,
    v4_segments_filtered: usize,
    v6_segments_filtered: usize,
    time_io_ms: i64,
    time_flatten_ms: i64,
    time_cidr_ms: i64,
};

pub fn run(io: std.Io, alloc: std.mem.Allocator, config: lib.config.Config) !RunResult {
    const ts_start = std.Io.Timestamp.now(io, .awake).nanoseconds;

    const out_file = try std.Io.Dir.cwd().createFile(io, config.output, .{});
    defer out_file.close(io);

    var out_buf: [65536]u8 = undefined;
    var out_file_writer = out_file.writer(io, &out_buf);
    const writer = &out_file_writer.interface;

    var static_stats = lib.parse.Stats{};
    var v4_stats = lib.parse.Stats{};
    var v6_stats = lib.parse.Stats{};
    var v4_cidrs: usize = 0;
    var v6_cidrs: usize = 0;
    var v4_countries: usize = 0;
    var v6_countries: usize = 0;
    var v4_flattened: usize = 0;
    var v6_flattened: usize = 0;
    var v4_segments: usize = 0;
    var v6_segments: usize = 0;
    var v4_segments_filtered: usize = 0;
    var v6_segments_filtered: usize = 0;

    var time_io_ns: i128 = 0;
    var time_flatten_ns: i128 = 0;
    var time_cidr_ns: i128 = 0;

    var seen_v4 = [_]bool{false} ** 65536;
    var seen_v6 = [_]bool{false} ** 65536;
    var static_v4_ranges = std.ArrayList(lib.ip.IPv4Range).empty;
    defer static_v4_ranges.deinit(alloc);
    var static_v6_ranges = std.ArrayList(lib.ip.IPv6Range).empty;
    defer static_v6_ranges.deinit(alloc);

    var country_map: [65536]u16 = undefined;
    var filter_map: [65536]bool = undefined;

    try lib.config.setupMaps(io, config, &country_map, &filter_map);

    if (config.static_file) |static_path| {
        const ts_static_start = std.Io.Timestamp.now(io, .awake).nanoseconds;
        static_stats = try lib.parse.staticFile(io, static_path, writer, alloc, &static_v4_ranges, &static_v6_ranges);
        time_io_ns += std.Io.Timestamp.now(io, .awake).nanoseconds - ts_static_start;
    }

    if (config.ipv4_csv) |v4_path| {
        const v4_result = try lib.pipeline.processStream(
            u32,
            io,
            v4_path,
            static_v4_ranges.items,
            &seen_v4,
            writer,
            alloc,
            &country_map,
            &filter_map,
        );
        v4_stats = v4_result.stats;
        v4_cidrs = v4_result.cidrs;
        v4_countries = v4_result.countries;
        v4_flattened = v4_result.flattened;
        v4_segments = v4_result.segments;
        v4_segments_filtered = v4_result.segments_filtered;
        time_io_ns += v4_result.time_io_ns;
        time_flatten_ns += v4_result.time_flatten_ns;
        time_cidr_ns += v4_result.time_cidr_ns;
    }

    if (config.ipv6_csv) |v6_path| {
        const v6_result = try lib.pipeline.processStream(
            u128,
            io,
            v6_path,
            static_v6_ranges.items,
            &seen_v6,
            writer,
            alloc,
            &country_map,
            &filter_map,
        );
        v6_stats = v6_result.stats;
        v6_cidrs = v6_result.cidrs;
        v6_countries = v6_result.countries;
        v6_flattened = v6_result.flattened;
        v6_segments = v6_result.segments;
        v6_segments_filtered = v6_result.segments_filtered;
        time_io_ns += v6_result.time_io_ns;
        time_flatten_ns += v6_result.time_flatten_ns;
        time_cidr_ns += v6_result.time_cidr_ns;
    }

    try out_file_writer.flush();

    const ts_end = std.Io.Timestamp.now(io, .awake).nanoseconds;
    const elapsed_ms = @divTrunc(ts_end - ts_start, 1_000_000);

    return .{
        .elapsed_ms = @intCast(elapsed_ms),
        .v4_stats = v4_stats,
        .v6_stats = v6_stats,
        .static_stats = static_stats,
        .v4_cidrs = v4_cidrs,
        .v6_cidrs = v6_cidrs,
        .v4_countries = v4_countries,
        .v6_countries = v6_countries,
        .v4_flattened = v4_flattened,
        .v6_flattened = v6_flattened,
        .v4_segments = v4_segments,
        .v6_segments = v6_segments,
        .v4_segments_filtered = v4_segments_filtered,
        .v6_segments_filtered = v6_segments_filtered,
        .time_io_ms = @intCast(@divTrunc(time_io_ns, 1_000_000)),
        .time_flatten_ms = @intCast(@divTrunc(time_flatten_ns, 1_000_000)),
        .time_cidr_ms = @intCast(@divTrunc(time_cidr_ns, 1_000_000)),
    };
}

pub fn printTelemetry(r: RunResult) void {
    const total_skipped = r.static_stats.lines_skipped + r.v4_stats.lines_skipped + r.v6_stats.lines_skipped;
    const total_cidrs = r.v4_cidrs + r.v6_cidrs;

    std.debug.print("Done in {} ms.\n", .{r.elapsed_ms});
    std.debug.print("  Inputs (ranges parsed): IPv4: {}, IPv6: {}, Static: {}, Skipped: {}\n", .{
        r.v4_stats.lines_parsed,
        r.v6_stats.lines_parsed,
        r.static_stats.lines_parsed,
        total_skipped,
    });
    std.debug.print("  Phase 1 (Sweep Line): Topological Collisions: IPv4: {}, IPv6: {}\n", .{
        r.v4_stats.collisions,
        r.v6_stats.collisions,
    });
    std.debug.print("  Phase 1 (Sweep Line): Disjoint Segments: IPv4: {}, IPv6: {}\n", .{
        r.v4_flattened,
        r.v6_flattened,
    });
    std.debug.print("  Phase 1 (Sweep Line): Segments filtered: IPv4: {}, IPv6: {}\n", .{
        r.v4_segments_filtered,
        r.v6_segments_filtered,
    });
    std.debug.print("  Phase 2 (CIDR Gen): Segments processed: IPv4: {}, IPv6: {}\n", .{
        r.v4_segments,
        r.v6_segments,
    });
    std.debug.print("  Phase 2 (CIDR Gen): Static Overrides: IPv4: {}, IPv6: {}\n", .{
        r.v4_stats.overrides,
        r.v6_stats.overrides,
    });
    std.debug.print("  Phase 2 (CIDR Gen): Unique countries mapped: IPv4: {}, IPv6: {}\n", .{
        r.v4_countries,
        r.v6_countries,
    });
    std.debug.print("  Outputs (CIDR networks generated): IPv4: {}, IPv6: {}, Total: {}\n", .{
        r.v4_cidrs,
        r.v6_cidrs,
        total_cidrs,
    });
    if (r.static_stats.lines_parsed > 0) {
        std.debug.print("  Outputs (static lines echoed, not CIDRs): {}\n", .{r.static_stats.lines_parsed});
    }

    const est_ram_mb = lib.nginx.estimateRamMB(r.v4_cidrs, r.v6_cidrs);
    std.debug.print("  Estimated Nginx RAM footprint: ~{} MB (97B/CIDR, verified via profiling)\n", .{est_ram_mb});

    std.debug.print("  Pipeline Profiling: I/O & Parsing: {}ms, Phase 1 (Flatten): {}ms, Phase 2 (CIDR Gen): {}ms\n", .{
        r.time_io_ms,
        r.time_flatten_ms,
        r.time_cidr_ms,
    });
}
