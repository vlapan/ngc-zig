const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;

const IPv4Range = struct { start: u32, end: u32, country: []const u8, size: u32 };
const IPv6Range = struct { start: [16]u8, end: [16]u8, country: []const u8, size: u128 };

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

    mem.sort(IPv4Range, ipv4_ranges.items, {}, struct {
        fn less(_: void, a: IPv4Range, b: IPv4Range) bool {
            if (a.size != b.size) return a.size < b.size;
            if (a.start != b.start) return a.start < b.start;
            return mem.order(u8, a.country, b.country) == .lt;
        }
    }.less);

    var seen_unmanaged = std.hash_map.StringHashMapUnmanaged(void){};
    try seen_unmanaged.ensureTotalCapacity(alloc, 500000);
    defer seen_unmanaged.deinit(alloc);

    const seen: *std.hash_map.StringHashMapUnmanaged(void) = &seen_unmanaged;

    const out_file = try std.Io.Dir.cwd().createFile(io, output_path, .{});
    defer out_file.close(io);

    var out_buf: [4096]u8 = undefined;
    var out_file_writer = out_file.writer(io, &out_buf);
    const writer = &out_file_writer.interface;

    try writer.print("127.0.0.0/8 RFC1918;\n", .{});
    try writer.print("169.254.0.0/16 RFC1918;\n", .{});
    try writer.print("10.0.0.0/8 RFC1918;\n", .{});
    try writer.print("172.16.0.0/12 RFC1918;\n", .{});
    try writer.print("192.168.0.0/16 RFC1918;\n", .{});

    try writeIPv4Ranges(ipv4_ranges.items, writer, alloc, seen);

    var ipv6_ranges = std.ArrayList(IPv6Range).empty;
    defer ipv6_ranges.deinit(alloc);
    try parseIPv6File(std.Io.Dir.cwd(), io, ipv6_path, &ipv6_ranges, alloc);

    mem.sort(IPv6Range, ipv6_ranges.items, {}, struct {
        fn less(_: void, a: IPv6Range, b: IPv6Range) bool {
            if (a.size != b.size) return a.size < b.size;
            if (mem.order(u8, &a.start, &b.start) != .eq) {
                return mem.order(u8, &a.start, &b.start) == .lt;
            }
            return mem.order(u8, a.country, b.country) == .lt;
        }
    }.less);

    try writeIPv6Ranges(ipv6_ranges.items, writer, alloc, seen);
    try out_file_writer.flush();
}

fn isPrivateIPv4(ip: u32) bool {
    if (ip >= 2130706432 and ip <= 2147483647) return true;
    if (ip >= 2851995648 and ip <= 2852061183) return true;
    if (ip >= 167772160 and ip <= 184549375) return true;
    if (ip >= 2886729728 and ip <= 2887778303) return true;
    if (ip >= 3232235520 and ip <= 3232301055) return true;
    return false;
}

fn writeIPv4Ranges(ranges: []const IPv4Range, writer: *std.Io.Writer, alloc: mem.Allocator, seen: *std.hash_map.StringHashMapUnmanaged(void)) !void {
    for (ranges) |range| {
        var start = range.start;
        while (start <= range.end) {
            var bits: u6 = @intCast(@ctz(start));
            while (bits > 0) {
                const max_diff: u32 = if (bits == 32) std.math.maxInt(u32) else (@as(u32, 1) << @intCast(bits)) - 1;
                if (max_diff <= range.end - start) break;
                bits -= 1;
            }
            const prefix: u6 = 32 - bits;

            const cidr = try fmt.allocPrint(alloc, "{d}.{d}.{d}.{d}/{d}", .{
                (start >> 24) & 0xFF,
                (start >> 16) & 0xFF,
                (start >> 8) & 0xFF,
                start & 0xFF,
                prefix,
            });

            if (!isPrivateIPv4(start)) {
                if (seen.contains(cidr)) {
                    alloc.free(cidr);
                } else {
                    try seen.put(alloc, cidr, {});
                    try writer.print("{s} {s};\n", .{ cidr, range.country });
                }
            } else {
                alloc.free(cidr);
            }

            if (bits == 32) break; // Reached end of IPv4 space
            const block_size: u32 = @as(u32, 1) << @intCast(bits);
            start +%= block_size;
        }
    }
}

fn writeIPv6Ranges(ranges: []const IPv6Range, writer: *std.Io.Writer, alloc: mem.Allocator, seen: *std.hash_map.StringHashMapUnmanaged(void)) !void {
    for (ranges) |range| {
        var start = parseIPv6Bytes(range.start);
        const end = parseIPv6Bytes(range.end);
        while (start <= end) {
            var bits: u8 = @intCast(@ctz(start));
            while (bits > 0) {
                const max_diff: u128 = if (bits == 128) std.math.maxInt(u128) else (@as(u128, 1) << @intCast(bits)) - 1;
                if (max_diff <= end - start) break;
                bits -= 1;
            }
            const prefix: u8 = 128 - bits;

            const cidr = try ipv6ToString(start, prefix, alloc);

            if (seen.contains(cidr)) {
                alloc.free(cidr);
            } else {
                try seen.put(alloc, cidr, {});
                try writer.print("{s} {s};\n", .{ cidr, range.country });
            }

            const block_size: u128 = if (bits == 128) std.math.maxInt(u128) else @as(u128, 1) << @intCast(bits);
            if (bits == 128) break; // If we consumed the entire space, we are done
            start +%= block_size;
        }
    }
}

fn parseIPv6Bytes(bytes: [16]u8) u128 {
    var result: u128 = 0;
    for (bytes, 0..) |b, i| {
        _ = i;
        result = (result << 8) | b;
    }
    return result;
}

fn ipv6ToString(ip: u128, prefix: u8, alloc: mem.Allocator) ![]u8 {
    return fmt.allocPrint(alloc, "{x}:{x}:{x}:{x}:{x}:{x}:{x}:{x}/{d}", .{
        @as(u16, @truncate(ip >> 112)),
        @as(u16, @truncate(ip >> 96)),
        @as(u16, @truncate(ip >> 80)),
        @as(u16, @truncate(ip >> 64)),
        @as(u16, @truncate(ip >> 48)),
        @as(u16, @truncate(ip >> 32)),
        @as(u16, @truncate(ip >> 16)),
        @as(u16, @truncate(ip)),
        prefix,
    });
}

fn parseIPv6Uint(s: []const u8) ![16]u8 {
    const n = try fmt.parseInt(u128, s, 10);
    var buf: [16]u8 = undefined;
    for (0..16) |i| {
        buf[15 - i] = @truncate(n >> @as(u7, @intCast(i * 8)));
    }
    return buf;
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
        const size = parseIPv6Bytes(end) -% parseIPv6Bytes(start) +% 1;

        try ranges.append(alloc, .{
            .start = start,
            .end = end,
            .country = try alloc.dupe(u8, country),
            .size = size,
        });
    }
}

fn parseIPv4File(dir: std.Io.Dir, io: std.Io, path: []const u8, ranges: *std.ArrayList(IPv4Range), alloc: mem.Allocator) !void {
    const content = try dir.readFileAlloc(io, path, alloc, .unlimited);
    defer alloc.free(content);

    var lines = mem.tokenizeAny(u8, content, "\n");
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parts = mem.tokenizeAny(u8, line, ",");
        const start_str = parts.next() orelse continue;
        const end_str = parts.next() orelse continue;
        const country = parts.next() orelse continue;

        const start = try fmt.parseInt(u32, start_str, 10);
        const end = try fmt.parseInt(u32, end_str, 10);
        const size = end -% start +% 1;

        try ranges.append(alloc, .{
            .start = start,
            .end = end,
            .country = try alloc.dupe(u8, country),
            .size = size,
        });
    }
}