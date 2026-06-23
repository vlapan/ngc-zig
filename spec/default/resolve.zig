/// Stage: RESOLVE
/// Transforms a flat list of IPRange (from INPUT stage) into disjoint,
/// non-overlapping Segments. Then optionally filters segments by allowlist
/// and merges adjacent same-country segments.
///
/// Input:
///   []IPRange(T)  — raw parsed ranges (may overlap, unordered)
///
/// Intermediate:
///   []Segment(T)  — sorted, disjoint, non-overlapping, collision-resolved
///   Segment(T)    — { start: T, end: T, country: u16 }
///
/// Output (post-filter):
///   []Segment(T)  — subset of intermediate segments (only allowlisted
///                     countries), with adjacent same-country merged
///
/// Algorithms:
///   flatten(T)       — 1D sweep-line: sort range boundaries, emit segments
///                       where active country changes. HOLE entries shadow
///                       overlapping ranges (collision = country with size=0
///                       wins against larger ranges).
///   filterSegments   — iterate segments, drop those not in filter_map,
///                       merge adjacent same-country survivors.
///
/// Invariants:
///   - Output segments never overlap
///   - Consecutive segments with same country and touching ranges are merged
///   - HOLE segments survive flatten() but are skipped in CIDR generation
///   - Filter never merges different countries
///
/// Non-goals:
///   - No CIDR generation (see output.zig)
///   - No file I/O
const std = @import("std");
const lib = @import("lib");
const testing = std.testing;

const Segment = lib.flatten.Segment;

test "flatten.rangeToSegments: two ranges same country" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    var segments = std.ArrayList(Segment(u32)).empty;
    defer segments.deinit(testing.allocator);

    var ranges = std.ArrayList(lib.ip.IPv4Range).empty;
    defer ranges.deinit(testing.allocator);

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');

    try ranges.append(testing.allocator, .{ .start = 0, .end = 127, .country = us_idx, .size = 128 });
    try ranges.append(testing.allocator, .{ .start = 256, .end = 511, .country = us_idx, .size = 256 });

    const stats = try lib.flatten.flatten(u32, testing.allocator, ranges.items, &segments);

    try testing.expectEqual(@as(usize, 0), stats.collisions);
    try testing.expectEqual(@as(usize, 2), stats.flattened);
    try testing.expectEqual(@as(usize, 2), segments.items.len);

    for (segments.items) |seg| {
        _ = try lib.cidr.rangeToCidrs(u32, &aw.writer, seg.start, seg.end, seg.country);
    }

    const expected = "0.0.0.0/25 US;\n0.0.1.0/24 US;\n";
    try testing.expectEqualStrings(expected, aw.writer.buffered());
}

test "flatten.rangeToSegments: gap between same-country ranges" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    var segments = std.ArrayList(Segment(u32)).empty;
    defer segments.deinit(testing.allocator);

    var ranges = std.ArrayList(lib.ip.IPv4Range).empty;
    defer ranges.deinit(testing.allocator);

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const ca_idx: u16 = (@as(u16, 'C') << 8) | @as(u16, 'A');

    try ranges.append(testing.allocator, .{ .start = 0, .end = 127, .country = us_idx, .size = 128 });
    try ranges.append(testing.allocator, .{ .start = 128, .end = 255, .country = ca_idx, .size = 128 });
    try ranges.append(testing.allocator, .{ .start = 256, .end = 511, .country = us_idx, .size = 256 });

    const stats = try lib.flatten.flatten(u32, testing.allocator, ranges.items, &segments);

    try testing.expectEqual(@as(usize, 0), stats.collisions);
    try testing.expectEqual(@as(usize, 3), stats.flattened);

    for (segments.items) |seg| {
        _ = try lib.cidr.rangeToCidrs(u32, &aw.writer, seg.start, seg.end, seg.country);
    }

    const expected = "0.0.0.0/25 US;\n0.0.0.128/25 CA;\n0.0.1.0/24 US;\n";
    try testing.expectEqualStrings(expected, aw.writer.buffered());
}

test "flatten contiguous sibling merge" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    var segments = std.ArrayList(Segment(u32)).empty;
    defer segments.deinit(testing.allocator);

    var ranges = std.ArrayList(lib.ip.IPv4Range).empty;
    defer ranges.deinit(testing.allocator);

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');

    try ranges.append(testing.allocator, .{ .start = 0, .end = 127, .country = us_idx, .size = 128 });
    try ranges.append(testing.allocator, .{ .start = 128, .end = 255, .country = us_idx, .size = 128 });

    const stats = try lib.flatten.flatten(u32, testing.allocator, ranges.items, &segments);

    try testing.expectEqual(@as(usize, 0), stats.collisions);
    try testing.expectEqual(@as(usize, 1), stats.flattened);
    try testing.expectEqual(@as(usize, 1), segments.items.len);

    for (segments.items) |seg| {
        _ = try lib.cidr.rangeToCidrs(u32, &aw.writer, seg.start, seg.end, seg.country);
    }

    const expected = "0.0.0.0/24 US;\n";
    try testing.expectEqualStrings(expected, aw.writer.buffered());
}

test "flatten with static HOLE override" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    var segments = std.ArrayList(Segment(u32)).empty;
    defer segments.deinit(testing.allocator);

    var ranges = std.ArrayList(lib.ip.IPv4Range).empty;
    defer ranges.deinit(testing.allocator);

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const hole = lib.ip.HOLE;

    try ranges.append(testing.allocator, .{ .start = 0, .end = 255, .country = us_idx, .size = 256 });
    try ranges.append(testing.allocator, .{ .start = 10, .end = 20, .country = hole, .size = 0 });

    const stats = try lib.flatten.flatten(u32, testing.allocator, ranges.items, &segments);

    try testing.expectEqual(@as(usize, 1), stats.collisions);
    try testing.expectEqual(@as(usize, 3), stats.flattened);

    for (segments.items) |seg| {
        _ = try lib.cidr.rangeToCidrs(u32, &aw.writer, seg.start, seg.end, seg.country);
    }

    const expected = "0.0.0.0/29 US;\n0.0.0.8/31 US;\n0.0.0.21/32 US;\n0.0.0.22/31 US;\n0.0.0.24/29 US;\n0.0.0.32/27 US;\n0.0.0.64/26 US;\n0.0.0.128/25 US;\n";
    try testing.expectEqualStrings(expected, aw.writer.buffered());
}

test "filterSegments: filter with group remap" {
    const eu_idx: u16 = (@as(u16, 'E') << 8) | @as(u16, 'U');

    var segments = std.ArrayList(lib.flatten.Segment(u32)).empty;
    defer segments.deinit(testing.allocator);
    try segments.append(testing.allocator, .{ .start = 0, .end = 255, .country = eu_idx });
    try segments.append(testing.allocator, .{ .start = 256, .end = 1023, .country = eu_idx });

    var seen_countries = [_]bool{false} ** 65536;
    var filter_map = [_]bool{false} ** 65536;
    filter_map[eu_idx] = true;

    const result = lib.pipeline.filterSegments(u32, &segments, &filter_map, &seen_countries);

    try testing.expectEqual(@as(usize, 1), result.countries);
    try testing.expectEqual(@as(usize, 0), result.segments_filtered);
    try testing.expectEqual(@as(usize, 1), segments.items.len);
    try testing.expectEqual(eu_idx, segments.items[0].country);
    try testing.expectEqual(@as(u32, 0), segments.items[0].start);
    try testing.expectEqual(@as(u32, 1023), segments.items[0].end);
}

test "filterSegments: adjacent same-country segments merge" {
    const xx_idx: u16 = (@as(u16, 'X') << 8) | @as(u16, 'X');

    var segments = std.ArrayList(lib.flatten.Segment(u32)).empty;
    defer segments.deinit(testing.allocator);
    try segments.append(testing.allocator, .{ .start = 0, .end = 255, .country = xx_idx });
    try segments.append(testing.allocator, .{ .start = 256, .end = 1023, .country = xx_idx });
    try segments.append(testing.allocator, .{ .start = 1024, .end = 2047, .country = xx_idx });

    var seen_countries = [_]bool{false} ** 65536;
    var filter_map = [_]bool{true} ** 65536;

    const result = lib.pipeline.filterSegments(u32, &segments, &filter_map, &seen_countries);

    try testing.expectEqual(@as(usize, 1), result.countries);
    try testing.expectEqual(@as(usize, 0), result.segments_filtered);
    try testing.expectEqual(@as(usize, 1), segments.items.len);
    try testing.expectEqual(@as(u32, 0), segments.items[0].start);
    try testing.expectEqual(@as(u32, 2047), segments.items[0].end);
}

test "filterSegments: different-country segments not merged" {
    const au_idx: u16 = (@as(u16, 'A') << 8) | @as(u16, 'U');
    const cn_idx: u16 = (@as(u16, 'C') << 8) | @as(u16, 'N');

    var segments = std.ArrayList(lib.flatten.Segment(u32)).empty;
    defer segments.deinit(testing.allocator);
    try segments.append(testing.allocator, .{ .start = 0, .end = 255, .country = au_idx });
    try segments.append(testing.allocator, .{ .start = 256, .end = 1023, .country = cn_idx });

    var seen_countries = [_]bool{false} ** 65536;
    var filter_map = [_]bool{true} ** 65536;

    const result = lib.pipeline.filterSegments(u32, &segments, &filter_map, &seen_countries);

    try testing.expectEqual(@as(usize, 2), result.countries);
    try testing.expectEqual(@as(usize, 0), result.segments_filtered);
    try testing.expectEqual(@as(usize, 2), segments.items.len);
}

test "filterSegments: filtered segment leaves gap (no false merge)" {
    const au_idx: u16 = (@as(u16, 'A') << 8) | @as(u16, 'U');
    const de_idx: u16 = (@as(u16, 'D') << 8) | @as(u16, 'E');

    var segments = std.ArrayList(lib.flatten.Segment(u32)).empty;
    defer segments.deinit(testing.allocator);
    try segments.append(testing.allocator, .{ .start = 0, .end = 255, .country = au_idx });
    try segments.append(testing.allocator, .{ .start = 256, .end = 511, .country = de_idx });
    try segments.append(testing.allocator, .{ .start = 512, .end = 767, .country = au_idx });

    var seen_countries = [_]bool{false} ** 65536;
    var filter_map = [_]bool{false} ** 65536;
    filter_map[au_idx] = true;

    const result = lib.pipeline.filterSegments(u32, &segments, &filter_map, &seen_countries);

    try testing.expectEqual(@as(usize, 1), result.countries);
    try testing.expectEqual(@as(usize, 1), result.segments_filtered);
    try testing.expectEqual(@as(usize, 2), segments.items.len);
}

test "filterSegments: all segments filtered out" {
    const au_idx: u16 = (@as(u16, 'A') << 8) | @as(u16, 'U');

    var segments = std.ArrayList(lib.flatten.Segment(u32)).empty;
    defer segments.deinit(testing.allocator);
    try segments.append(testing.allocator, .{ .start = 0, .end = 255, .country = au_idx });

    var seen_countries = [_]bool{false} ** 65536;
    var filter_map = [_]bool{false} ** 65536;

    const result = lib.pipeline.filterSegments(u32, &segments, &filter_map, &seen_countries);

    try testing.expectEqual(@as(usize, 0), result.countries);
    try testing.expectEqual(@as(usize, 1), result.segments_filtered);
    try testing.expectEqual(@as(usize, 0), segments.items.len);
}
