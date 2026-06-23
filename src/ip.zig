const std = @import("std");

pub fn IPRange(comptime T: type) type {
    return struct { start: T, end: T, country: u16, size: T };
}

pub const IPv4Range = IPRange(u32);
pub const IPv6Range = IPRange(u128);

pub const HOLE: u16 = 0xFFFF;

pub fn isPrivateIPv6(ip: u128) bool {
    return (ip & 0xFE000000000000000000000000000000) == 0xFC000000000000000000000000000000 or // fc00::/7
        (ip & 0xFFC00000000000000000000000000000) == 0xFE800000000000000000000000000000; // fe80::/10
}

pub fn isPrivateIPv4(ip: u32) bool {
    return (ip & 0xFF000000) == 0x7F000000 or // 127.0.0.0/8
        (ip & 0xFFFF0000) == 0xA9FE0000 or // 169.254.0.0/16
        (ip & 0xFF000000) == 0x0A000000 or // 10.0.0.0/8
        (ip & 0xFFF00000) == 0xAC100000 or // 172.16.0.0/12
        (ip & 0xFFFF0000) == 0xC0A80000; // 192.168.0.0/16
}

pub fn formatIPv4Line(ip: u32, prefix: u8, country: u16, buf: *[64]u8) []u8 {
    var idx: usize = 0;

    const b1: u8 = @intCast((ip >> 24) & 0xFF);
    const b2: u8 = @intCast((ip >> 16) & 0xFF);
    const b3: u8 = @intCast((ip >> 8) & 0xFF);
    const b4: u8 = @intCast(ip & 0xFF);

    idx += formatU8Int(buf.*[idx..], b1);
    buf.*[idx] = '.';
    idx += 1;
    idx += formatU8Int(buf.*[idx..], b2);
    buf.*[idx] = '.';
    idx += 1;
    idx += formatU8Int(buf.*[idx..], b3);
    buf.*[idx] = '.';
    idx += 1;
    idx += formatU8Int(buf.*[idx..], b4);
    buf.*[idx] = '/';
    idx += 1;
    idx += formatU8Int(buf.*[idx..], prefix);
    buf.*[idx] = ' ';
    idx += 1;

    buf.*[idx] = @truncate(country >> 8);
    buf.*[idx + 1] = @truncate(country);
    idx += 2;

    buf.*[idx] = ';';
    buf.*[idx + 1] = '\n';
    idx += 2;
    return buf.*[0..idx];
}

pub fn formatIPv4(writer: anytype, ip: u32, prefix: u8, country: u16) !void {
    var buf: [64]u8 = undefined;
    try writer.writeAll(formatIPv4Line(ip, prefix, country, &buf));
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

pub fn formatIPv6Line(ip: u128, prefix: u8, country: u16, buf: *[64]u8) []u8 {
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
            buf.*[idx] = ':';
            idx += 1;
            buf.*[idx] = ':';
            idx += 1;
            i += longest_len;
            last_was_colon = true;
            continue;
        }

        if (i > 0 and !last_was_colon) {
            buf.*[idx] = ':';
            idx += 1;
        }
        last_was_colon = false;

        const chunk = chunks[i];
        if (chunk == 0) {
            buf.*[idx] = '0';
            idx += 1;
        } else {
            const clz: u5 = @clz(chunk);
            const chars: u3 = @intCast(4 - (clz / 4));
            switch (chars) {
                4 => {
                    buf.*[idx] = HEX_CHARS[@as(usize, (chunk >> 12) & 0xF)];
                    buf.*[idx + 1] = HEX_CHARS[@as(usize, (chunk >> 8) & 0xF)];
                    buf.*[idx + 2] = HEX_CHARS[@as(usize, (chunk >> 4) & 0xF)];
                    buf.*[idx + 3] = HEX_CHARS[@as(usize, chunk & 0xF)];
                },
                3 => {
                    buf.*[idx] = HEX_CHARS[@as(usize, (chunk >> 8) & 0xF)];
                    buf.*[idx + 1] = HEX_CHARS[@as(usize, (chunk >> 4) & 0xF)];
                    buf.*[idx + 2] = HEX_CHARS[@as(usize, chunk & 0xF)];
                },
                2 => {
                    buf.*[idx] = HEX_CHARS[@as(usize, (chunk >> 4) & 0xF)];
                    buf.*[idx + 1] = HEX_CHARS[@as(usize, chunk & 0xF)];
                },
                1 => {
                    buf.*[idx] = HEX_CHARS[@as(usize, chunk & 0xF)];
                },
                else => unreachable,
            }
            idx += chars;
        }
        i += 1;
    }

    buf.*[idx] = '/';
    idx += 1;
    idx += formatU8Int(buf.*[idx..], prefix);
    buf.*[idx] = ' ';
    idx += 1;

    buf.*[idx] = @truncate(country >> 8);
    buf.*[idx + 1] = @truncate(country);
    idx += 2;

    buf.*[idx] = ';';
    buf.*[idx + 1] = '\n';
    idx += 2;
    return buf.*[0..idx];
}

pub fn formatIPv6(writer: anytype, ip: u128, prefix: u8, country: u16) !void {
    var buf: [64]u8 = undefined;
    try writer.writeAll(formatIPv6Line(ip, prefix, country, &buf));
}
