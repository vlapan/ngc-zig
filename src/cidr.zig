const std = @import("std");
const ip_mod = @import("ip.zig");

pub const HOLE: u16 = 0xFFFF;

pub const CidrStats = struct {
    cidrs: usize = 0,
};

pub fn rangeToCidrs(comptime T: type, writer: *std.Io.Writer, start: T, end: T, country: u16) !CidrStats {
    var stats = CidrStats{};
    var current = start;
    const max_bits: u8 = @intCast(@bitSizeOf(T));

    while (current <= end) {
        if (current == 0 and end == std.math.maxInt(T)) {
            if (country != HOLE) {
                if (T == u32) {
                    try ip_mod.formatIPv4(writer, 0, 0, country);
                    stats.cidrs += 1;
                } else {
                    try ip_mod.formatIPv6(writer, 0, 0, country);
                    stats.cidrs += 1;
                }
            }
            break;
        }

        const remaining = end - current + 1;
        const align_bits: u8 = if (current == 0) max_bits else @ctz(current);
        const range_bits: u8 = max_bits - 1 - @clz(remaining);

        const bits: u8 = if (align_bits < range_bits) align_bits else range_bits;
        const block: T = @as(T, 1) << @intCast(bits);
        const prefix: u8 = max_bits - bits;

        if (country != HOLE) {
            if (T == u32) {
                if (!ip_mod.isPrivateIPv4(@intCast(current))) {
                    try ip_mod.formatIPv4(writer, @intCast(current), prefix, country);
                    stats.cidrs += 1;
                }
            } else {
                try ip_mod.formatIPv6(writer, @intCast(current), prefix, country);
                stats.cidrs += 1;
            }
        }

        current += block;
    }

    return stats;
}

const testing = std.testing;

test "cidr: single /32 IPv4" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const stats = try rangeToCidrs(u32, &aw.writer, 0x08080808, 0x08080808, us_idx);

    try testing.expectEqual(@as(usize, 1), stats.cidrs);
    try testing.expectEqualStrings("8.8.8.8/32 US;\n", aw.writer.buffered());
}

test "cidr: single /24 IPv4 block" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const stats = try rangeToCidrs(u32, &aw.writer, 0x01020300, 0x010203FF, us_idx);

    try testing.expectEqual(@as(usize, 1), stats.cidrs);
    try testing.expectEqualStrings("1.2.3.0/24 US;\n", aw.writer.buffered());
}

test "cidr: non-aligned range produces multiple CIDRs" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const stats = try rangeToCidrs(u32, &aw.writer, 10, 20, us_idx);

    try testing.expectEqual(@as(usize, 4), stats.cidrs);
    const expected = "0.0.0.10/31 US;\n0.0.0.12/30 US;\n0.0.0.16/30 US;\n0.0.0.20/32 US;\n";
    try testing.expectEqualStrings(expected, aw.writer.buffered());
}

test "cidr: full IPv4 space /0" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const stats = try rangeToCidrs(u32, &aw.writer, 0, std.math.maxInt(u32), us_idx);

    try testing.expectEqual(@as(usize, 1), stats.cidrs);
    try testing.expectEqualStrings("0.0.0.0/0 US;\n", aw.writer.buffered());
}

test "cidr: two halves merge into /1 blocks" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const mid = std.math.maxInt(u32) / 2;
    const stats = try rangeToCidrs(u32, &aw.writer, 0, mid, us_idx);

    try testing.expectEqual(@as(usize, 1), stats.cidrs);
    try testing.expectEqualStrings("0.0.0.0/1 US;\n", aw.writer.buffered());
}

test "cidr: HOLE country produces no output" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    const stats = try rangeToCidrs(u32, &aw.writer, 0, 255, HOLE);

    try testing.expectEqual(@as(usize, 0), stats.cidrs);
    try testing.expectEqualStrings("", aw.writer.buffered());
}

test "cidr: private IPv4 ranges are skipped" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const stats = try rangeToCidrs(u32, &aw.writer, 0x0A000000, 0x0A0000FF, us_idx);

    try testing.expectEqual(@as(usize, 0), stats.cidrs);
    try testing.expectEqualStrings("", aw.writer.buffered());
}

test "cidr: IPv6 single /128" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const ip: u128 = 0x20010DB8000000000000000000000001;
    const stats = try rangeToCidrs(u128, &aw.writer, ip, ip, us_idx);

    try testing.expectEqual(@as(usize, 1), stats.cidrs);
    try testing.expectEqualStrings("2001:db8::1/128 US;\n", aw.writer.buffered());
}

test "cidr: IPv6 /64 block" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const start: u128 = 0x20010DB8000100000000000000000000;
    const end: u128 = 0x20010DB800010000FFFFFFFFFFFFFFFF;
    const stats = try rangeToCidrs(u128, &aw.writer, start, end, us_idx);

    try testing.expectEqual(@as(usize, 1), stats.cidrs);
    try testing.expectEqualStrings("2001:db8:1::/64 US;\n", aw.writer.buffered());
}

test "cidr: IPv6 full /0 space" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const stats = try rangeToCidrs(u128, &aw.writer, 0, std.math.maxInt(u128), us_idx);

    try testing.expectEqual(@as(usize, 1), stats.cidrs);
    try testing.expectEqualStrings("::/0 US;\n", aw.writer.buffered());
}

test "cidr: IPv6 non-aligned range" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const start: u128 = 0x20010DB8000000000000000000000001;
    const end: u128 = 0x20010DB8000000000000000000000003;
    const stats = try rangeToCidrs(u128, &aw.writer, start, end, us_idx);

    try testing.expectEqual(@as(usize, 2), stats.cidrs);
    const expected = "2001:db8::1/128 US;\n2001:db8::2/127 US;\n";
    try testing.expectEqualStrings(expected, aw.writer.buffered());
}
