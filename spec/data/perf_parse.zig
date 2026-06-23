const std = @import("std");
const lib = @import("lib");
const perf = @import("perf_helpers");

pub const Scan = struct {
    pub const title = "PARSE";

    pub const Row = struct {
        id: []const u8,
        label: []const u8,
        input: []const u8,
        needle: u8,
    };

    pub const rows align(perf.cache_line) = [_]Row{
        .{
            .id = "SW-PRF-001",
            .label = "findByte: CSV-like line at comma",
            .input = "12345678,90123456,US",
            .needle = ',',
        },
        .{
            .id = "SW-PRF-002",
            .label = "findByte: no match in short string",
            .input = "abcdefgh",
            .needle = ',',
        },
    };

    pub fn runOnce(row: Row) align(perf.cache_line) void {
        std.mem.doNotOptimizeAway(lib.scan.findByte(row.input, row.needle));
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

pub const ParseInt = struct {
    pub const title = "PARSE";

    pub const Row = struct {
        id: []const u8,
        label: []const u8,
        input: []const u8,
        needle: u8,
    };

    pub const rows align(perf.cache_line) = [_]Row{
        .{
            .id = "PAR-PRF-001",
            .label = "parseInt: 8-digit (IPv4 octet)",
            .input = "12345678",
            .needle = 0,
        },
        .{
            .id = "PAR-PRF-002",
            .label = "parseInt: 3-digit short",
            .input = "123",
            .needle = 0,
        },
        .{
            .id = "PAR-PRF-003",
            .label = "parseInt: 1-digit (zero)",
            .input = "0",
            .needle = 0,
        },
        .{
            .id = "PAR-PRF-004",
            .label = "parseInt: 10-digit max u32",
            .input = "4294967295",
            .needle = 0,
        },
    };

    pub fn runOnce(row: Row) align(perf.cache_line) void {
        std.mem.doNotOptimizeAway(lib.parse.parseInt(u32, row.input) catch 0);
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
