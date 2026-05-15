const std = @import("std");

pub const Config = struct {
    ipv4_csv: ?[]const u8 = null,
    ipv6_csv: ?[]const u8 = null,
    output: []const u8,
    static_file: ?[]const u8 = null,
    groups: []const []const u8 = &[_][]const u8{},
    groups_file: ?[]const u8 = null,
    filters: []const []const u8 = &[_][]const u8{},
    filters_file: ?[]const u8 = null,
};

pub fn parseArgs(init: std.process.Init, alloc: std.mem.Allocator) !Config {
    var args = init.minimal.args.iterate();
    _ = args.next(); // Skip executable name

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

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--ipv4")) {
            ipv4 = args.next();
        } else if (std.mem.eql(u8, arg, "--ipv6")) {
            ipv6 = args.next();
        } else if (std.mem.eql(u8, arg, "--output")) {
            out = args.next();
        } else if (std.mem.eql(u8, arg, "--static")) {
            static_f = args.next();
        } else if (std.mem.eql(u8, arg, "--groups-file")) {
            groups_f = args.next();
        } else if (std.mem.eql(u8, arg, "--group")) {
            if (args.next()) |g| {
                try groups.append(alloc, g);
            }
        } else if (std.mem.eql(u8, arg, "--filters-file")) {
            filters_f = args.next();
        } else if (std.mem.eql(u8, arg, "--filter")) {
            if (args.next()) |f| {
                try filters.append(alloc, f);
            }
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
        }
    }

    if (out == null) {
        std.debug.print("Usage: ngc [--ipv4 <file>] [--ipv6 <file>] [--static <file>] [--group TARGET:SRC1,SRC2] [--groups-file <file>] [--filter SRC1,SRC2] [--filters-file <file>] --output <file>\n", .{});
        return error.InvalidArgs;
    }

    if (ipv4 == null and ipv6 == null and static_f == null) {
        std.log.err("At least one input file (--ipv4, --ipv6, or --static) must be provided.\n", .{});
        return error.InvalidArgs;
    }

    const duped_groups = try alloc.alloc([]const u8, groups.items.len);
    for (groups.items, 0..) |g, i| {
        duped_groups[i] = try alloc.dupe(u8, g);
    }

    const duped_filters = try alloc.alloc([]const u8, filters.items.len);
    for (filters.items, 0..) |f, i| {
        duped_filters[i] = try alloc.dupe(u8, f);
    }

    return Config{
        .ipv4_csv = if (ipv4) |f| try alloc.dupe(u8, f) else null,
        .ipv6_csv = if (ipv6) |f| try alloc.dupe(u8, f) else null,
        .output = try alloc.dupe(u8, out.?),
        .static_file = if (static_f) |f| try alloc.dupe(u8, f) else null,
        .groups = duped_groups,
        .groups_file = if (groups_f) |f| try alloc.dupe(u8, f) else null,
        .filters = duped_filters,
        .filters_file = if (filters_f) |f| try alloc.dupe(u8, f) else null,
    };
}

pub const ConfigError = error{ InvalidGroupFormat, InvalidFilterFormat };

pub fn parseGroupLine(line: []const u8, country_map: *[65536]u16) !void {
    const g = std.mem.trim(u8, line, " \t\r\n");
    if (g.len == 0 or g[0] == '#') return;

    if (std.mem.indexOfScalar(u8, g, ':')) |colon_idx| {
        const target_str = std.mem.trim(u8, g[0..colon_idx], " \t");
        if (target_str.len != 2) {
            return error.InvalidGroupFormat;
        }
        const target_u16 = (@as(u16, target_str[0]) << 8) | @as(u16, target_str[1]);

        var it = std.mem.splitScalar(u8, g[colon_idx + 1 ..], ',');
        while (it.next()) |src_str| {
            const s_str = std.mem.trim(u8, src_str, " \t");
            if (s_str.len == 0) continue;
            if (s_str.len != 2) {
                return error.InvalidGroupFormat;
            }
            const src_u16 = (@as(u16, s_str[0]) << 8) | @as(u16, s_str[1]);
            country_map.*[src_u16] = target_u16;
        }
    } else {
        return error.InvalidGroupFormat;
    }
}

pub fn parseFilterLine(line: []const u8, filter_map: *[65536]bool) !void {
    const f = std.mem.trim(u8, line, " \t\r\n");
    if (f.len == 0 or f[0] == '#') return;

    var it = std.mem.splitScalar(u8, f, ',');
    while (it.next()) |src_str| {
        const s_str = std.mem.trim(u8, src_str, " \t");
        if (s_str.len == 0) continue;
        if (s_str.len != 2) {
            return error.InvalidFilterFormat;
        }
        const src_u16 = (@as(u16, s_str[0]) << 8) | @as(u16, s_str[1]);
        filter_map.*[src_u16] = true;
    }
}

pub fn setupMaps(io: std.Io, config: Config, country_map: *[65536]u16, filter_map: *[65536]bool) !void {
    for (0..65536) |i| {
        country_map[i] = @intCast(i);
    }
    for (config.groups) |g| {
        try parseGroupLine(g, country_map);
    }

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

    const has_filters = config.filters.len > 0 or config.filters_file != null;
    @memset(filter_map, !has_filters);

    if (has_filters) {
        for (config.filters) |f| {
            try parseFilterLine(f, filter_map);
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
}

const testing = std.testing;

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
