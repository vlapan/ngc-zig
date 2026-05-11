const std = @import("std");
const mem = std.mem;

fn IPRange(comptime T: type) type {
    return struct { start: T, end: T, country: []const u8, size: T };
}
const IPv4Range = IPRange(u32);
const IPv6Range = IPRange(u128);

const SeenKey = struct { ip: u128, prefix: u8 };

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

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
    try parseFile(u32, io, ipv4_path, &ipv4_ranges, alloc);
    sortRanges(u32, ipv4_ranges.items);

    var seen_unmanaged = std.hash_map.AutoHashMapUnmanaged(SeenKey, void){};
    try seen_unmanaged.ensureTotalCapacity(alloc, 500000);

    const seen: *std.hash_map.AutoHashMapUnmanaged(SeenKey, void) = &seen_unmanaged;

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

    try writeRanges(u32, ipv4_ranges.items, writer, alloc, seen);

    var ipv6_ranges = std.ArrayList(IPv6Range).empty;
    try parseFile(u128, io, ipv6_path, &ipv6_ranges, alloc);
    sortRanges(u128, ipv6_ranges.items);

    try writeRanges(u128, ipv6_ranges.items, writer, alloc, seen);
    try out_file_writer.flush();
}

fn sortRanges(comptime T: type, ranges: []IPRange(T)) void {
    mem.sort(IPRange(T), ranges, {}, struct {
        fn less(_: void, a: IPRange(T), b: IPRange(T)) bool {
            if (a.size != b.size) return a.size < b.size;
            if (a.start != b.start) return a.start < b.start;
            return mem.order(u8, a.country, b.country) == .lt;
        }
    }.less);
}

fn parseFile(comptime T: type, io: std.Io, path: []const u8, ranges: *std.ArrayList(IPRange(T)), alloc: mem.Allocator) !void {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var in_buf: [8192]u8 = undefined;
    var file_reader = file.reader(io, &in_buf);
    const reader = &file_reader.interface;

    while (try reader.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;
        var parts = mem.tokenizeAny(u8, line, ",\r");
        const start_str = parts.next() orelse continue;
        const end_str = parts.next() orelse continue;
        const country = parts.next() orelse continue;

        const start = try std.fmt.parseInt(T, start_str, 10);
        const end = try std.fmt.parseInt(T, end_str, 10);
        const size = end -% start +% 1;

        try ranges.append(alloc, .{
            .start = start,
            .end = end,
            .country = try alloc.dupe(u8, country),
            .size = size,
        });
    }
}

fn isPrivateIPv4(ip: u32) bool {
    if (ip >= 2130706432 and ip <= 2147483647) return true;
    if (ip >= 2851995648 and ip <= 2852061183) return true;
    if (ip >= 167772160 and ip <= 184549375) return true;
    if (ip >= 2886729728 and ip <= 2887778303) return true;
    if (ip >= 3232235520 and ip <= 3232301055) return true;
    return false;
}

fn findBlockBits(comptime T: type, start: T, end: T) u8 {
    if (start == 0 and end == std.math.maxInt(T)) return @bitSizeOf(T);
    var bits: u8 = @intCast(@ctz(start));
    while (bits > 0) {
        const max_diff: T = if (bits == @bitSizeOf(T)) std.math.maxInt(T) else (@as(T, 1) << @intCast(bits)) - 1;
        if (max_diff <= end - start) break;
        bits -= 1;
    }
    return bits;
}

fn writeRanges(comptime T: type, ranges: []const IPRange(T), writer: *std.Io.Writer, alloc: mem.Allocator, seen: *std.hash_map.AutoHashMapUnmanaged(SeenKey, void)) !void {
    for (ranges) |range| {
        var start = range.start;
        while (start <= range.end) {
            const bits = findBlockBits(T, start, range.end);
            const prefix: u8 = @as(u8, @intCast(@bitSizeOf(T))) - bits;

            if (T == u32 and isPrivateIPv4(start)) {
                if (bits == @bitSizeOf(T)) break;
                start +%= @as(T, 1) << @intCast(bits);
                continue;
            }

            const key = SeenKey{ .ip = if (T == u32) @as(u128, start) else start, .prefix = prefix };
            const entry = try seen.getOrPut(alloc, key);
            if (!entry.found_existing) {
                if (T == u32) {
                    try writer.print("{d}.{d}.{d}.{d}/{d} {s};\n", .{ (start >> 24) & 0xFF, (start >> 16) & 0xFF, (start >> 8) & 0xFF, start & 0xFF, prefix, range.country });
                } else {
                    try writer.print("{x}:{x}:{x}:{x}:{x}:{x}:{x}:{x}/{d} {s};\n", .{ @as(u16, @truncate(start >> 112)), @as(u16, @truncate(start >> 96)), @as(u16, @truncate(start >> 80)), @as(u16, @truncate(start >> 64)), @as(u16, @truncate(start >> 48)), @as(u16, @truncate(start >> 32)), @as(u16, @truncate(start >> 16)), @as(u16, @truncate(start)), prefix, range.country });
                }
            }

            if (bits == @bitSizeOf(T)) break;
            start +%= @as(T, 1) << @intCast(bits);
        }
    }
}
