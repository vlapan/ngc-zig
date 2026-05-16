const std = @import("std");
const build_options = @import("build_options.zig");

pub const Config = struct {
    ipv4_csv: ?[]const u8 = null,
    ipv6_csv: ?[]const u8 = null,
    output: []const u8,
    static_file: ?[]const u8 = null,
    groups: []const []const u8 = &[_][]const u8{},
    groups_file: ?[]const u8 = null,
    filters: []const []const u8 = &[_][]const u8{},
    filters_file: ?[]const u8 = null,

    pub fn deinit(self: *Config, alloc: std.mem.Allocator) void {
        if (self.ipv4_csv) |f| alloc.free(f);
        if (self.ipv6_csv) |f| alloc.free(f);
        alloc.free(self.output);
        if (self.static_file) |f| alloc.free(f);
        for (self.groups) |g| alloc.free(g);
        if (self.groups.len > 0) alloc.free(self.groups);
        if (self.groups_file) |f| alloc.free(f);
        for (self.filters) |f| alloc.free(f);
        if (self.filters.len > 0) alloc.free(self.filters);
        if (self.filters_file) |f| alloc.free(f);
    }
};

pub const ParseError = error{
    InvalidArgs,
    MissingValue,
    UnknownArgument,
    HelpRequested,
    VersionRequested,
} || std.mem.Allocator.Error;

pub fn parseArgs(init: std.process.Init, alloc: std.mem.Allocator) ParseError!Config {
    var args = init.minimal.args.iterate();
    _ = args.next();

    return parseArgListFromIter(&args, alloc);
}

fn parseArgListFromIter(iter: anytype, alloc: std.mem.Allocator) ParseError!Config {
    var ipv4: ?[]const u8 = null;
    var ipv6: ?[]const u8 = null;
    var out: ?[]const u8 = null;
    var static_f: ?[]const u8 = null;
    var groups_f: ?[]const u8 = null;
    var filters_f: ?[]const u8 = null;
    var groups = std.ArrayList([]const u8).empty;
    defer groups.deinit(alloc);
    var filters = std.ArrayList([]const u8).empty;
    defer filters.deinit(alloc);

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--ipv4")) {
            ipv4 = iter.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--ipv6")) {
            ipv6 = iter.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--output")) {
            out = iter.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--static")) {
            static_f = iter.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--groups-file")) {
            groups_f = iter.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--group")) {
            const g = iter.next() orelse return error.MissingValue;
            try groups.append(alloc, try alloc.dupe(u8, g));
        } else if (std.mem.eql(u8, arg, "--filters-file")) {
            filters_f = iter.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--filter")) {
            const f = iter.next() orelse return error.MissingValue;
            try filters.append(alloc, try alloc.dupe(u8, f));
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print("Usage: ngc [--ipv4 <file>] [--ipv6 <file>] [--static <file>] [--group TARGET:SRC1,SRC2] [--groups-file <file>] [--filter SRC1,SRC2] [--filters-file <file>] --output <file>\n", .{});
            return error.HelpRequested;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            std.debug.print("ngc {s}\n", .{build_options.version});
            return error.VersionRequested;
        } else {
            return error.UnknownArgument;
        }
    }

    if (out == null) {
        std.debug.print("Usage: ngc [--ipv4 <file>] [--ipv6 <file>] [--static <file>] [--group TARGET:SRC1,SRC2] [--groups-file <file>] [--filter SRC1,SRC2] [--filters-file <file>] --output <file>\n", .{});
        return error.InvalidArgs;
    }

    if (ipv4 == null and ipv6 == null and static_f == null) {
        std.debug.print("At least one input file (--ipv4, --ipv6, or --static) must be provided.\n", .{});
        return error.InvalidArgs;
    }

    const duped_groups = try groups.toOwnedSlice(alloc);
    const duped_filters = try filters.toOwnedSlice(alloc);

    var config = Config{
        .ipv4_csv = if (ipv4) |f| try alloc.dupe(u8, f) else null,
        .ipv6_csv = if (ipv6) |f| try alloc.dupe(u8, f) else null,
        .output = try alloc.dupe(u8, out.?),
        .static_file = if (static_f) |f| try alloc.dupe(u8, f) else null,
        .groups = duped_groups,
        .groups_file = if (groups_f) |f| try alloc.dupe(u8, f) else null,
        .filters = duped_filters,
        .filters_file = if (filters_f) |f| try alloc.dupe(u8, f) else null,
    };
    errdefer config.deinit(alloc);
    return config;
}

pub const FormatError = error{ InvalidGroupFormat, InvalidFilterFormat };

pub fn parseGroupLine(line: []const u8, country_map: *[65536]u16) FormatError!void {
    const g = std.mem.trim(u8, line, " \t\r\n");
    if (g.len == 0 or g[0] == '#') return;

    if (std.mem.indexOfScalar(u8, g, ':')) |colon_idx| {
        const target_str = std.mem.trim(u8, g[0..colon_idx], " \t");
        if (target_str.len != 2) return error.InvalidGroupFormat;
        const target_u16 = (@as(u16, target_str[0]) << 8) | @as(u16, target_str[1]);

        var it = std.mem.splitScalar(u8, g[colon_idx + 1 ..], ',');
        while (it.next()) |src_str| {
            const s_str = std.mem.trim(u8, src_str, " \t");
            if (s_str.len == 0) continue;
            if (s_str.len != 2) return error.InvalidGroupFormat;
            const src_u16 = (@as(u16, s_str[0]) << 8) | @as(u16, s_str[1]);
            country_map.*[src_u16] = target_u16;
        }
    } else {
        return error.InvalidGroupFormat;
    }
}

pub fn parseFilterLine(line: []const u8, filter_map: *[65536]bool) FormatError!void {
    const f = std.mem.trim(u8, line, " \t\r\n");
    if (f.len == 0 or f[0] == '#') return;

    var it = std.mem.splitScalar(u8, f, ',');
    while (it.next()) |src_str| {
        const s_str = std.mem.trim(u8, src_str, " \t");
        if (s_str.len == 0) continue;
        if (s_str.len != 2) return error.InvalidFilterFormat;
        const src_u16 = (@as(u16, s_str[0]) << 8) | @as(u16, s_str[1]);
        filter_map.*[src_u16] = true;
    }
}

pub fn setupMaps(io: std.Io, config: Config, country_map: *[65536]u16, filter_map: *[65536]bool) !void {
    try setupMapsInline(config, country_map, filter_map);

    if (config.groups_file) |gf| {
        var file = try std.Io.Dir.cwd().openFile(io, gf, .{});
        defer file.close(io);
        const stat = try file.stat(io);
        if (stat.size > 0) {
            @branchHint(.likely);
            const mapped = try std.posix.mmap(null, stat.size, .{ .READ = true }, .{ .TYPE = .PRIVATE }, file.handle, 0);
            defer std.posix.munmap(mapped);

            var it = std.mem.splitScalar(u8, mapped, '\n');
            while (it.next()) |line| {
                try parseGroupLine(line, country_map);
            }
        }
    }

    if (config.filters_file) |ff| {
        var file = try std.Io.Dir.cwd().openFile(io, ff, .{});
        defer file.close(io);
        const stat = try file.stat(io);
        if (stat.size > 0) {
            const mapped = try std.posix.mmap(null, stat.size, .{ .READ = true }, .{ .TYPE = .PRIVATE }, file.handle, 0);
            defer std.posix.munmap(mapped);

            var it = std.mem.splitScalar(u8, mapped, '\n');
            while (it.next()) |line| {
                try parseFilterLine(line, filter_map);
            }
        }
    }
}

fn setupMapsInline(config: Config, country_map: *[65536]u16, filter_map: *[65536]bool) !void {
    for (0..65536) |i| {
        country_map[i] = @intCast(i);
    }
    for (config.groups) |g| {
        try parseGroupLine(g, country_map);
    }

    const has_filters = config.filters.len > 0 or config.filters_file != null;
    @memset(filter_map, !has_filters);

    if (has_filters) {
        for (config.filters) |f| {
            try parseFilterLine(f, filter_map);
        }
    }
}

const testing = std.testing;

// SliceIter adapts a []const []const u8 to the iterator interface expected by parseArgListFromIter.
// Assumes args[0] is the program name (skipped automatically).
const SliceIter = struct {
    items: []const []const u8,
    index: usize = 0,

    fn next(self: *SliceIter) ?[]const u8 {
        if (self.index >= self.items.len) return null;
        const item = self.items[self.index];
        self.index += 1;
        return item;
    }
};

fn parseArgList(args: []const []const u8, alloc: std.mem.Allocator) ParseError!Config {
    var iter = SliceIter{ .items = args, .index = 1 };
    return parseArgListFromIter(&iter, alloc);
}

// parseArgList tests

test "parseArgList: minimal valid args (--output only)" {
    const args = [_][]const u8{ "ngc", "--ipv4", "ipv4.csv", "--output", "out.conf" };
    var config = try parseArgList(args[0..], testing.allocator);
    defer config.deinit(testing.allocator);

    try testing.expectEqualStrings("ipv4.csv", config.ipv4_csv.?);
    try testing.expect(config.ipv6_csv == null);
    try testing.expectEqualStrings("out.conf", config.output);
    try testing.expect(config.static_file == null);
    try testing.expectEqual(@as(usize, 0), config.groups.len);
    try testing.expectEqual(@as(usize, 0), config.filters.len);
}

test "parseArgList: all flags" {
    const args = [_][]const u8{
        "ngc",
        "--ipv4", "ipv4.csv",
        "--ipv6", "ipv6.csv",
        "--output", "out.conf",
        "--static", "static.conf",
        "--groups-file", "groups.txt",
        "--group", "EU:FR,DE",
        "--filters-file", "filters.txt",
        "--filter", "US,CA",
    };
    var config = try parseArgList(args[0..], testing.allocator);
    defer config.deinit(testing.allocator);

    try testing.expectEqualStrings("ipv4.csv", config.ipv4_csv.?);
    try testing.expectEqualStrings("ipv6.csv", config.ipv6_csv.?);
    try testing.expectEqualStrings("out.conf", config.output);
    try testing.expectEqualStrings("static.conf", config.static_file.?);
    try testing.expectEqualStrings("groups.txt", config.groups_file.?);
    try testing.expectEqual(@as(usize, 1), config.groups.len);
    try testing.expectEqualStrings("EU:FR,DE", config.groups[0]);
    try testing.expectEqualStrings("filters.txt", config.filters_file.?);
    try testing.expectEqual(@as(usize, 1), config.filters.len);
    try testing.expectEqualStrings("US,CA", config.filters[0]);
}

test "parseArgList: missing --output returns InvalidArgs" {
    const args = [_][]const u8{ "ngc", "--ipv4", "ipv4.csv" };
    try testing.expectError(error.InvalidArgs, parseArgList(args[0..], testing.allocator));
}

test "parseArgList: no input files returns InvalidArgs" {
    const args = [_][]const u8{ "ngc", "--output", "out.conf" };
    try testing.expectError(error.InvalidArgs, parseArgList(args[0..], testing.allocator));
}

test "parseArgList: unknown argument returns UnknownArgument" {
    const args = [_][]const u8{ "ngc", "--ipv4", "ipv4.csv", "--ouptut", "out.conf" };
    try testing.expectError(error.UnknownArgument, parseArgList(args[0..], testing.allocator));
}

test "parseArgList: missing value after --ipv4 at end of args returns MissingValue" {
    const args = [_][]const u8{ "ngc", "--ipv4" };
    try testing.expectError(error.MissingValue, parseArgList(args[0..], testing.allocator));
}

test "parseArgList: missing value after --output returns MissingValue" {
    const args = [_][]const u8{ "ngc", "--output" };
    try testing.expectError(error.MissingValue, parseArgList(args[0..], testing.allocator));
}

test "parseArgList: missing value after --group returns MissingValue" {
    const args = [_][]const u8{ "ngc", "--ipv4", "ipv4.csv", "--output", "out.conf", "--group" };
    try testing.expectError(error.MissingValue, parseArgList(args[0..], testing.allocator));
}

test "parseArgList: multiple --group flags" {
    const args = [_][]const u8{
        "ngc", "--ipv4", "ipv4.csv", "--output", "out.conf",
        "--group", "EU:FR,DE", "--group", "NA:US,CA",
    };
    var config = try parseArgList(args[0..], testing.allocator);
    defer config.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 2), config.groups.len);
    try testing.expectEqualStrings("EU:FR,DE", config.groups[0]);
    try testing.expectEqualStrings("NA:US,CA", config.groups[1]);
}

test "parseArgList: multiple --filter flags" {
    const args = [_][]const u8{
        "ngc", "--ipv4", "ipv4.csv", "--output", "out.conf",
        "--filter", "US", "--filter", "CA,JP",
    };
    var config = try parseArgList(args[0..], testing.allocator);
    defer config.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 2), config.filters.len);
    try testing.expectEqualStrings("US", config.filters[0]);
    try testing.expectEqualStrings("CA,JP", config.filters[1]);
}

test "parseArgList: --static as sole input is valid" {
    const args = [_][]const u8{ "ngc", "--static", "static.conf", "--output", "out.conf" };
    var config = try parseArgList(args[0..], testing.allocator);
    defer config.deinit(testing.allocator);

    try testing.expectEqualStrings("static.conf", config.static_file.?);
}

test "parseArgList: empty args (just program name) returns InvalidArgs" {
    const args = [_][]const u8{ "ngc" };
    try testing.expectError(error.InvalidArgs, parseArgList(args[0..], testing.allocator));
}

test "parseArgList: --help returns HelpRequested" {
    const args = [_][]const u8{ "ngc", "--help" };
    try testing.expectError(error.HelpRequested, parseArgList(args[0..], testing.allocator));
}

test "parseArgList: -h returns HelpRequested" {
    const args = [_][]const u8{ "ngc", "-h" };
    try testing.expectError(error.HelpRequested, parseArgList(args[0..], testing.allocator));
}

test "parseArgList: --version returns VersionRequested" {
    const args = [_][]const u8{ "ngc", "--version" };
    try testing.expectError(error.VersionRequested, parseArgList(args[0..], testing.allocator));
}

test "parseArgList: -v returns VersionRequested" {
    const args = [_][]const u8{ "ngc", "-v" };
    try testing.expectError(error.VersionRequested, parseArgList(args[0..], testing.allocator));
}

test "Config.deinit: empty config with default slices" {
    var config = Config{ .output = try testing.allocator.dupe(u8, "out.conf") };
    config.deinit(testing.allocator);
}

test "Config.deinit: full config cleanup" {
    const groups = try testing.allocator.dupe([]const u8, &[_][]const u8{
        try testing.allocator.dupe(u8, "EU:FR,DE"),
    });
    const filters = try testing.allocator.dupe([]const u8, &[_][]const u8{
        try testing.allocator.dupe(u8, "US,CA"),
    });
    var config = Config{
        .ipv4_csv = try testing.allocator.dupe(u8, "ipv4.csv"),
        .ipv6_csv = try testing.allocator.dupe(u8, "ipv6.csv"),
        .output = try testing.allocator.dupe(u8, "out.conf"),
        .static_file = try testing.allocator.dupe(u8, "static.conf"),
        .groups = groups,
        .groups_file = try testing.allocator.dupe(u8, "groups.txt"),
        .filters = filters,
        .filters_file = try testing.allocator.dupe(u8, "filters.txt"),
    };
    config.deinit(testing.allocator);
}

// parseGroupLine tests

test "parseGroupLine handles normal, empty, and whitespace correctly" {
    var cmap = [_]u16{0} ** 65536;

    // Valid cases
    try parseGroupLine("EU:FR,DE", &cmap);
    const eu_idx = (@as(u16, 'E') << 8) | @as(u16, 'U');
    const fr_idx = (@as(u16, 'F') << 8) | @as(u16, 'R');
    const de_idx = (@as(u16, 'D') << 8) | @as(u16, 'E');
    try testing.expectEqual(eu_idx, cmap[fr_idx]);
    try testing.expectEqual(eu_idx, cmap[de_idx]);

    // Whitespace handling (valid but ignored or trimmed)
    try parseGroupLine("   \t  \n ", &cmap);
    try parseGroupLine("", &cmap);
    try parseGroupLine("# comment", &cmap);

    // Invalid cases
    try testing.expectError(error.InvalidGroupFormat, parseGroupLine("E:FR,DE", &cmap));
    try testing.expectError(error.InvalidGroupFormat, parseGroupLine("EU:F,DE", &cmap));
    try testing.expectError(error.InvalidGroupFormat, parseGroupLine("EU", &cmap));
}

test "parseGroupLine: whitespace around target and sources" {
    var cmap = [_]u16{0} ** 65536;
    try parseGroupLine("  EU  :  FR , DE  ", &cmap);
    const eu_idx = (@as(u16, 'E') << 8) | @as(u16, 'U');
    const fr_idx = (@as(u16, 'F') << 8) | @as(u16, 'R');
    const de_idx = (@as(u16, 'D') << 8) | @as(u16, 'E');
    try testing.expectEqual(eu_idx, cmap[fr_idx]);
    try testing.expectEqual(eu_idx, cmap[de_idx]);
}

test "parseGroupLine: single source country" {
    var cmap = [_]u16{0} ** 65536;
    try parseGroupLine("EU:FR", &cmap);
    const eu_idx = (@as(u16, 'E') << 8) | @as(u16, 'U');
    const fr_idx = (@as(u16, 'F') << 8) | @as(u16, 'R');
    try testing.expectEqual(eu_idx, cmap[fr_idx]);
}

test "parseGroupLine: empty source after comma is skipped" {
    var cmap = [_]u16{0} ** 65536;
    try parseGroupLine("EU:FR,,DE", &cmap);
    const eu_idx = (@as(u16, 'E') << 8) | @as(u16, 'U');
    const fr_idx = (@as(u16, 'F') << 8) | @as(u16, 'R');
    const de_idx = (@as(u16, 'D') << 8) | @as(u16, 'E');
    try testing.expectEqual(eu_idx, cmap[fr_idx]);
    try testing.expectEqual(eu_idx, cmap[de_idx]);
}

// parseFilterLine tests

test "parseFilterLine handles normal, empty, and whitespace correctly" {
    var fmap = [_]bool{false} ** 65536;

    // Valid cases
    try parseFilterLine("FR, DE", &fmap);
    const fr_idx = (@as(u16, 'F') << 8) | @as(u16, 'R');
    const de_idx = (@as(u16, 'D') << 8) | @as(u16, 'E');
    try testing.expect(fmap[fr_idx] == true);
    try testing.expect(fmap[de_idx] == true);

    // Whitespace handling
    try parseFilterLine("   \t  \n ", &fmap);
    try parseFilterLine("", &fmap);
    try parseFilterLine("# comment", &fmap);

    // Invalid cases
    try testing.expectError(error.InvalidFilterFormat, parseFilterLine("F,DE", &fmap));
}

test "parseFilterLine: single country" {
    var fmap = [_]bool{false} ** 65536;
    try parseFilterLine("US", &fmap);
    const us_idx = (@as(u16, 'U') << 8) | @as(u16, 'S');
    try testing.expect(fmap[us_idx] == true);
}

test "parseFilterLine: empty entries between commas are skipped" {
    var fmap = [_]bool{false} ** 65536;
    try parseFilterLine("US,,CA", &fmap);
    const us_idx = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const ca_idx = (@as(u16, 'C') << 8) | @as(u16, 'A');
    try testing.expect(fmap[us_idx] == true);
    try testing.expect(fmap[ca_idx] == true);
}

// setupMaps tests (inline-only, no file I/O)

test "setupMaps initializes identity mapping" {
    var country_map = [_]u16{0} ** 65536;
    var filter_map = [_]bool{false} ** 65536;

    const config = Config{ .output = "out.conf" };
    try setupMapsInline(config, &country_map, &filter_map);

    for (0..65536) |i| {
        try testing.expectEqual(@as(u16, @intCast(i)), country_map[i]);
    }
}

test "setupMaps: filter map all true when no filters configured" {
    var country_map = [_]u16{0} ** 65536;
    var filter_map = [_]bool{false} ** 65536;

    const config = Config{ .output = "out.conf" };
    try setupMapsInline(config, &country_map, &filter_map);

    for (0..65536) |i| {
        try testing.expect(filter_map[i] == true);
    }
}

test "setupMaps: inline groups remap countries" {
    var country_map = [_]u16{0} ** 65536;
    var filter_map = [_]bool{false} ** 65536;

    const groups = [_][]const u8{"EU:FR,DE"};
    const config = Config{ .output = "out.conf", .groups = &groups };
    try setupMapsInline(config, &country_map, &filter_map);

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
    const config = Config{ .output = "out.conf", .filters = &filters };
    try setupMapsInline(config, &country_map, &filter_map);

    const us_idx = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const ca_idx = (@as(u16, 'C') << 8) | @as(u16, 'A');
    const fr_idx = (@as(u16, 'F') << 8) | @as(u16, 'R');

    try testing.expect(filter_map[us_idx] == true);
    try testing.expect(filter_map[ca_idx] == true);
    try testing.expect(filter_map[fr_idx] == false);
}
