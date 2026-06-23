/// Scenario: BASIC PIPELINE
/// Exercises the full IPv4 and IPv6 pipelines with filter and group remap.
/// Verifies exact CIDR output counts and content.
///
/// SCENARIO-001: filter + group — AU-only filter, CN→ZZ remap, expect
///                2 AU CIDRs (1.0.0.0/24 hole-punched by HOLE from static? No,
///                no static here — just AU ranges from CSV with CN excluded)
///              Result: 4 lines parsed, 2 CIDRs, 1 country, 2 segments filtered.
///
/// SCENARIO-002: IPv6 + static HOLE — IPv6 fixture with HOLE at ::1/128.
///              Result: 5 lines parsed, overrides > 0, CIDRs > 0.
/// Scenario: CLI ORCHESTRATION
/// Tests the full `main.run()` function which ties all pipeline stages
/// together with real file I/O (CSV, static, output).
///
/// SCENARIO-008: basic v4 run with known fixtures
///              Verifies output file is created, contains CIDR lines,
///              and has the correct format.
const std = @import("std");
const lib = @import("lib");
const helpers = @import("../_helpers.zig");
const testing = std.testing;

const TestEnv = helpers.TestEnv;

test "SCENARIO-001: filter + group — group remap causes filtering" {
    var env = TestEnv.init();
    defer env.deinit();

    const static_ranges = std.ArrayList(lib.ip.IPv4Range).empty;

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
    try testing.expectEqual(@as(usize, 2), result.cidrs);
    try testing.expectEqual(@as(usize, 1), result.countries);
    try testing.expectEqual(@as(usize, 2), result.segments_filtered);
    try testing.expectEqualStrings("1.0.0.0/24 AU;\n1.0.4.0/22 AU;\n", env.aw.writer.buffered());
}

test "SCENARIO-002: IPv6 pipeline with static HOLE override" {
    var env = TestEnv.init();
    defer env.deinit();

    var static_ranges = std.ArrayList(lib.ip.IPv6Range).empty;
    defer static_ranges.deinit(testing.allocator);

    try static_ranges.append(testing.allocator, .{
        .start = 1,
        .end = 1,
        .country = lib.ip.HOLE,
        .size = 0,
    });

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

    try testing.expectEqual(@as(usize, 5), result.stats.lines_parsed);
    try testing.expect(result.stats.overrides > 0);
    try testing.expect(result.cidrs > 0);
    try helpers.validateOutputFormat(env.aw.writer.buffered());
}
