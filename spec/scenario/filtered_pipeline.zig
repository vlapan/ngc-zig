/// Scenario: FILTERED PIPELINE
/// Tests the interaction between static HOLE overrides and the allowlist filter.
///
/// SCENARIO-003: static HOLE at 1.0.0.0 (first CSV line) + AU-only filter.
///              Expected: 9 AU CIDRs (1.0.0.1..1.0.0.255 split into 8 CIDRs
///              because 1.0.0.0 is HOLE'd, plus 1.0.4.0/22).
///
/// SCENARIO-004: same CSV with and without filter, verify filtered output
///              is smaller than full output.
const std = @import("std");
const lib = @import("lib");
const helpers = @import("../_helpers.zig");
const testing = std.testing;

const TestEnv = helpers.TestEnv;

test "SCENARIO-003: static HOLE + filter — both effects visible" {
    var env = TestEnv.init();
    defer env.deinit();

    var static_ranges = std.ArrayList(lib.ip.IPv4Range).empty;
    defer static_ranges.deinit(testing.allocator);

    try static_ranges.append(testing.allocator, .{
        .start = 16777216,
        .end = 16777216,
        .country = lib.ip.HOLE,
        .size = 0,
    });

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

    try testing.expectEqual(@as(usize, 4), result.stats.lines_parsed);
    try testing.expectEqual(@as(usize, 1), result.stats.overrides);
    try testing.expectEqual(@as(usize, 1), result.stats.collisions);
    try testing.expectEqual(@as(usize, 9), result.cidrs);
    try testing.expectEqual(@as(usize, 1), result.countries);
    try testing.expectEqualStrings(
        "1.0.0.1/32 AU;\n1.0.0.2/31 AU;\n1.0.0.4/30 AU;\n1.0.0.8/29 AU;\n1.0.0.16/28 AU;\n1.0.0.32/27 AU;\n1.0.0.64/26 AU;\n1.0.0.128/25 AU;\n1.0.4.0/22 AU;\n",
        env.aw.writer.buffered(),
    );
}

test "SCENARIO-004: filter reduces output size" {
    var env = TestEnv.init();
    defer env.deinit();

    var full_aw = std.Io.Writer.Allocating.init(testing.allocator);
    defer full_aw.deinit();

    const static_ranges = std.ArrayList(lib.ip.IPv4Range).empty;

    const full_result = try lib.pipeline.processStream(
        u32,
        std.testing.io,
        "spec/fixtures/ipv4.csv",
        static_ranges.items,
        &env.seen_countries,
        &full_aw.writer,
        testing.allocator,
        &env.country_map,
        &env.filter_map,
    );

    try testing.expectEqual(@as(usize, 5), full_result.cidrs);

    var filtered_env = TestEnv.init();
    defer filtered_env.deinit();

    @memset(&filtered_env.filter_map, false);
    const au_idx: u16 = (@as(u16, 'A') << 8) | @as(u16, 'U');
    filtered_env.filter_map[au_idx] = true;

    const filtered_result = try lib.pipeline.processStream(
        u32,
        std.testing.io,
        "spec/fixtures/ipv4.csv",
        static_ranges.items,
        &filtered_env.seen_countries,
        &filtered_env.aw.writer,
        testing.allocator,
        &filtered_env.country_map,
        &filtered_env.filter_map,
    );

    try testing.expectEqual(@as(usize, 2), filtered_result.cidrs);

    const full_output = full_aw.writer.buffered();
    const filtered_output = filtered_env.aw.writer.buffered();
    try testing.expect(filtered_output.len < full_output.len);
    try helpers.validateOutputFormat(full_output);
    try helpers.validateOutputFormat(filtered_output);
}
