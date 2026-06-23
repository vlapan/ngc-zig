/// Stage: RUN (pipeline orchestration)
/// Ties INPUT → RESOLVE → OUTPUT into a single end-to-end pipeline for one
/// IP version (u32 or u128). This is the integration boundary where real
/// file I/O meets the pure transform stages.
///
/// Pipeline flow:
///   1. CSV file (mmap) → csvLine (parse each line) → IPRange[]
///   2. Static HOLE ranges appended to IPRange[]
///   3. flatten (sweep-line) → Segment[]
///   4. filterSegments (allowlist) → Segment[] (filtered + merged)
///   5. rangeToCidrs (iterative) → CIDR text lines
///   6. Country tracking: seen_countries populated during filter step
///
/// Entry point:
///   lib.pipeline.processStream(T, io, csv_path, static_ranges, ...)
///     → StreamResult
///
/// StreamResult:
///   stats:     parse.Stats     — lines_parsed, lines_skipped, collisions, overrides
///   cidrs:     usize           — total CIDRs produced
///   countries: usize           — unique countries in output
///   segments_filtered: usize   — segments dropped by allowlist filter
///   time_io_ns, time_flatten_ns, time_cidr_ns — per-stage timing
///
/// Fixture files:
///   spec/fixtures/ipv4.csv      — 4 CSV lines (AU, CN, AU, CN)
///   spec/fixtures/ipv6.csv      — IPv6 CSV data
///   spec/fixtures/empty.csv     — empty file (0 lines)
///   spec/fixtures/ipv4-short.csv — lines with short country codes (c_val=0)
///
/// Invariants:
///   - Empty CSV → 0 CIDRs, 0 countries
///   - Static HOLE covering entire CSV → 0 CIDRs
///   - All countries filtered out → 0 CIDRs, 0 countries, segments_filtered > 0
///   - country_count matches manual scan of seen_countries
const std = @import("std");
const lib = @import("lib");
const helpers = @import("../_helpers.zig");
const testing = std.testing;

const TestEnv = helpers.TestEnv;

test "lib.pipeline.processStream: IPv4 basic pipeline" {
    var env = TestEnv.init();
    defer env.deinit();

    const static_ranges = std.ArrayList(lib.ip.IPv4Range).empty;

    const result = try lib.pipeline.processStream(
        u32,
        std.testing.io,
        "spec/fixtures/ipv4.csv",
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

test "lib.pipeline.processStream: IPv6 basic pipeline" {
    var env = TestEnv.init();
    defer env.deinit();

    const static_ranges = std.ArrayList(lib.ip.IPv6Range).empty;

    const result = try lib.pipeline.processStream(
        u128,
        std.testing.io,
        "spec/fixtures/ipv6.csv",
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

test "lib.pipeline.processStream: static ranges appended and override CSV" {
    var env = TestEnv.init();
    defer env.deinit();

    var static_ranges = std.ArrayList(lib.ip.IPv4Range).empty;
    defer static_ranges.deinit(testing.allocator);

    const hole = lib.ip.HOLE;
    try static_ranges.append(testing.allocator, .{
        .start = 16777216,
        .end = 16777216,
        .country = hole,
        .size = 0,
    });

    const result = try lib.pipeline.processStream(
        u32,
        std.testing.io,
        "spec/fixtures/ipv4.csv",
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

test "lib.pipeline.processStream: filter excludes countries" {
    var env = TestEnv.init();
    defer env.deinit();

    const static_ranges = std.ArrayList(lib.ip.IPv4Range).empty;

    @memset(&env.filter_map, false);
    const au_idx: u16 = (@as(u16, 'A') << 8) | @as(u16, 'U');
    env.filter_map[au_idx] = true;

    const result = try lib.pipeline.processStream(
        u32,
        std.testing.io,
        "spec/fixtures/ipv4.csv",
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

test "lib.pipeline.processStream: country grouping remaps" {
    var env = TestEnv.init();
    defer env.deinit();

    const static_ranges = std.ArrayList(lib.ip.IPv4Range).empty;

    const eu_idx: u16 = (@as(u16, 'E') << 8) | @as(u16, 'U');
    const au_idx: u16 = (@as(u16, 'A') << 8) | @as(u16, 'U');
    const cn_idx: u16 = (@as(u16, 'C') << 8) | @as(u16, 'N');
    env.country_map[au_idx] = eu_idx;
    env.country_map[cn_idx] = eu_idx;

    const result = try lib.pipeline.processStream(
        u32,
        std.testing.io,
        "spec/fixtures/ipv4.csv",
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

test "lib.pipeline.processStream: country counter matches manual iteration" {
    var env = TestEnv.init();
    defer env.deinit();

    const static_ranges = std.ArrayList(lib.ip.IPv4Range).empty;

    const result = try lib.pipeline.processStream(
        u32,
        std.testing.io,
        "spec/fixtures/ipv4.csv",
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

test "lib.pipeline.processStream: short country code (c_val=0)" {
    var env = TestEnv.init();
    defer env.deinit();

    const static_ranges = std.ArrayList(lib.ip.IPv4Range).empty;

    const result = try lib.pipeline.processStream(
        u32,
        std.testing.io,
        "spec/fixtures/ipv4-short.csv",
        static_ranges.items,
        &env.seen_countries,
        &env.aw.writer,
        testing.allocator,
        &env.country_map,
        &env.filter_map,
    );

    try testing.expect(result.stats.lines_parsed > 0);
    try testing.expect(result.cidrs > 0);

    const output = env.aw.writer.buffered();
    try testing.expect(std.mem.indexOf(u8, output, "\x00\x00;") != null);
}

test "lib.pipeline.processStream: empty CSV produces zero CIDRs" {
    var env = TestEnv.init();
    defer env.deinit();

    const static_ranges = std.ArrayList(lib.ip.IPv4Range).empty;

    const result = try lib.pipeline.processStream(
        u32,
        std.testing.io,
        "spec/fixtures/empty.csv",
        static_ranges.items,
        &env.seen_countries,
        &env.aw.writer,
        testing.allocator,
        &env.country_map,
        &env.filter_map,
    );

    try testing.expectEqual(@as(usize, 0), result.stats.lines_parsed);
    try testing.expectEqual(@as(usize, 0), result.cidrs);
    try testing.expectEqual(@as(usize, 0), result.countries);
}

test "lib.pipeline.processStream: all countries filtered out" {
    var env = TestEnv.init();
    defer env.deinit();

    const static_ranges = std.ArrayList(lib.ip.IPv4Range).empty;

    @memset(&env.filter_map, false);

    const result = try lib.pipeline.processStream(
        u32,
        std.testing.io,
        "spec/fixtures/ipv4.csv",
        static_ranges.items,
        &env.seen_countries,
        &env.aw.writer,
        testing.allocator,
        &env.country_map,
        &env.filter_map,
    );

    try testing.expect(result.stats.lines_parsed > 0);
    try testing.expectEqual(@as(usize, 0), result.cidrs);
    try testing.expectEqual(@as(usize, 0), result.countries);
    try testing.expect(result.segments_filtered > 0);
}

test "lib.pipeline.processStream: static HOLE covers entire CSV range" {
    var env = TestEnv.init();
    defer env.deinit();

    var static_ranges = std.ArrayList(lib.ip.IPv4Range).empty;
    defer static_ranges.deinit(testing.allocator);

    // Range 16777216..16781311 = 1.0.0.0/24, covers the first entry in
    // spec/fixtures/ipv4.csv. If that fixture changes, update this range to match.
    try static_ranges.append(testing.allocator, .{
        .start = 16777216,
        .end = 16781311,
        .country = lib.ip.HOLE,
        .size = 0,
    });

    const result = try lib.pipeline.processStream(
        u32,
        std.testing.io,
        "spec/fixtures/ipv4.csv",
        static_ranges.items,
        &env.seen_countries,
        &env.aw.writer,
        testing.allocator,
        &env.country_map,
        &env.filter_map,
    );

    try testing.expect(result.stats.lines_parsed > 0);
    try testing.expectEqual(@as(usize, 0), result.cidrs);
    try testing.expect(result.stats.overrides > 0);
}
