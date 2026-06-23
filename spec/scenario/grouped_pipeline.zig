/// Scenario: GROUPED PIPELINE
/// Tests the interaction of static HOLE + group remap + filter simultaneously.
///
/// SCENARIO-005: HOLE at 1.0.0.0, CN→ZZ remap, AU-only filter.
///              Expected: 9 AU CIDRs, 1 country (AU), overrides=1.
///
/// SCENARIO-006: IPv4 + IPv6 cumulative run — both pipelines write to
///              separate buffers, total CIDRs > each individually.
const std = @import("std");
const lib = @import("lib");
const helpers = @import("../_helpers.zig");
const testing = std.testing;

const TestEnv = helpers.TestEnv;

test "SCENARIO-005: static + group + filter — all three together" {
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

    const zz_idx: u16 = (@as(u16, 'Z') << 8) | @as(u16, 'Z');
    const cn_idx: u16 = (@as(u16, 'C') << 8) | @as(u16, 'N');
    env.country_map[cn_idx] = zz_idx;

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
    try testing.expectEqual(@as(usize, 9), result.cidrs);
    try testing.expectEqual(@as(usize, 1), result.countries);
    try testing.expect(result.segments_filtered > 0);
    try testing.expectEqualStrings(
        "1.0.0.1/32 AU;\n1.0.0.2/31 AU;\n1.0.0.4/30 AU;\n1.0.0.8/29 AU;\n1.0.0.16/28 AU;\n1.0.0.32/27 AU;\n1.0.0.64/26 AU;\n1.0.0.128/25 AU;\n1.0.4.0/22 AU;\n",
        env.aw.writer.buffered(),
    );
}

test "SCENARIO-006: IPv4 + IPv6 cumulative pipeline" {
    var env = TestEnv.init();
    defer env.deinit();

    const static_ranges_v4 = std.ArrayList(lib.ip.IPv4Range).empty;

    const result_v4 = try lib.pipeline.processStream(
        u32,
        std.testing.io,
        "spec/fixtures/ipv4.csv",
        static_ranges_v4.items,
        &env.seen_countries,
        &env.aw.writer,
        testing.allocator,
        &env.country_map,
        &env.filter_map,
    );

    try testing.expectEqual(@as(usize, 5), result_v4.cidrs);

    var env_v6 = TestEnv.init();
    defer env_v6.deinit();

    const static_ranges_v6 = std.ArrayList(lib.ip.IPv6Range).empty;

    const result_v6 = try lib.pipeline.processStream(
        u128,
        std.testing.io,
        "spec/fixtures/ipv6.csv",
        static_ranges_v6.items,
        &env_v6.seen_countries,
        &env_v6.aw.writer,
        testing.allocator,
        &env_v6.country_map,
        &env_v6.filter_map,
    );

    const total_cidrs: usize = result_v4.cidrs + result_v6.cidrs;
    try testing.expect(total_cidrs > result_v4.cidrs);
    try testing.expect(total_cidrs > result_v6.cidrs);
    try testing.expectEqual(@as(usize, 4), result_v4.stats.lines_parsed);
    try testing.expectEqual(@as(usize, 5), result_v6.stats.lines_parsed);
    try helpers.validateOutputFormat(env.aw.writer.buffered());
    try helpers.validateOutputFormat(env_v6.aw.writer.buffered());
}
