/// Stage: OPTIONS (configuration)
/// Parses CLI arguments into Config, then builds country_map and filter_map
/// from inline groups/filters or from group/filter files.
///
/// CLI interface:
///   ngc --ipv4 <path> [--ipv6 <path>] --output <path> \
///       [--static <path>] [--group <spec>]... [--filter <cc>]... \
///       [--groups-file <path>] [--filters-file <path>]
///
///   Flags:
///     --ipv4, --ipv6        — input CSV paths (at least one required)
///     --output              — output file path (required)
///     --static              — static CIDR override file path
///     --group <target:src,...> — country group remap (e.g. "EU:FR,DE")
///     --filter <cc,...>     — allowlisted countries (e.g. "US,CA")
///     --groups-file         — file with one --group spec per line
///     --filters-file        — file with one --filter spec per line
///     --help, -h            — print usage (ParseError.HelpRequested)
///     --version, -v         — print version (ParseError.VersionRequested)
///
/// Data structures:
///   Config  — { ipv4_csv, ipv6_csv, output, static_file,
///                groups: []const []const u8, filters: []const []const u8,
///                groups_file, filters_file }
///
///   country_map: [65536]u16  — identity by default, remaps on --group
///   filter_map:  [65536]bool — all-true by default, narrows on --filter
///
/// Group file line format:
///   <target_cc>:<src_cc>,<src_cc>,...
///   Example: "EU:FR,DE" — remaps FR and DE to EU
///   Empty lines, whitespace-only, and # comment lines are ignored.
///
/// Filter file line format:
///   <cc>,<cc>,...
///   Example: "US,CA" — only US and CA pass the filter
///   Empty lines, whitespace-only, and # comment lines are ignored.
///
/// Functions:
///   parseArgList(args, alloc)     — raw string args → Config | ParseError
///   parseGroupLine(line, map)     — "EU:FR,DE" → populates country_map
///   parseFilterLine(line, map)    — "US,CA" → populates filter_map
///   setupMaps(config, maps)       — inline groups/filters + file-based
///   setupMapsInline(config, maps) — inline groups/filters only (no I/O)
///   Config.deinit(alloc)          — frees all owned strings
///
/// Invariants:
///   - Default filter_map = all-true (allow identity)
///   - Default country_map = identity (c_val → c_val)
///   - Unknown flags → UnknownArgument error
///   - Missing --output or no input files → InvalidArgs error
///   - Empty groups-file/filters-file → no-op (not an error)
const std = @import("std");
const lib = @import("lib");
const helpers = @import("../_helpers.zig");
const testing = std.testing;

const parse_arg_list_rows = [_]struct {
    id: []const u8,
    given: []const u8,
    args: []const []const u8,
    expected_error: enum { none, InvalidArgs, UnknownArgument, MissingValue, HelpRequested, VersionRequested },
    expected_ipv4: ?[]const u8,
    expected_ipv6: ?[]const u8,
    expected_output: ?[]const u8,
    expected_static: ?[]const u8,
    expected_groups_count: usize,
    expected_filters_count: usize,
}{
    .{ .id = "ARG-001", .given = "minimal valid args (--output only)", .args = &.{ "ngc", "--ipv4", "ipv4.csv", "--output", "out.conf" }, .expected_error = .none, .expected_ipv4 = "ipv4.csv", .expected_ipv6 = null, .expected_output = "out.conf", .expected_static = null, .expected_groups_count = 0, .expected_filters_count = 0 },
    .{ .id = "ARG-002", .given = "all flags", .args = &.{ "ngc", "--ipv4", "ipv4.csv", "--ipv6", "ipv6.csv", "--output", "out.conf", "--static", "static.conf", "--groups-file", "groups.txt", "--group", "EU:FR,DE", "--filters-file", "filters.txt", "--filter", "US,CA" }, .expected_error = .none, .expected_ipv4 = "ipv4.csv", .expected_ipv6 = "ipv6.csv", .expected_output = "out.conf", .expected_static = "static.conf", .expected_groups_count = 1, .expected_filters_count = 1 },
    .{ .id = "ARG-003", .given = "missing --output returns InvalidArgs", .args = &.{ "ngc", "--ipv4", "ipv4.csv" }, .expected_error = .InvalidArgs, .expected_ipv4 = null, .expected_ipv6 = null, .expected_output = null, .expected_static = null, .expected_groups_count = 0, .expected_filters_count = 0 },
    .{ .id = "ARG-004", .given = "no input files returns InvalidArgs", .args = &.{ "ngc", "--output", "out.conf" }, .expected_error = .InvalidArgs, .expected_ipv4 = null, .expected_ipv6 = null, .expected_output = null, .expected_static = null, .expected_groups_count = 0, .expected_filters_count = 0 },
    .{ .id = "ARG-005", .given = "unknown argument returns UnknownArgument", .args = &.{ "ngc", "--bogus", "x", "--output", "out.conf" }, .expected_error = .UnknownArgument, .expected_ipv4 = null, .expected_ipv6 = null, .expected_output = null, .expected_static = null, .expected_groups_count = 0, .expected_filters_count = 0 },
    .{ .id = "ARG-006", .given = "missing value after --ipv4 at end", .args = &.{ "ngc", "--ipv4" }, .expected_error = .MissingValue, .expected_ipv4 = null, .expected_ipv6 = null, .expected_output = null, .expected_static = null, .expected_groups_count = 0, .expected_filters_count = 0 },
    .{ .id = "ARG-007", .given = "missing value after --output", .args = &.{ "ngc", "--ipv4", "ipv4.csv", "--output" }, .expected_error = .MissingValue, .expected_ipv4 = null, .expected_ipv6 = null, .expected_output = null, .expected_static = null, .expected_groups_count = 0, .expected_filters_count = 0 },
    .{ .id = "ARG-008", .given = "missing value after --group", .args = &.{ "ngc", "--ipv4", "ipv4.csv", "--output", "out.conf", "--group" }, .expected_error = .MissingValue, .expected_ipv4 = null, .expected_ipv6 = null, .expected_output = null, .expected_static = null, .expected_groups_count = 0, .expected_filters_count = 0 },
    .{ .id = "ARG-009", .given = "multiple --group flags", .args = &.{ "ngc", "--ipv4", "ipv4.csv", "--output", "out.conf", "--group", "EU:FR,DE", "--group", "NA:US,CA,MX" }, .expected_error = .none, .expected_ipv4 = "ipv4.csv", .expected_ipv6 = null, .expected_output = "out.conf", .expected_static = null, .expected_groups_count = 2, .expected_filters_count = 0 },
    .{ .id = "ARG-010", .given = "multiple --filter flags", .args = &.{ "ngc", "--ipv4", "ipv4.csv", "--output", "out.conf", "--filter", "US", "--filter", "CA" }, .expected_error = .none, .expected_ipv4 = "ipv4.csv", .expected_ipv6 = null, .expected_output = "out.conf", .expected_static = null, .expected_groups_count = 0, .expected_filters_count = 2 },
    .{ .id = "ARG-011", .given = "--static as sole input is valid", .args = &.{ "ngc", "--static", "static.conf", "--output", "out.conf" }, .expected_error = .none, .expected_ipv4 = null, .expected_ipv6 = null, .expected_output = "out.conf", .expected_static = "static.conf", .expected_groups_count = 0, .expected_filters_count = 0 },
    .{ .id = "ARG-012", .given = "empty args (just program name) returns InvalidArgs", .args = &.{"ngc"}, .expected_error = .InvalidArgs, .expected_ipv4 = null, .expected_ipv6 = null, .expected_output = null, .expected_static = null, .expected_groups_count = 0, .expected_filters_count = 0 },
    .{ .id = "ARG-013", .given = "--help returns HelpRequested", .args = &.{ "ngc", "--help" }, .expected_error = .HelpRequested, .expected_ipv4 = null, .expected_ipv6 = null, .expected_output = null, .expected_static = null, .expected_groups_count = 0, .expected_filters_count = 0 },
    .{ .id = "ARG-014", .given = "-h returns HelpRequested", .args = &.{ "ngc", "-h" }, .expected_error = .HelpRequested, .expected_ipv4 = null, .expected_ipv6 = null, .expected_output = null, .expected_static = null, .expected_groups_count = 0, .expected_filters_count = 0 },
    .{ .id = "ARG-015", .given = "--version returns VersionRequested", .args = &.{ "ngc", "--version" }, .expected_error = .VersionRequested, .expected_ipv4 = null, .expected_ipv6 = null, .expected_output = null, .expected_static = null, .expected_groups_count = 0, .expected_filters_count = 0 },
    .{ .id = "ARG-016", .given = "-v returns VersionRequested", .args = &.{ "ngc", "-v" }, .expected_error = .VersionRequested, .expected_ipv4 = null, .expected_ipv6 = null, .expected_output = null, .expected_static = null, .expected_groups_count = 0, .expected_filters_count = 0 },
};

const parse_group_line_rows = [_]struct {
    id: []const u8,
    given: []const u8,
    line: []const u8,
    expect_error: bool,
    fr_maps_to: ?u16,
    de_maps_to: ?u16,
}{
    .{ .id = "GRP-001", .given = "normal line maps FR,DE to EU", .line = "EU:FR,DE", .expect_error = false, .fr_maps_to = (@as(u16, 'E') << 8) | @as(u16, 'U'), .de_maps_to = (@as(u16, 'E') << 8) | @as(u16, 'U') },
    .{ .id = "GRP-002", .given = "whitespace around target and sources", .line = "  EU  :  FR , DE  ", .expect_error = false, .fr_maps_to = (@as(u16, 'E') << 8) | @as(u16, 'U'), .de_maps_to = (@as(u16, 'E') << 8) | @as(u16, 'U') },
    .{ .id = "GRP-003", .given = "single source country", .line = "EU:FR", .expect_error = false, .fr_maps_to = (@as(u16, 'E') << 8) | @as(u16, 'U'), .de_maps_to = null },
    .{ .id = "GRP-004", .given = "empty source after comma is skipped", .line = "EU:FR,,DE", .expect_error = false, .fr_maps_to = (@as(u16, 'E') << 8) | @as(u16, 'U'), .de_maps_to = (@as(u16, 'E') << 8) | @as(u16, 'U') },
    .{ .id = "GRP-005", .given = "short target (E) returns InvalidGroupFormat", .line = "E:FR,DE", .expect_error = true, .fr_maps_to = null, .de_maps_to = null },
    .{ .id = "GRP-006", .given = "short source (F) returns InvalidGroupFormat", .line = "EU:F,DE", .expect_error = true, .fr_maps_to = null, .de_maps_to = null },
    .{ .id = "GRP-007", .given = "no sources returns InvalidGroupFormat", .line = "EU", .expect_error = true, .fr_maps_to = null, .de_maps_to = null },
};

const parse_filter_line_rows = [_]struct {
    id: []const u8,
    given: []const u8,
    line: []const u8,
    expect_error: bool,
    fr_included: ?bool,
    de_included: ?bool,
}{
    .{ .id = "FIL-001", .given = "normal line enables FR and DE", .line = "FR, DE", .expect_error = false, .fr_included = true, .de_included = true },
    .{ .id = "FIL-002", .given = "single country US", .line = "US", .expect_error = false, .fr_included = null, .de_included = null },
    .{ .id = "FIL-003", .given = "empty entries between commas are skipped", .line = "US,,CA", .expect_error = false, .fr_included = null, .de_included = null },
    .{ .id = "FIL-004", .given = "short country (F) returns InvalidFilterFormat", .line = "F,DE", .expect_error = true, .fr_included = null, .de_included = null },
};

test "Config.deinit: empty config with default slices" {
    var cfg = lib.config.Config{ .output = try testing.allocator.dupe(u8, "out.conf") };
    cfg.deinit(testing.allocator);
}

test "Config.deinit: full config cleanup" {
    const groups = try testing.allocator.dupe([]const u8, &[_][]const u8{
        try testing.allocator.dupe(u8, "EU:FR,DE"),
    });
    const filters = try testing.allocator.dupe([]const u8, &[_][]const u8{
        try testing.allocator.dupe(u8, "US,CA"),
    });
    var parsed = lib.config.Config{
        .ipv4_csv = try testing.allocator.dupe(u8, "ipv4.csv"),
        .ipv6_csv = try testing.allocator.dupe(u8, "ipv6.csv"),
        .output = try testing.allocator.dupe(u8, "out.conf"),
        .static_file = try testing.allocator.dupe(u8, "static.conf"),
        .groups = groups,
        .groups_file = try testing.allocator.dupe(u8, "groups.txt"),
        .filters = filters,
        .filters_file = try testing.allocator.dupe(u8, "filters.txt"),
    };
    parsed.deinit(testing.allocator);
}

test "setupMaps: groups file populates country_map" {
    const dir = std.Io.Dir.cwd();
    const io = std.testing.io;
    const groups_path = "ngc-test-groups.txt";

    try dir.writeFile(io, .{ .sub_path = groups_path, .data = "EU:FR,DE\nNA:US,CA,MX\n" });
    defer dir.deleteFile(io, groups_path) catch {};

    var country_map = [_]u16{0} ** 65536;
    var filter_map = [_]bool{false} ** 65536;
    const parsed = lib.config.Config{
        .output = "out.conf",
        .groups_file = groups_path,
    };
    try lib.config.setupMaps(io, parsed, &country_map, &filter_map);

    const eu_idx = (@as(u16, 'E') << 8) | @as(u16, 'U');
    const na_idx = (@as(u16, 'N') << 8) | @as(u16, 'A');
    const fr_idx = (@as(u16, 'F') << 8) | @as(u16, 'R');
    const de_idx = (@as(u16, 'D') << 8) | @as(u16, 'E');
    const us_idx = (@as(u16, 'U') << 8) | @as(u16, 'S');
    try testing.expectEqual(eu_idx, country_map[fr_idx]);
    try testing.expectEqual(eu_idx, country_map[de_idx]);
    try testing.expectEqual(na_idx, country_map[us_idx]);
    try testing.expect(filter_map[eu_idx] == true);
}

test "setupMaps: filters file populates filter_map" {
    const dir = std.Io.Dir.cwd();
    const io = std.testing.io;
    const filters_path = "ngc-test-filters.txt";

    try dir.writeFile(io, .{ .sub_path = filters_path, .data = "US,CA\nFR\n" });
    defer dir.deleteFile(io, filters_path) catch {};

    var country_map = [_]u16{0} ** 65536;
    var filter_map = [_]bool{false} ** 65536;
    const parsed = lib.config.Config{
        .output = "out.conf",
        .filters_file = filters_path,
    };
    try lib.config.setupMaps(io, parsed, &country_map, &filter_map);

    const us_idx = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const ca_idx = (@as(u16, 'C') << 8) | @as(u16, 'A');
    const fr_idx = (@as(u16, 'F') << 8) | @as(u16, 'R');
    try testing.expect(filter_map[us_idx] == true);
    try testing.expect(filter_map[ca_idx] == true);
    try testing.expect(filter_map[fr_idx] == true);
    const de_idx = (@as(u16, 'D') << 8) | @as(u16, 'E');
    try testing.expect(filter_map[de_idx] == false);
}

test "parseGroupLine: whitespace and empty lines handled" {
    var cmap = [_]u16{0} ** 65536;
    try lib.config.parseGroupLine("   \t  \n ", &cmap);
    try lib.config.parseGroupLine("", &cmap);
    try lib.config.parseGroupLine("# comment", &cmap);
}

test "parseFilterLine: whitespace and empty lines handled" {
    var fmap = [_]bool{false} ** 65536;
    try lib.config.parseFilterLine("   \t  \n ", &fmap);
    try lib.config.parseFilterLine("", &fmap);
    try lib.config.parseFilterLine("# comment", &fmap);
}

test "setupMaps initializes identity mapping" {
    var country_map = [_]u16{0} ** 65536;
    var filter_map = [_]bool{false} ** 65536;
    const parsed = lib.config.Config{ .output = "out.conf" };
    try helpers.setupMapsInline(parsed, &country_map, &filter_map);
    for (0..65536) |i| {
        try testing.expectEqual(@as(u16, @intCast(i)), country_map[i]);
    }
}

test "setupMaps: filter map all true when no filters configured" {
    var country_map = [_]u16{0} ** 65536;
    var filter_map = [_]bool{false} ** 65536;
    const parsed = lib.config.Config{ .output = "out.conf" };
    try helpers.setupMapsInline(parsed, &country_map, &filter_map);
    for (0..65536) |i| {
        try testing.expect(filter_map[i] == true);
    }
}

test "setupMaps: inline groups remap countries" {
    var country_map = [_]u16{0} ** 65536;
    var filter_map = [_]bool{false} ** 65536;
    const groups = [_][]const u8{"EU:FR,DE"};
    const parsed = lib.config.Config{ .output = "out.conf", .groups = &groups };
    try helpers.setupMapsInline(parsed, &country_map, &filter_map);
    const eu_idx = (@as(u16, 'E') << 8) | @as(u16, 'U');
    const fr_idx = (@as(u16, 'F') << 8) | @as(u16, 'R');
    const de_idx = (@as(u16, 'D') << 8) | @as(u16, 'E');
    try testing.expectEqual(eu_idx, country_map[fr_idx]);
    try testing.expectEqual(eu_idx, country_map[de_idx]);
}

test "setupMaps: inline filters set specific countries" {
    var country_map = [_]u16{0} ** 65536;
    var filter_map = [_]bool{false} ** 65536;
    const filters = [_][]const u8{"US,CA"};
    const parsed = lib.config.Config{ .output = "out.conf", .filters = &filters };
    try helpers.setupMapsInline(parsed, &country_map, &filter_map);
    const us_idx = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const ca_idx = (@as(u16, 'C') << 8) | @as(u16, 'A');
    const fr_idx = (@as(u16, 'F') << 8) | @as(u16, 'R');
    try testing.expect(filter_map[us_idx] == true);
    try testing.expect(filter_map[ca_idx] == true);
    try testing.expect(filter_map[fr_idx] == false);
}

test "parseArgList: all cases" {
    for (parse_arg_list_rows) |row| {
        const result = lib.config.parseArgList(row.args[0..], testing.allocator);
        switch (row.expected_error) {
            .none => {
                var parsed = try result;
                defer parsed.deinit(testing.allocator);
                if (row.expected_ipv4) |exp| {
                    try testing.expectEqualStrings(exp, parsed.ipv4_csv.?);
                } else {
                    try testing.expect(parsed.ipv4_csv == null);
                }
                if (row.expected_ipv6) |exp| {
                    try testing.expectEqualStrings(exp, parsed.ipv6_csv.?);
                } else {
                    try testing.expect(parsed.ipv6_csv == null);
                }
                try testing.expectEqualStrings(row.expected_output.?, parsed.output);
                if (row.expected_static) |exp| {
                    try testing.expectEqualStrings(exp, parsed.static_file.?);
                } else {
                    try testing.expect(parsed.static_file == null);
                }
                try testing.expectEqual(row.expected_groups_count, parsed.groups.len);
                try testing.expectEqual(row.expected_filters_count, parsed.filters.len);
            },
            .InvalidArgs => try testing.expectError(error.InvalidArgs, result),
            .UnknownArgument => try testing.expectError(error.UnknownArgument, result),
            .MissingValue => try testing.expectError(error.MissingValue, result),
            .HelpRequested => try testing.expectError(error.HelpRequested, result),
            .VersionRequested => try testing.expectError(error.VersionRequested, result),
        }
    }
}

test "parseGroupLine: all cases" {
    for (parse_group_line_rows) |row| {
        var cmap = [_]u16{0} ** 65536;
        if (row.expect_error) {
            try testing.expectError(error.InvalidGroupFormat, lib.config.parseGroupLine(row.line, &cmap));
        } else {
            try lib.config.parseGroupLine(row.line, &cmap);
            const fr_idx = (@as(u16, 'F') << 8) | @as(u16, 'R');
            const de_idx = (@as(u16, 'D') << 8) | @as(u16, 'E');
            if (row.fr_maps_to) |exp| {
                try testing.expectEqual(exp, cmap[fr_idx]);
            }
            if (row.de_maps_to) |exp| {
                try testing.expectEqual(exp, cmap[de_idx]);
            }
        }
    }
}

test "parseFilterLine: all cases" {
    for (parse_filter_line_rows) |row| {
        var fmap = [_]bool{false} ** 65536;
        if (row.expect_error) {
            try testing.expectError(error.InvalidFilterFormat, lib.config.parseFilterLine(row.line, &fmap));
        } else {
            try lib.config.parseFilterLine(row.line, &fmap);
            if (row.fr_included) |exp| {
                const fr_idx = (@as(u16, 'F') << 8) | @as(u16, 'R');
                try testing.expectEqual(exp, fmap[fr_idx]);
            }
            if (row.de_included) |exp| {
                const de_idx = (@as(u16, 'D') << 8) | @as(u16, 'E');
                try testing.expectEqual(exp, fmap[de_idx]);
            }
        }
    }
}
