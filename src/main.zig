const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;

const IPv4Range = struct { start: u32, end: u32, country: []const u8 };
const IPv6Range = struct { start: [16]u8, end: [16]u8, country: []const u8 };

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;

    var args = init.minimal.args.iterate();
    _ = args.next();

    const ipv4_path = args.next() orelse {
        std.debug.print("Usage: geoip-converter <ipv4_csv> <ipv6_csv> <output_file>\n", .{});
        return error.InvalidArgs;
    };
    const ipv6_path = args.next() orelse {
        std.debug.print("Usage: geoip-converter <ipv4_csv> <ipv6_csv> <output_file>\n", .{});
        return error.InvalidArgs;
    };
    const output_path = args.next() orelse {
        std.debug.print("Usage: geoip-converter <ipv4_csv> <ipv6_csv> <output_file>\n", .{});
        return error.InvalidArgs;
    };

    var ipv4_ranges = std.ArrayList(IPv4Range).empty;
    defer ipv4_ranges.deinit(alloc);
    try parseIPv4File(std.Io.Dir.cwd(), io, ipv4_path, &ipv4_ranges, alloc);

    var ipv6_ranges = std.ArrayList(IPv6Range).empty;
    defer ipv6_ranges.deinit(alloc);
    try parseIPv6File(std.Io.Dir.cwd(), io, ipv6_path, &ipv6_ranges, alloc);

    const out_file = try std.Io.Dir.cwd().createFile(io, output_path, .{});
    defer out_file.close(io);

    var out_buf: [4096]u8 = undefined;
    var out_file_writer = out_file.writer(io, &out_buf);
    try writeIPv4Ranges(ipv4_ranges.items, &out_file_writer.interface, alloc);
    try writeIPv6Ranges(ipv6_ranges.items, &out_file_writer.interface, alloc);
}

fn writeIPv4Ranges(ranges: []const IPv4Range, writer: *std.Io.Writer, alloc: mem.Allocator) !void {
    for (ranges) |range| {
        const cidrs = try rangeToCIDRsIPv4(range, alloc);
        defer {
            for (cidrs) |cidr| alloc.free(cidr);
            alloc.free(cidrs);
        }
        for (cidrs) |cidr| {
            try writer.print("{s} {s};\n", .{ cidr, range.country });
        }
    }
}

fn writeIPv6Ranges(ranges: []const IPv6Range, writer: *std.Io.Writer, alloc: mem.Allocator) !void {
    for (ranges) |range| {
        const cidrs = try rangeToCIDRsIPv6(range, alloc);
        defer {
            for (cidrs) |cidr| alloc.free(cidr);
            alloc.free(cidrs);
        }
        for (cidrs) |cidr| {
            try writer.print("{s} {s};\n", .{ cidr, range.country });
        }
    }
}

fn parseIPv4File(dir: std.Io.Dir, io: std.Io, path: []const u8, ranges: *std.ArrayList(IPv4Range), alloc: mem.Allocator) !void {
    const content = try dir.readFileAlloc(io, path, alloc, .unlimited);
    defer alloc.free(content);

    var lines = mem.tokenizeAny(u8, content, "\n");
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parts = mem.tokenizeAny(u8, line, ",");
        const start = parts.next() orelse continue;
        const end = parts.next() orelse continue;
        const country = parts.next() orelse continue;

        try ranges.append(alloc, .{
            .start = try fmt.parseInt(u32, start, 10),
            .end = try fmt.parseInt(u32, end, 10),
            .country = try alloc.dupe(u8, country),
        });
    }
}

fn parseIPv6File(dir: std.Io.Dir, io: std.Io, path: []const u8, ranges: *std.ArrayList(IPv6Range), alloc: mem.Allocator) !void {
    const content = try dir.readFileAlloc(io, path, alloc, .unlimited);
    defer alloc.free(content);

    var lines = mem.tokenizeAny(u8, content, "\n");
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parts = mem.tokenizeAny(u8, line, ",");
        const start_str = parts.next() orelse continue;
        const end_str = parts.next() orelse continue;
        const country = parts.next() orelse continue;

        const start = try parseIPv6Uint(start_str);
        const end = try parseIPv6Uint(end_str);

        try ranges.append(alloc, .{
            .start = start,
            .end = end,
            .country = try alloc.dupe(u8, country),
        });
    }
}

fn parseIPv6Uint(s: []const u8) ![16]u8 {
    const n = try fmt.parseInt(u128, s, 10);
    var buf: [16]u8 = undefined;
    for (0..16) |i| {
        buf[15 - i] = @truncate(n >> @as(u7, @intCast(i * 8)));
    }
    return buf;
}

fn rangeToCIDRsIPv4(range: IPv4Range, alloc: mem.Allocator) ![]const []const u8 {
    var cidrs = std.ArrayList([]const u8).empty;
    defer {
        for (cidrs.items) |cidr| alloc.free(cidr);
        cidrs.deinit(alloc);
    }
    var start = range.start;
    while (start <= range.end) {
        const remaining: u32 = range.end -% start;
        const prefix: u6 = if (remaining == 0) @as(u6, 32) else @as(u6, 32 -% @clz(remaining));
        const block_size: u32 = if (prefix == 0) 1 else @as(u32, 1) << @intCast(prefix);

        const mask: u32 = if (prefix == 32) 0 else (~@as(u32, 0)) << @intCast(32 -% prefix);
        const network: u32 = start & ~mask;

        const cidr = try fmt.allocPrint(alloc, "{d}.{d}.{d}.{d}/{d}", .{
            (network >> 24) & 0xFF,
            (network >> 16) & 0xFF,
            (network >> 8) & 0xFF,
            network & 0xFF,
            prefix,
        });
        try cidrs.append(alloc, cidr);

        start +%= block_size;
    }
    return try cidrs.toOwnedSlice(alloc);
}

fn rangeToCIDRsIPv6(range: IPv6Range, alloc: mem.Allocator) ![]const []const u8 {
    _ = range;
    _ = alloc;
    const result: []const []const u8 = &.{};
    return result;
}