const std = @import("std");
const lib = @import("lib");
const perf = @import("perf_helpers");

pub const Cidr = struct {
    pub const title = "CIDR";

    pub const Row = struct {
        id: []const u8,
        label: []const u8,
        start: u32,
        end: u32,
    };

    pub const rows align(perf.cache_line) = [_]Row{
        .{
            .id = "CIDR-PRF-001",
            .label = "computeCidrBlock: /24 aligned",
            .start = 0x01020300,
            .end = 0x010203FF,
        },
        .{
            .id = "CIDR-PRF-002",
            .label = "computeCidrBlock: unaligned range [10,20]",
            .start = 10,
            .end = 20,
        },
        .{
            .id = "CIDR-PRF-003",
            .label = "computeCidrBlock: /0 full space",
            .start = 0,
            .end = std.math.maxInt(u32),
        },
    };

    pub fn runOnce(row: Row) align(perf.cache_line) void {
        std.mem.doNotOptimizeAway(lib.cidr.computeCidrBlock(u32, row.start, row.end));
    }

    pub fn run(row: Row, iters: usize) align(perf.cache_line) u64 {
        const t0 = perf.now();
        for (0..iters) |_| {
            runOnce(row);
        }
        const t1 = perf.now();
        return t1 - t0;
    }
};

pub const FormatV4 = struct {
    pub const title = "CIDR";

    pub const Row = struct {
        id: []const u8,
        label: []const u8,
        ip: u32,
        prefix: u8,
        country: u16,
    };

    pub const rows align(perf.cache_line) = [_]Row{
        .{
            .id = "IPF-PRF-001",
            .label = "formatIPv4Line: /24",
            .ip = 0x01020300,
            .prefix = 24,
            .country = (@as(u16, 'U') << 8) | @as(u16, 'S'),
        },
        .{
            .id = "IPF-PRF-002",
            .label = "formatIPv4Line: /32",
            .ip = 0x08080808,
            .prefix = 32,
            .country = (@as(u16, 'U') << 8) | @as(u16, 'S'),
        },
        .{
            .id = "IPF-PRF-003",
            .label = "formatIPv4Line: /0",
            .ip = 0,
            .prefix = 0,
            .country = (@as(u16, 'U') << 8) | @as(u16, 'S'),
        },
    };

    pub fn runOnce(row: Row) align(perf.cache_line) void {
        var buf: [64]u8 = undefined;
        std.mem.doNotOptimizeAway(lib.ip.formatIPv4Line(row.ip, row.prefix, row.country, &buf));
    }

    pub fn run(row: Row, iters: usize) align(perf.cache_line) u64 {
        const t0 = perf.now();
        for (0..iters) |_| runOnce(row);
        const t1 = perf.now();
        return t1 - t0;
    }
};

pub const FormatV6 = struct {
    pub const title = "CIDR";

    pub const Row = struct {
        id: []const u8,
        label: []const u8,
        ip: u128,
        prefix: u8,
        country: u16,
    };

    pub const rows align(perf.cache_line) = [_]Row{
        .{
            .id = "IPF-PRF-004",
            .label = "formatIPv6Line: /64",
            .ip = 0x20010DB8000100000000000000000000,
            .prefix = 64,
            .country = (@as(u16, 'U') << 8) | @as(u16, 'S'),
        },
        .{
            .id = "IPF-PRF-005",
            .label = "formatIPv6Line: /128",
            .ip = 0x20010DB8000000000000000000000001,
            .prefix = 128,
            .country = (@as(u16, 'D') << 8) | @as(u16, 'E'),
        },
        .{
            .id = "IPF-PRF-006",
            .label = "formatIPv6Line: /0",
            .ip = 0,
            .prefix = 0,
            .country = (@as(u16, 'U') << 8) | @as(u16, 'S'),
        },
    };

    pub fn runOnce(row: Row) align(perf.cache_line) void {
        var buf: [64]u8 = undefined;
        std.mem.doNotOptimizeAway(lib.ip.formatIPv6Line(row.ip, row.prefix, row.country, &buf));
    }

    pub fn run(row: Row, iters: usize) align(perf.cache_line) u64 {
        const t0 = perf.now();
        for (0..iters) |_| runOnce(row);
        const t1 = perf.now();
        return t1 - t0;
    }
};
