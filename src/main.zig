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
    const _ipv6_path = args.next() orelse {
        std.debug.print("Usage: geoip-converter <ipv4_csv> <ipv6_csv> <output_file>\n", .{});
        return error.InvalidArgs;
    };
    _ = _ipv6_path;
    const output_path = args.next() orelse {
        std.debug.print("Usage: geoip-converter <ipv4_csv> <ipv6_csv> <output_file>\n", .{});
        return error.InvalidArgs;
    };

    var ipv4_ranges = std.ArrayList(IPv4Range).empty;
    defer ipv4_ranges.deinit(alloc);
    try parseIPv4File(std.Io.Dir.cwd(), io, ipv4_path, &ipv4_ranges, alloc);

    mem.sort(IPv4Range, ipv4_ranges.items, {}, struct {
        fn less(_: void, a: IPv4Range, b: IPv4Range) bool {
            return a.size > b.size;
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
    try writeIPv4Ranges(ipv4_ranges.items, &out_file_writer.interface, alloc, seen);
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
            try writer.print("{s} {s};\n", .{ cidr, range.country });
        }
    }
}

fn writeIPv6RangesPlaceholder(writer: *std.Io.Writer) !void {
    _ = writer;
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