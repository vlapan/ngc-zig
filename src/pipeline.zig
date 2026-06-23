const std = @import("std");
const ip_mod = @import("ip.zig");
const flatten_mod = @import("flatten.zig");
const parse = @import("parse.zig");
const cidr_mod = @import("cidr.zig");

pub const StreamResult = struct {
    stats: parse.Stats,
    cidrs: usize,
    countries: usize,
    flattened: usize,
    segments: usize,
    segments_filtered: usize,
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
    var stats = try parse.csvFile(T, io, path, &ranges, alloc, country_map);
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

    @memset(seen_countries, false);

    const filter_result = filterSegments(T, &segments, filter_map, seen_countries);

    var cidrs: usize = 0;
    for (segments.items) |seg| {
        const cidr_stats = try cidr_mod.rangeToCidrs(T, writer, seg.start, seg.end, seg.country);
        cidrs += cidr_stats.cidrs;
    }
    const seg_count = segments.items.len;

    const ts_cidr = std.Io.Timestamp.now(io, .awake).nanoseconds;
    const time_cidr_ns = ts_cidr - ts_flattened;

    return StreamResult{
        .stats = stats,
        .cidrs = cidrs,
        .countries = filter_result.countries,
        .flattened = flattened,
        .segments = seg_count,
        .segments_filtered = filter_result.segments_filtered,
        .time_io_ns = time_io_ns,
        .time_flatten_ns = time_flatten_ns,
        .time_cidr_ns = time_cidr_ns,
    };
}

pub const FilterResult = struct {
    segments_filtered: usize,
    countries: usize,
};

pub fn filterSegments(
    comptime T: type,
    segments: *std.ArrayList(flatten_mod.Segment(T)),
    filter_map: *const [65536]bool,
    seen_countries: *[65536]bool,
) FilterResult {
    var segments_filtered: usize = 0;
    var countries: usize = 0;
    var write_idx: usize = 0;
    for (segments.items) |seg| {
        if (!filter_map[seg.country]) {
            segments_filtered += 1;
            continue;
        }
        if (write_idx > 0 and
            segments.items[write_idx - 1].end + 1 == seg.start and
            segments.items[write_idx - 1].country == seg.country)
        {
            segments.items[write_idx - 1].end = seg.end;
        } else {
            segments.items[write_idx] = seg;
            write_idx += 1;
        }
        if (!seen_countries[seg.country]) {
            seen_countries[seg.country] = true;
            countries += 1;
        }
    }
    segments.shrinkRetainingCapacity(write_idx);
    return .{ .segments_filtered = segments_filtered, .countries = countries };
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
    try testing.expect(result.segments_filtered > 0);
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

test "pipeline.processStream: country counter matches manual iteration" {
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

    var manual_count: usize = 0;
    for (env.seen_countries) |seen| {
        if (seen) manual_count += 1;
    }
    try testing.expectEqual(manual_count, result.countries);
}

test "filterSegments: filter with group remap" {
    const eu_idx: u16 = (@as(u16, 'E') << 8) | @as(u16, 'U');

    var segments = std.ArrayList(flatten_mod.Segment(u32)).empty;
    defer segments.deinit(testing.allocator);
    try segments.append(testing.allocator, .{ .start = 0, .end = 255, .country = eu_idx });
    try segments.append(testing.allocator, .{ .start = 256, .end = 1023, .country = eu_idx });

    var seen_countries = [_]bool{false} ** 65536;
    var filter_map = [_]bool{false} ** 65536;
    filter_map[eu_idx] = true;

    const result = filterSegments(u32, &segments, &filter_map, &seen_countries);

    try testing.expectEqual(@as(usize, 1), result.countries);
    try testing.expectEqual(@as(usize, 0), result.segments_filtered);
    try testing.expectEqual(@as(usize, 1), segments.items.len);
    try testing.expectEqual(eu_idx, segments.items[0].country);
    try testing.expectEqual(@as(u32, 0), segments.items[0].start);
    try testing.expectEqual(@as(u32, 1023), segments.items[0].end);
}

test "filterSegments: adjacent same-country segments merge" {
    const xx_idx: u16 = (@as(u16, 'X') << 8) | @as(u16, 'X');

    var segments = std.ArrayList(flatten_mod.Segment(u32)).empty;
    defer segments.deinit(testing.allocator);
    try segments.append(testing.allocator, .{ .start = 0, .end = 255, .country = xx_idx });
    try segments.append(testing.allocator, .{ .start = 256, .end = 1023, .country = xx_idx });
    try segments.append(testing.allocator, .{ .start = 1024, .end = 2047, .country = xx_idx });

    var seen_countries = [_]bool{false} ** 65536;
    var filter_map = [_]bool{true} ** 65536;

    const result = filterSegments(u32, &segments, &filter_map, &seen_countries);

    try testing.expectEqual(@as(usize, 1), result.countries);
    try testing.expectEqual(@as(usize, 0), result.segments_filtered);
    try testing.expectEqual(@as(usize, 1), segments.items.len);
    try testing.expectEqual(@as(u32, 0), segments.items[0].start);
    try testing.expectEqual(@as(u32, 2047), segments.items[0].end);
}

test "filterSegments: different-country segments not merged" {
    const au_idx: u16 = (@as(u16, 'A') << 8) | @as(u16, 'U');
    const cn_idx: u16 = (@as(u16, 'C') << 8) | @as(u16, 'N');

    var segments = std.ArrayList(flatten_mod.Segment(u32)).empty;
    defer segments.deinit(testing.allocator);
    try segments.append(testing.allocator, .{ .start = 0, .end = 255, .country = au_idx });
    try segments.append(testing.allocator, .{ .start = 256, .end = 1023, .country = cn_idx });

    var seen_countries = [_]bool{false} ** 65536;
    var filter_map = [_]bool{true} ** 65536;

    const result = filterSegments(u32, &segments, &filter_map, &seen_countries);

    try testing.expectEqual(@as(usize, 2), result.countries);
    try testing.expectEqual(@as(usize, 0), result.segments_filtered);
    try testing.expectEqual(@as(usize, 2), segments.items.len);
}

test "filterSegments: filtered segment leaves gap (no false merge)" {
    const au_idx: u16 = (@as(u16, 'A') << 8) | @as(u16, 'U');
    const de_idx: u16 = (@as(u16, 'D') << 8) | @as(u16, 'E');

    var segments = std.ArrayList(flatten_mod.Segment(u32)).empty;
    defer segments.deinit(testing.allocator);
    try segments.append(testing.allocator, .{ .start = 0, .end = 255, .country = au_idx });
    try segments.append(testing.allocator, .{ .start = 256, .end = 511, .country = de_idx });
    try segments.append(testing.allocator, .{ .start = 512, .end = 767, .country = au_idx });

    var seen_countries = [_]bool{false} ** 65536;
    var filter_map = [_]bool{false} ** 65536;
    filter_map[au_idx] = true; // DE filtered out

    const result = filterSegments(u32, &segments, &filter_map, &seen_countries);

    try testing.expectEqual(@as(usize, 1), result.countries);
    try testing.expectEqual(@as(usize, 1), result.segments_filtered);
    // AU segments are not adjacent (256 gap where DE was) → stay separate
    try testing.expectEqual(@as(usize, 2), segments.items.len);
}

test "pipeline.processStream: short country code (c_val=0)" {
    var env = TestEnv.init();
    defer env.deinit();

    const static_ranges = std.ArrayList(ip_mod.IPv4Range).empty;

    const result = try processStream(
        u32,
        std.testing.io,
        "test/ipv4-short.csv",
        static_ranges.items,
        &env.seen_countries,
        &env.aw.writer,
        testing.allocator,
        &env.country_map,
        &env.filter_map,
    );

    try testing.expect(result.stats.lines_parsed > 0);
    // Short code (c_val=0) passes through and gets a CIDR block
    try testing.expect(result.cidrs > 0);
}
