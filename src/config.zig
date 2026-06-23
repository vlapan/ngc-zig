const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options.zig");

inline fn cliPrint(comptime fmt: []const u8, args: anytype) void {
    if (builtin.is_test) return;
    std.debug.print(fmt, args);
}

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
            cliPrint("Usage: ngc [--ipv4 <file>] [--ipv6 <file>] [--static <file>] [--group TARGET:SRC1,SRC2] [--groups-file <file>] [--filter SRC1,SRC2] [--filters-file <file>] --output <file>\n", .{});
            return error.HelpRequested;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            cliPrint("v{s}\n", .{build_options.version});
            return error.VersionRequested;
        } else {
            return error.UnknownArgument;
        }
    }

    if (out == null) {
        cliPrint("Usage: ngc [--ipv4 <file>] [--ipv6 <file>] [--static <file>] [--group TARGET:SRC1,SRC2] [--groups-file <file>] [--filter SRC1,SRC2] [--filters-file <file>] --output <file>\n", .{});
        return error.InvalidArgs;
    }

    if (ipv4 == null and ipv6 == null and static_f == null) {
        cliPrint("At least one input file (--ipv4, --ipv6, or --static) must be provided.\n", .{});
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

pub fn setupMapsInline(config: Config, country_map: *[65536]u16, filter_map: *[65536]bool) !void {
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

pub fn parseArgList(args: []const []const u8, alloc: std.mem.Allocator) ParseError!Config {
    var iter = struct {
        args: []const []const u8,
        idx: usize,
        pub fn next(self: *@This()) ?[]const u8 {
            const i = self.idx;
            if (i >= self.args.len) return null;
            self.idx = i + 1;
            return self.args[i];
        }
    }{ .args = args, .idx = 1 };
    return parseArgListFromIter(&iter, alloc);
}
