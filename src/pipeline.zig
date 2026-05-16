const std = @import("std");
const ip_mod = @import("ip.zig");
const flatten_mod = @import("flatten.zig");
const parser_mod = @import("parser.zig");
const cidr_mod = @import("cidr.zig");

pub const StreamResult = struct {
    stats: parser_mod.Stats,
    cidrs: usize,
    countries: usize,
    flattened: usize,
    segments: usize,
    time_io_ns: i128,
    time_flatten_ns: i128,
    time_cidr_ns: i128,
};

pub fn processStream(
    comptime T: type,
    io: std.Io,
    path: []const u8,
    static_ranges: []const ip_mod.IPRange(T),
    seen_countries: *[65536]bool,
    writer: *std.Io.Writer,
    alloc: std.mem.Allocator,
    country_map: *const [65536]u16,
    filter_map: *const [65536]bool,
) !StreamResult {
    const ts_start = std.Io.Timestamp.now(io, .awake).nanoseconds;

    var ranges = std.ArrayList(ip_mod.IPRange(T)).empty;
    defer ranges.deinit(alloc);
    var stats = try parser_mod.parseFile(T, io, path, &ranges, alloc, seen_countries, country_map, filter_map);
    const ts_parsed = std.Io.Timestamp.now(io, .awake).nanoseconds;
    const time_io_ns = ts_parsed - ts_start;

    for (static_ranges) |r| {
        try ranges.append(alloc, r);
    }

    var segments = std.ArrayList(flatten_mod.Segment(T)).empty;
    defer segments.deinit(alloc);

    const flatten_stats = try flatten_mod.flatten(T, alloc, ranges.items, &segments);
    stats.collisions = flatten_stats.collisions;
    stats.overrides = flatten_stats.overrides;
    const flattened = flatten_stats.flattened;

    const ts_flattened = std.Io.Timestamp.now(io, .awake).nanoseconds;
    const time_flatten_ns = ts_flattened - ts_parsed;

    var cidrs: usize = 0;
    for (segments.items) |seg| {
        const cidr_stats = try cidr_mod.rangeToCidrs(T, writer, seg.start, seg.end, seg.country);
        cidrs += cidr_stats.cidrs;
    }
    const seg_count = segments.items.len;

    const ts_cidr = std.Io.Timestamp.now(io, .awake).nanoseconds;
    const time_cidr_ns = ts_cidr - ts_flattened;

    var countries: usize = 0;
    for (seen_countries) |seen| {
        if (seen) countries += 1;
    }

    return StreamResult{
        .stats = stats,
        .cidrs = cidrs,
        .countries = countries,
        .flattened = flattened,
        .segments = seg_count,
        .time_io_ns = time_io_ns,
        .time_flatten_ns = time_flatten_ns,
        .time_cidr_ns = time_cidr_ns,
    };
}

const testing = std.testing;

const TestEnv = struct {
    country_map: [65536]u16,
    filter_map: [65536]bool,
    seen_countries: [65536]bool,
    aw: std.Io.Writer.Allocating,

    fn init() TestEnv {
        var country_map = [_]u16{0} ** 65536;
        for (0..65536) |i| country_map[i] = @intCast(i);
        return .{
            .country_map = country_map,
            .filter_map = [_]bool{true} ** 65536,
            .seen_countries = [_]bool{false} ** 65536,
            .aw = .init(testing.allocator),
        };
    }

    fn deinit(self: *TestEnv) void {
        self.aw.deinit();
    }
};

test "pipeline.processStream: IPv4 basic pipeline" {
    var env = TestEnv.init();
    defer env.deinit();

    const static_ranges = std.ArrayList(ip_mod.IPv4Range).empty;

    const result = try processStream(
        u32,
        std.testing.io,
        "test/ipv4.csv",
        static_ranges.items,
        &env.seen_countries,
        &env.aw.writer,
        testing.allocator,
        &env.country_map,
        &env.filter_map,
    );

    try testing.expect(result.stats.lines_parsed > 0);
    try testing.expect(result.cidrs > 0);
    try testing.expect(result.countries > 0);
    try testing.expect(result.time_io_ns > 0);
    try testing.expect(result.time_flatten_ns > 0);
    try testing.expect(result.time_cidr_ns > 0);
}

test "pipeline.processStream: IPv6 basic pipeline" {
    var env = TestEnv.init();
    defer env.deinit();

    const static_ranges = std.ArrayList(ip_mod.IPv6Range).empty;

    const result = try processStream(
        u128,
        std.testing.io,
        "test/ipv6.csv",
        static_ranges.items,
        &env.seen_countries,
        &env.aw.writer,
        testing.allocator,
        &env.country_map,
        &env.filter_map,
    );

    try testing.expect(result.stats.lines_parsed > 0);
    try testing.expect(result.cidrs > 0);
    try testing.expect(result.countries > 0);
}

test "pipeline.processStream: static ranges appended and override CSV" {
    var env = TestEnv.init();
    defer env.deinit();

    var static_ranges = std.ArrayList(ip_mod.IPv4Range).empty;
    defer static_ranges.deinit(testing.allocator);

    const hole: u16 = 0xFFFF;
    try static_ranges.append(testing.allocator, .{
        .start = 16777216,
        .end = 16777216,
        .country = hole,
        .size = 0,
    });

    const result = try processStream(
        u32,
        std.testing.io,
        "test/ipv4.csv",
        static_ranges.items,
        &env.seen_countries,
        &env.aw.writer,
        testing.allocator,
        &env.country_map,
        &env.filter_map,
    );

    try testing.expect(result.stats.lines_parsed > 0);
    try testing.expect(result.stats.overrides > 0);
    try testing.expect(result.cidrs > 0);
}

test "pipeline.processStream: filter excludes countries" {
    var env = TestEnv.init();
    defer env.deinit();

    const static_ranges = std.ArrayList(ip_mod.IPv4Range).empty;

    @memset(&env.filter_map, false);
    const au_idx: u16 = (@as(u16, 'A') << 8) | @as(u16, 'U');
    env.filter_map[au_idx] = true;

    const result = try processStream(
        u32,
        std.testing.io,
        "test/ipv4.csv",
        static_ranges.items,
        &env.seen_countries,
        &env.aw.writer,
        testing.allocator,
        &env.country_map,
        &env.filter_map,
    );

    try testing.expect(result.stats.lines_parsed > 0);
    try testing.expect(result.stats.lines_filtered > 0);
    try testing.expectEqual(@as(usize, 1), result.countries);
}

test "pipeline.processStream: country grouping remaps" {
    var env = TestEnv.init();
    defer env.deinit();

    const static_ranges = std.ArrayList(ip_mod.IPv4Range).empty;

    const eu_idx: u16 = (@as(u16, 'E') << 8) | @as(u16, 'U');
    const au_idx: u16 = (@as(u16, 'A') << 8) | @as(u16, 'U');
    const cn_idx: u16 = (@as(u16, 'C') << 8) | @as(u16, 'N');
    env.country_map[au_idx] = eu_idx;
    env.country_map[cn_idx] = eu_idx;

    const result = try processStream(
        u32,
        std.testing.io,
        "test/ipv4.csv",
        static_ranges.items,
        &env.seen_countries,
        &env.aw.writer,
        testing.allocator,
        &env.country_map,
        &env.filter_map,
    );

    try testing.expect(result.stats.lines_parsed > 0);
    try testing.expectEqual(@as(usize, 1), result.countries);
    try testing.expect(env.seen_countries[eu_idx]);
}
