const std = @import("std");

pub const Config = struct {
    ipv4_csv: ?[]const u8 = null,
    ipv6_csv: ?[]const u8 = null,
    output: []const u8,
    static_file: ?[]const u8 = null,
    groups: []const []const u8 = &[_][]const u8{},
};

pub fn parseArgs(init: std.process.Init, alloc: std.mem.Allocator) !Config {
    var args = init.minimal.args.iterate();
    _ = args.next(); // Skip executable name

    var ipv4: ?[]const u8 = null;
    var ipv6: ?[]const u8 = null;
    var out: ?[]const u8 = null;
    var static_f: ?[]const u8 = null;
    var groups = std.ArrayList([]const u8).empty;
    defer groups.deinit(alloc);

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--ipv4")) {
            ipv4 = args.next();
        } else if (std.mem.eql(u8, arg, "--ipv6")) {
            ipv6 = args.next();
        } else if (std.mem.eql(u8, arg, "--output")) {
            out = args.next();
        } else if (std.mem.eql(u8, arg, "--static")) {
            static_f = args.next();
        } else if (std.mem.eql(u8, arg, "--group")) {
            if (args.next()) |g| {
                try groups.append(alloc, g);
            }
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
        }
    }

    if (out == null) {
        std.debug.print("Usage: ngc [--ipv4 <file>] [--ipv6 <file>] [--static <file>] [--group TARGET:SRC1,SRC2] --output <file>\n", .{});
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

    return Config{
        .ipv4_csv = if (ipv4) |f| try alloc.dupe(u8, f) else null,
        .ipv6_csv = if (ipv6) |f| try alloc.dupe(u8, f) else null,
        .output = try alloc.dupe(u8, out.?),
        .static_file = if (static_f) |f| try alloc.dupe(u8, f) else null,
        .groups = duped_groups,
    };
}
