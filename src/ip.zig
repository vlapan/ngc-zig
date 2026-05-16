const std = @import("std");

pub fn IPRange(comptime T: type) type {
    return struct { start: T, end: T, country: u16, size: T };
}

pub const IPv4Range = IPRange(u32);
pub const IPv6Range = IPRange(u128);

pub const HOLE: u16 = 0xFFFF;

pub fn isPrivateIPv4(ip: u32) bool {
    return (ip & 0xFF000000) == 0x7F000000 or // 127.0.0.0/8
        (ip & 0xFFFF0000) == 0xA9FE0000 or // 169.254.0.0/16
        (ip & 0xFF000000) == 0x0A000000 or // 10.0.0.0/8
        (ip & 0xFFF00000) == 0xAC100000 or // 172.16.0.0/12
        (ip & 0xFFFF0000) == 0xC0A80000; // 192.168.0.0/16
}

pub fn formatIPv4(writer: anytype, ip: u32, prefix: u8, country: u16) !void {
    var buf: [64]u8 = undefined;
    var idx: usize = 0;

    const b1: u8 = @intCast((ip >> 24) & 0xFF);
    const b2: u8 = @intCast((ip >> 16) & 0xFF);
    const b3: u8 = @intCast((ip >> 8) & 0xFF);
    const b4: u8 = @intCast(ip & 0xFF);

    idx += formatU8Int(buf[idx..], b1);
    buf[idx] = '.';
    idx += 1;
    idx += formatU8Int(buf[idx..], b2);
    buf[idx] = '.';
    idx += 1;
    idx += formatU8Int(buf[idx..], b3);
    buf[idx] = '.';
    idx += 1;
    idx += formatU8Int(buf[idx..], b4);
    buf[idx] = '/';
    idx += 1;
    idx += formatU8Int(buf[idx..], prefix);
    buf[idx] = ' ';
    idx += 1;

    buf[idx] = @truncate(country >> 8);
    buf[idx + 1] = @truncate(country);
    idx += 2;
    try writer.writeAll(buf[0..idx]);
    try writer.writeAll(";\n");
}

const OctetStr = struct {
    len: u8,
    bytes: [3]u8,
};

const U8_LUT: [256]OctetStr = init_lut: {
    @setEvalBranchQuota(10000);
    var table: [256]OctetStr = undefined;
    for (0..256) |i| {
        var buf: [3]u8 = undefined;
        var len: u8 = 0;
        var v: usize = i;
        if (v >= 100) {
            buf[0] = '0' + @as(u8, @intCast(v / 100));
            v %= 100;
            buf[1] = '0' + @as(u8, @intCast(v / 10));
            buf[2] = '0' + @as(u8, @intCast(v % 10));
            len = 3;
        } else if (v >= 10) {
            buf[0] = '0' + @as(u8, @intCast(v / 10));
            buf[1] = '0' + @as(u8, @intCast(v % 10));
            len = 2;
        } else {
            buf[0] = '0' + @as(u8, @intCast(v));
            len = 1;
        }
        table[i] = OctetStr{ .len = len, .bytes = buf };
    }
    break :init_lut table;
};

fn formatU8Int(buf: []u8, val: u8) usize {
    const entry = U8_LUT[val];
    buf[0] = entry.bytes[0];
    if (entry.len > 1) {
        buf[1] = entry.bytes[1];
        if (entry.len > 2) {
            buf[2] = entry.bytes[2];
        }
    }
    return entry.len;
}

const HEX_CHARS = "0123456789abcdef";

pub fn formatIPv6(writer: anytype, ip: u128, prefix: u8, country: u16) !void {
    var buf: [48]u8 = undefined;
    var idx: usize = 0;

    var chunks: [8]u16 = undefined;
    inline for (0..8) |i| {
        const shift: u7 = @intCast((7 - i) * 16);
        chunks[i] = @truncate(ip >> shift);
    }

    var longest_start: usize = 8;
    var longest_len: usize = 0;
    var current_start: usize = 0;
    var current_len: usize = 0;

    for (chunks, 0..) |chunk, i| {
        if (chunk == 0) {
            if (current_len == 0) current_start = i;
            current_len += 1;
        } else {
            if (current_len > longest_len) {
                longest_start = current_start;
                longest_len = current_len;
            }
            current_len = 0;
        }
    }
    if (current_len > longest_len) {
        longest_start = current_start;
        longest_len = current_len;
    }

    if (longest_len == 1) {
        @branchHint(.unlikely);
        longest_len = 0;
    }

    var i: usize = 0;
    var last_was_colon = false;
    while (i < 8) {
        if (longest_len > 0 and i == longest_start) {
            buf[idx] = ':';
            idx += 1;
            buf[idx] = ':';
            idx += 1;
            i += longest_len;
            last_was_colon = true;
            continue;
        }

        if (i > 0 and !last_was_colon) {
            buf[idx] = ':';
            idx += 1;
        }
        last_was_colon = false;

        const chunk = chunks[i];
        if (chunk == 0) {
            buf[idx] = '0';
            idx += 1;
        } else {
            const clz: u5 = @clz(chunk);
            const chars: u3 = @intCast(4 - (clz / 4));
            switch (chars) {
                4 => {
                    buf[idx] = HEX_CHARS[@as(usize, (chunk >> 12) & 0xF)];
                    buf[idx + 1] = HEX_CHARS[@as(usize, (chunk >> 8) & 0xF)];
                    buf[idx + 2] = HEX_CHARS[@as(usize, (chunk >> 4) & 0xF)];
                    buf[idx + 3] = HEX_CHARS[@as(usize, chunk & 0xF)];
                },
                3 => {
                    buf[idx] = HEX_CHARS[@as(usize, (chunk >> 8) & 0xF)];
                    buf[idx + 1] = HEX_CHARS[@as(usize, (chunk >> 4) & 0xF)];
                    buf[idx + 2] = HEX_CHARS[@as(usize, chunk & 0xF)];
                },
                2 => {
                    buf[idx] = HEX_CHARS[@as(usize, (chunk >> 4) & 0xF)];
                    buf[idx + 1] = HEX_CHARS[@as(usize, chunk & 0xF)];
                },
                1 => {
                    buf[idx] = HEX_CHARS[@as(usize, chunk & 0xF)];
                },
                else => unreachable,
            }
            idx += chars;
        }
        i += 1;
    }

    buf[idx] = '/';
    idx += 1;
    idx += formatU8Int(buf[idx..], prefix);
    buf[idx] = ' ';
    idx += 1;

    buf[idx] = @truncate(country >> 8);
    buf[idx + 1] = @truncate(country);
    idx += 2;
    try writer.writeAll(buf[0..idx]);
    try writer.writeAll(";\n");
}

const testing = std.testing;

test "IPv6 RFC 5952 Zero Compression Edge Cases" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    const country: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');

    // Case 1: Trailing zeroes (longest run at the end)
    // Uncompressed: 2001:db8:0:0:0:0:0:0
    // Expected: 2001:db8::
    aw.clearRetainingCapacity();
    const ip1: u128 = (0x2001 << 112) | (0x0db8 << 96);
    try formatIPv6(&aw.writer, ip1, 32, country);
    try testing.expectEqualStrings("2001:db8::/32 US;\n", aw.writer.buffered());

    // Case 2: Middle zeroes (longest run in the middle)
    // Uncompressed: 2001:db8:0:0:0:0:2:1
    // Expected: 2001:db8::2:1
    aw.clearRetainingCapacity();
    const ip2: u128 = (0x2001 << 112) | (0x0db8 << 96) | (0x0002 << 16) | (0x0001);
    try formatIPv6(&aw.writer, ip2, 128, country);
    try testing.expectEqualStrings("2001:db8::2:1/128 US;\n", aw.writer.buffered());

    // Case 3: Leading zeroes (longest run at the start)
    // Uncompressed: 0:0:0:0:0:0:0:1
    // Expected: ::1
    aw.clearRetainingCapacity();
    const ip3: u128 = 1;
    try formatIPv6(&aw.writer, ip3, 128, country);
    try testing.expectEqualStrings("::1/128 US;\n", aw.writer.buffered());

    // Case 4: All zeroes
    // Uncompressed: 0:0:0:0:0:0:0:0
    // Expected: ::
    aw.clearRetainingCapacity();
    const ip4: u128 = 0;
    try formatIPv6(&aw.writer, ip4, 0, country);
    try testing.expectEqualStrings("::/0 US;\n", aw.writer.buffered());

    // Case 5: Single zero (MUST NOT compress)
    // Uncompressed: 2001:db8:0:1:1:1:1:1
    // Expected: 2001:db8:0:1:1:1:1:1
    aw.clearRetainingCapacity();
    const ip5: u128 = (0x2001 << 112) | (0x0db8 << 96) | (0x0001 << 64) | (0x0001 << 48) | (0x0001 << 32) | (0x0001 << 16) | (0x0001);
    try formatIPv6(&aw.writer, ip5, 128, country);
    try testing.expectEqualStrings("2001:db8:0:1:1:1:1:1/128 US;\n", aw.writer.buffered());

    // Case 6: Multiple equal-length zero runs (MUST compress FIRST run)
    // Uncompressed: 2001:db8:0:0:1:0:0:1
    // Expected: 2001:db8::1:0:0:1
    aw.clearRetainingCapacity();
    const ip6: u128 = (0x2001 << 112) | (0x0db8 << 96) | (0x0001 << 48) | (0x0001);
    try formatIPv6(&aw.writer, ip6, 128, country);
    try testing.expectEqualStrings("2001:db8::1:0:0:1/128 US;\n", aw.writer.buffered());

    // Case 7: Multiple unequal-length zero runs (MUST compress LONGEST run)
    // Uncompressed: 2001:0:0:1:0:0:0:1
    // Expected: 2001:0:0:1::1
    aw.clearRetainingCapacity();
    const ip7: u128 = (0x2001 << 112) | (0x0001 << 64) | (0x0001);
    try formatIPv6(&aw.writer, ip7, 128, country);
    try testing.expectEqualStrings("2001:0:0:1::1/128 US;\n", aw.writer.buffered());
}

test "isPrivateIPv4 detects correct private blocks" {
    // Localhost
    try std.testing.expect(isPrivateIPv4(0x7F000001)); // 127.0.0.1
    // APIPA
    try std.testing.expect(isPrivateIPv4(0xA9FE0001)); // 169.254.0.1
    // 10.x.x.x
    try std.testing.expect(isPrivateIPv4(0x0A000001)); // 10.0.0.1
    // 172.16.x.x
    try std.testing.expect(isPrivateIPv4(0xAC100001)); // 172.16.0.1
    // 192.168.x.x
    try std.testing.expect(isPrivateIPv4(0xC0A80001)); // 192.168.0.1

    // Public IPs (Should return false)
    try std.testing.expect(!isPrivateIPv4(0x08080808)); // 8.8.8.8
    try std.testing.expect(!isPrivateIPv4(0x01010101)); // 1.1.1.1
}

test "IPv4 formatting handles edges" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');

    try formatIPv4(&aw.writer, 0, 0, us_idx); // 0.0.0.0/0
    try std.testing.expectEqualStrings("0.0.0.0/0 US;\n", aw.writer.buffered());

    aw.clearRetainingCapacity();
    try formatIPv4(&aw.writer, 0xFFFFFFFF, 32, us_idx); // 255.255.255.255/32
    try std.testing.expectEqualStrings("255.255.255.255/32 US;\n", aw.writer.buffered());
}
