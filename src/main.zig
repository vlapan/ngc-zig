const std = @import("std");
const cli = @import("cli.zig");
const ip_mod = @import("ip.zig");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    const config = cli.parseArgs(init, alloc) catch |err| {
        if (err == error.InvalidArgs) return;
        return err;
    };

    var seen = ip_mod.IpSet.init();
    try seen.ensureTotalCapacity(alloc, 500000);

    const out_file = try std.Io.Dir.cwd().createFile(init.io, config.output, .{});
    defer out_file.close(init.io);

    var out_buf: [65536]u8 = undefined;
    var out_file_writer = out_file.writer(init.io, &out_buf);
    const writer = &out_file_writer.interface;

    if (config.static_file) |static_path| {
        try appendStaticFile(init.io, static_path, writer);
    }

    var ipv4_ranges = std.ArrayList(ip_mod.IPv4Range).empty;
    try parseFile(u32, init.io, config.ipv4_csv, &ipv4_ranges, alloc);
    ip_mod.sortRanges(u32, ipv4_ranges.items);
    try writeRanges(u32, ipv4_ranges.items, writer, alloc, &seen);

    var ipv6_ranges = std.ArrayList(ip_mod.IPv6Range).empty;
    try parseFile(u128, init.io, config.ipv6_csv, &ipv6_ranges, alloc);
    ip_mod.sortRanges(u128, ipv6_ranges.items);
    try writeRanges(u128, ipv6_ranges.items, writer, alloc, &seen);
    
    try out_file_writer.flush();
}

fn appendStaticFile(io: std.Io, path: []const u8, writer: *std.Io.Writer) !void {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var in_buf: [65536]u8 = undefined;
    var file_reader = file.reader(io, &in_buf);
    const reader = &file_reader.interface;

    while (try reader.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;
        var final_line = line;
        if (final_line[final_line.len - 1] == '\r') {
            final_line = final_line[0 .. final_line.len - 1];
        }
        if (final_line.len == 0) continue;
        try writer.writeAll(final_line);
        try writer.writeAll("\n");
    }
}

fn parseFile(comptime T: type, io: std.Io, path: []const u8, ranges: *std.ArrayList(ip_mod.IPRange(T)), alloc: std.mem.Allocator) !void {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var in_buf: [65536]u8 = undefined;
    var file_reader = file.reader(io, &in_buf);
    const reader = &file_reader.interface;

    while (try reader.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;
        
        const comma1 = std.mem.indexOfScalar(u8, line, ',') orelse continue;
        const comma2 = std.mem.indexOfScalarPos(u8, line, comma1 + 1, ',') orelse continue;

        const start_str = line[0..comma1];
        const end_str = line[comma1 + 1 .. comma2];
        
        var country = line[comma2 + 1 ..];
        if (country.len > 0 and country[country.len - 1] == '\r') {
            country = country[0 .. country.len - 1];
        }

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

fn writeRanges(comptime T: type, ranges: []const ip_mod.IPRange(T), writer: *std.Io.Writer, alloc: std.mem.Allocator, seen: *ip_mod.IpSet) !void {
    for (ranges) |range| {
        var start = range.start;
        while (start <= range.end) {
            const bits = ip_mod.findBlockBits(T, start, range.end);
            const prefix: u8 = @as(u8, @intCast(@bitSizeOf(T))) - bits;

            if (T == u32 and ip_mod.isPrivateIPv4(start)) {
                if (bits == @bitSizeOf(T)) break;
                start +%= @as(T, 1) << @intCast(bits);
                continue;
            }

            const ip_key = if (T == u32) @as(u128, start) else start;
            const duplicate = try seen.checkAndMark(alloc, ip_key, prefix);
            
            if (!duplicate) {
                if (T == u32) {
                    try ip_mod.formatIPv4(writer, start, prefix, range.country);
                } else {
                    try ip_mod.formatIPv6(writer, start, prefix, range.country);
                }
            }

            if (bits == @bitSizeOf(T)) break;
            start +%= @as(T, 1) << @intCast(bits);
        }
    }
}
