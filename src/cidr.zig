const std = @import("std");
const ip_mod = @import("ip.zig");

pub const HOLE: u16 = 0xFFFF;

pub const CidrStats = struct {
    cidrs: usize = 0,
};

pub fn CidrBlock(comptime T: type) type {
    return struct { addr: T, prefix: u8, step: T };
}

pub fn computeCidrBlock(comptime T: type, addr: T, end: T) CidrBlock(T) {
    const max_bits: u8 = @intCast(@bitSizeOf(T));
    const remaining = end -% addr +% 1;
    if (remaining == 0) return .{ .addr = addr, .prefix = 0, .step = 0 };
    const align_bits: u8 = if (addr == 0) max_bits else @ctz(addr);
    const range_bits: u8 = max_bits - 1 - @clz(remaining);
    const bits: u8 = if (align_bits < range_bits) align_bits else range_bits;
    const block: T = @as(T, 1) << @intCast(bits);
    const prefix: u8 = max_bits - bits;
    return .{ .addr = addr, .prefix = prefix, .step = block };
}

pub fn rangeToCidrs(comptime T: type, writer: *std.Io.Writer, start: T, end: T, country: u16) !CidrStats {
    var stats = CidrStats{};
    var current = start;

    while (current <= end) {
        if (current == 0 and end == std.math.maxInt(T)) {
            @branchHint(.cold);
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

        const block = computeCidrBlock(T, current, end);

        if (country != HOLE) {
            if (T == u32) {
                if (!ip_mod.isPrivateIPv4(@intCast(current))) {
                    @branchHint(.likely);
                    try ip_mod.formatIPv4(writer, @intCast(current), block.prefix, country);
                    stats.cidrs += 1;
                }
            } else {
                if (!ip_mod.isPrivateIPv6(current)) {
                    @branchHint(.likely);
                    try ip_mod.formatIPv6(writer, current, block.prefix, country);
                    stats.cidrs += 1;
                }
            }
        }

        const next = current +% block.step;
        if (next <= current) break;
        current = next;
    }

    return stats;
}
