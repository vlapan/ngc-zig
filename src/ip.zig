const std = @import("std");

pub fn IPRange(comptime T: type) type {
    return struct { start: T, end: T, country: []const u8, size: T };
}

pub const IPv4Range = IPRange(u32);
pub const IPv6Range = IPRange(u128);

pub const SeenKey = struct { ip: u128, prefix: u8 };

pub const IpSet = struct {
    map: std.hash_map.AutoHashMapUnmanaged(SeenKey, void),

    pub fn init() IpSet {
        return .{ .map = .{} };
    }

    pub fn ensureTotalCapacity(self: *IpSet, alloc: std.mem.Allocator, size: u32) !void {
        try self.map.ensureTotalCapacity(alloc, size);
    }

    pub fn checkAndMark(self: *IpSet, alloc: std.mem.Allocator, ip: u128, prefix: u8) !bool {
        const key = SeenKey{ .ip = ip, .prefix = prefix };
        const entry = try self.map.getOrPut(alloc, key);
        return entry.found_existing;
    }
};

pub fn sortRanges(comptime T: type, ranges: []IPRange(T)) void {
    std.mem.sort(IPRange(T), ranges, {}, struct {
        fn less(_: void, a: IPRange(T), b: IPRange(T)) bool {
            if (a.size != b.size) return a.size < b.size;
            if (a.start != b.start) return a.start < b.start;
            return std.mem.order(u8, a.country, b.country) == .lt;
        }
    }.less);
}

pub fn isPrivateIPv4(ip: u32) bool {
    if (ip >= 2130706432 and ip <= 2147483647) return true;
    if (ip >= 2851995648 and ip <= 2852061183) return true;
    if (ip >= 167772160 and ip <= 184549375) return true;
    if (ip >= 2886729728 and ip <= 2887778303) return true;
    if (ip >= 3232235520 and ip <= 3232301055) return true;
    return false;
}

pub fn findBlockBits(comptime T: type, start: T, end: T) u8 {
    if (start == 0 and end == std.math.maxInt(T)) return @bitSizeOf(T);
    var bits: u8 = @intCast(@ctz(start));
    while (bits > 0) {
        const max_diff: T = if (bits == @bitSizeOf(T)) std.math.maxInt(T) else (@as(T, 1) << @intCast(bits)) - 1;
        if (max_diff <= end - start) break;
        bits -= 1;
    }
    return bits;
}

pub fn formatIPv4(writer: anytype, ip: u32, prefix: u8, country: []const u8) !void {
    var buf: [64]u8 = undefined;
    var idx: usize = 0;
    
    const b1: u8 = @intCast((ip >> 24) & 0xFF);
    const b2: u8 = @intCast((ip >> 16) & 0xFF);
    const b3: u8 = @intCast((ip >> 8) & 0xFF);
    const b4: u8 = @intCast(ip & 0xFF);
    
    idx += formatU8Int(buf[idx..], b1); buf[idx] = '.'; idx += 1;
    idx += formatU8Int(buf[idx..], b2); buf[idx] = '.'; idx += 1;
    idx += formatU8Int(buf[idx..], b3); buf[idx] = '.'; idx += 1;
    idx += formatU8Int(buf[idx..], b4); buf[idx] = '/'; idx += 1;
    idx += formatU8Int(buf[idx..], prefix); buf[idx] = ' '; idx += 1;
    
    try writer.writeAll(buf[0..idx]);
    try writer.writeAll(country);
    try writer.writeAll(";\n");
}

fn formatU8Int(buf: []u8, val: u8) usize {
    var v = val;
    var idx: usize = 0;
    if (v >= 100) {
        buf[idx] = '0' + (v / 100); idx += 1;
        v %= 100;
        buf[idx] = '0' + (v / 10); idx += 1;
        buf[idx] = '0' + (v % 10); idx += 1;
    } else if (v >= 10) {
        buf[idx] = '0' + (v / 10); idx += 1;
        buf[idx] = '0' + (v % 10); idx += 1;
    } else {
        buf[idx] = '0' + v; idx += 1;
    }
    return idx;
}

const HEX_CHARS = "0123456789abcdef";

pub fn formatIPv6(writer: anytype, ip: u128, prefix: u8, country: []const u8) !void {
    var buf: [128]u8 = undefined;
    var idx: usize = 0;
    
    inline for (0..8) |i| {
        const shift: u7 = @intCast((7 - i) * 16);
        const chunk: u16 = @truncate(ip >> shift);
        
        if (chunk == 0) {
            buf[idx] = '0'; idx += 1;
        } else {
            var started = false;
            inline for (0..4) |nibble| {
                const n_shift: u4 = @intCast((3 - nibble) * 4);
                const nib: u8 = @intCast((chunk >> n_shift) & 0xF);
                if (nib != 0 or started) {
                    buf[idx] = HEX_CHARS[nib]; idx += 1;
                    started = true;
                }
            }
        }
        
        if (i < 7) {
            buf[idx] = ':'; idx += 1;
        }
    }
    
    buf[idx] = '/'; idx += 1;
    idx += formatU8Int(buf[idx..], prefix); buf[idx] = ' '; idx += 1;
    
    try writer.writeAll(buf[0..idx]);
    try writer.writeAll(country);
    try writer.writeAll(";\n");
}
