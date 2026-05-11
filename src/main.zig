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
            return a.start < b.start;
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

    try writer.print("\t127.0.0.0/8 RFC1918;\n", .{});
    try writer.print("\t169.254.0.0/16 RFC1918;\n", .{});
    try writer.print("\t10.0.0.0/8 RFC1918;\n", .{});
    try writer.print("\t172.16.0.0/12 RFC1918;\n", .{});
    try writer.print("\t192.168.0.0/16 RFC1918;\n", .{});

    try writeIPv4Ranges(ipv4_ranges.items, writer, alloc, seen);

    var ipv6_ranges = std.ArrayList(IPv6Range).empty;
    defer ipv6_ranges.deinit(alloc);
    try parseIPv6File(std.Io.Dir.cwd(), io, ipv6_path, &ipv6_ranges, alloc);

    try writeIPv6Ranges(ipv6_ranges.items, writer, alloc, seen);
    try out_file_writer.flush();
}

fn writeIPv4Ranges(ranges: []const IPv4Range, writer: *std.Io.Writer, alloc: mem.Allocator, seen: *std.hash_map.StringHashMapUnmanaged(void)) !void {
    for (ranges) |range| {
        var start = range.start;
        while (start <= range.end) {
            var prefix: u6 = 32;
            while (prefix > 0) {
                const bits: u6 = @intCast(32 -% prefix +% 1);
                const block_size: u32 = @as(u32, 1) << @intCast(bits);
                const alignment_check: u32 = block_size - 1;

                if (start & alignment_check != 0) break;
                if (start +% block_size -% 1 > range.end) break;

                prefix -%= 1;
            }

            const cidr = try fmt.allocPrint(alloc, "{d}.{d}.{d}.{d}/{d}", .{
                (start >> 24) & 0xFF,
                (start >> 16) & 0xFF,
                (start >> 8) & 0xFF,
                start & 0xFF,
                prefix,
            });

            const bits: u6 = @intCast(32 -% prefix);
            const block_size: u32 = if (bits == 32) 1 else @as(u32, 1) << @intCast(bits);
            start +%= block_size;

            if (seen.contains(cidr)) {
                alloc.free(cidr);
                continue;
            }
            try seen.put(alloc, cidr, {});
            try writer.print("\t{s} {s};\n", .{ cidr, range.country });
        }
    }
}

fn writeIPv6Ranges(ranges: []const IPv6Range, writer: *std.Io.Writer, alloc: mem.Allocator, seen: *std.hash_map.StringHashMapUnmanaged(void)) !void {
    for (ranges) |range| {
        var start = parseIPv6Bytes(range.start);
        const end = parseIPv6Bytes(range.end);
        while (start <= end) {
            var prefix: u8 = 128;
            while (prefix > 0) {
                const block_bits: u8 = @intCast(128 -% prefix +% 1);
                const block_size: u128 = @as(u128, 1) << @intCast(block_bits);

                if (start & (block_size - 1) != 0) break;
                if (start +% block_size -% 1 > end) break;

                prefix -%= 1;
            }

            const cidr = try ipv6ToString(start, prefix, alloc);

            if (seen.contains(cidr)) {
                alloc.free(cidr);
            } else {
                try seen.put(alloc, cidr, {});
                try writer.print("\t{s} {s};\n", .{ cidr, range.country });
            }

            const block_bits: u8 = @intCast(128 -% prefix);
            const block_size: u128 = if (block_bits == 128) 1 else @as(u128, 1) << @intCast(block_bits);
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
    var hex = try fmt.allocPrint(alloc, "{x}", .{ip});
    defer alloc.free(hex);

    while (hex.len < 32) {
        hex = try fmt.allocPrint(alloc, "0{s}", .{hex});
        defer alloc.free(hex);
    }

    var result_parts: [8]u16 = undefined;
    inline for (0..8) |i| {
        const start_idx = (7 - i) * 4;
        const chunk = hex[start_idx..start_idx + 4];
        result_parts[i] = try fmt.parseInt(u16, chunk, 16);
    }

    var str_parts: [8][]u8 = undefined;
    defer for (str_parts, 0..) |p, i| {
        if (p.len > 0) alloc.free(p);
        _ = i;
    };

    inline for (result_parts, 0..) |part, i| {
        str_parts[i] = try fmt.allocPrint(alloc, "{x}", .{part});
    }

    return fmt.allocPrint(alloc, "{s}:{s}:{s}:{s}:{s}:{s}:{s}:{s}/{d}", .{
        str_parts[0], str_parts[1], str_parts[2], str_parts[3],
        str_parts[4], str_parts[5], str_parts[6], str_parts[7],
        prefix
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