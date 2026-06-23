/// Scenario: STATIC OVERRIDE + FILTER
/// Validates that static HOLE + filter produces correct CIDR count, country
/// count, and exact output content.
///
/// SCENARIO-007: HOLE at 1.0.0.0 + AU-only filter.
///              Expected: 9 CIDRs, 1 country, exact string match.
const std = @import("std");
const lib = @import("lib");
const helpers = @import("../_helpers.zig");
const testing = std.testing;

const TestEnv = helpers.TestEnv;

test "SCENARIO-007: static + filter — output format invariant" {
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

    try testing.expectEqual(@as(usize, 9), result.cidrs);
    try testing.expectEqual(@as(usize, 1), result.countries);
    try testing.expectEqual(@as(usize, 4), result.stats.lines_parsed);
    try testing.expect(result.stats.overrides > 0);
    try testing.expectEqualStrings(
        "1.0.0.1/32 AU;\n1.0.0.2/31 AU;\n1.0.0.4/30 AU;\n1.0.0.8/29 AU;\n1.0.0.16/28 AU;\n1.0.0.32/27 AU;\n1.0.0.64/26 AU;\n1.0.0.128/25 AU;\n1.0.4.0/22 AU;\n",
        env.aw.writer.buffered(),
    );
}
