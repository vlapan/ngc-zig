const std = @import("std");

pub const Config = struct {
    ipv4_csv: []const u8,
    ipv6_csv: []const u8,
    output: []const u8,
    static_file: ?[]const u8 = null,
};

pub fn parseArgs(init: std.process.Init, alloc: std.mem.Allocator) !Config {
    var args = init.minimal.args.iterate();
    _ = args.next(); // Skip executable name

    var ipv4: ?[]const u8 = null;
    var ipv6: ?[]const u8 = null;
    var out: ?[]const u8 = null;
    var static_f: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--ipv4")) {
            ipv4 = args.next();
        } else if (std.mem.eql(u8, arg, "--ipv6")) {
            ipv6 = args.next();
        } else if (std.mem.eql(u8, arg, "--output")) {
            out = args.next();
        } else if (std.mem.eql(u8, arg, "--static")) {
            static_f = args.next();
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
        }
    }

    if (ipv4 == null or ipv6 == null or out == null) {
        std.debug.print("Usage: ngc --ipv4 <file> --ipv6 <file> --output <file> [--static <file>]\n", .{});
        return error.InvalidArgs;
    }

    return Config{
        .ipv4_csv = try alloc.dupe(u8, ipv4.?),
        .ipv6_csv = try alloc.dupe(u8, ipv6.?),
        .output = try alloc.dupe(u8, out.?),
        .static_file = if (static_f) |f| try alloc.dupe(u8, f) else null,
    };
}
