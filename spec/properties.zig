/// Tier: PROPERTY
/// Random-input invariant checks for CIDR block generation and formatting.
/// Finds edge cases that static IAE tables miss (large numbers, boundary
/// conditions, unusual alignments).
///
/// Properties:
///   PROP-001 (u32): computeCidrBlock produces power-of-2 aligned addresses
///   PROP-002 (u32): CIDR step is always a power of 2
///   PROP-003 (u32): CIDR block never exceeds requested range
///   PROP-004 (u32): formatIPv4Line output always newline-terminated
///   PROP-005 (u128): same as PROP-001 for IPv6
///   PROP-006 (u128): same as PROP-002 for IPv6
///   PROP-007 (u128): same as PROP-003 for IPv6
///   PROP-008 (u128): formatIPv6Line output always newline-terminated
///
/// Generation strategy:
///   randomRange: 50% small random ranges, 50% edge cases (single IP, max boundary)
///   Same logic for u128 with randomRange128 (random u128 start, small range)
///
/// Invariants (across all tests):
///   - step == 0  → addr=0, prefix=0 (full /0)
///   - step > 0   → addr % step == 0, step & (step-1) == 0
///   - block covers [addr, addr + step - 1] ⊆ [start, end]
///   - Every output line ends with \n
const std = @import("std");
const lib = @import("lib");
const testing = std.testing;

fn randomRange(rand: std.Random) struct { start: u32, end: u32 } {
    if (rand.boolean()) {
        const start = rand.int(u32);
        const remaining = rand.int(u32) % 65536 + 1;
        const end = if (start +% remaining < start) std.math.maxInt(u32) else start + remaining;
        return .{ .start = start, .end = end };
    } else {
        const edge = rand.enumValue(enum { single, max_boundary });
        return switch (edge) {
            .single => blk: {
                const ip = rand.int(u32);
                break :blk .{ .start = ip, .end = ip };
            },
            .max_boundary => .{ .start = std.math.maxInt(u32) -% rand.intRangeAtMost(u32, 1, 255), .end = std.math.maxInt(u32) },
        };
    }
}

fn randomRange128(rand: std.Random) struct { start: u128, end: u128 } {
    if (rand.boolean()) {
        const start = rand.int(u128);
        const remaining: u128 = @intCast(rand.int(u64) % 65536 + 1);
        const end = if (start +% remaining < start) std.math.maxInt(u128) else start + remaining;
        return .{ .start = start, .end = end };
    } else {
        const edge = rand.enumValue(enum { single, max_boundary });
        return switch (edge) {
            .single => blk: {
                const ip = rand.int(u128);
                break :blk .{ .start = ip, .end = ip };
            },
            .max_boundary => .{ .start = std.math.maxInt(u128) -% rand.intRangeAtMost(u128, 1, 255), .end = std.math.maxInt(u128) },
        };
    }
}

test "PROP-001: CIDR blocks are power-of-2 aligned" {
    const seed: u64 = 42;
    var rng = std.Random.DefaultPrng.init(seed);
    const rand = rng.random();

    for (0..1000) |_| {
        const range = randomRange(rand);
        const block = lib.cidr.computeCidrBlock(u32, range.start, range.end);
        try testing.expect(block.step == 0 or block.addr & (block.step - 1) == 0);
    }
}

test "PROP-002: CIDR step is always a power of 2" {
    const seed: u64 = 42;
    var rng = std.Random.DefaultPrng.init(seed);
    const rand = rng.random();

    for (0..1000) |_| {
        const range = randomRange(rand);
        const block = lib.cidr.computeCidrBlock(u32, range.start, range.end);
        try testing.expect(block.step == 0 or block.step & (block.step - 1) == 0);
        try testing.expect(block.step <= range.end -% range.start +% 1);
    }
}

test "PROP-003: CIDR block covers at most the requested range" {
    const seed: u64 = 42;
    var rng = std.Random.DefaultPrng.init(seed);
    const rand = rng.random();

    for (0..1000) |_| {
        const range = randomRange(rand);
        const block = lib.cidr.computeCidrBlock(u32, range.start, range.end);
        try testing.expect(block.addr >= range.start);
        try testing.expect(block.step == 0 or block.addr + (block.step - 1) <= range.end);
    }
}

test "PROP-004: formatIPv4Line output is always newline-terminated" {
    const seed: u64 = 42;
    var rng = std.Random.DefaultPrng.init(seed);
    const rand = rng.random();
    var buf: [64]u8 = undefined;

    for (0..500) |_| {
        const ip = rand.int(u32);
        const prefix: u8 = @intCast(rand.int(u8) % 33);
        const country: u16 = @intCast(rand.int(u16));
        const line = lib.ip.formatIPv4Line(ip, prefix, country, &buf);
        try testing.expect(line.len >= 2);
        try testing.expect(line[line.len - 1] == '\n');
    }
}

test "PROP-005: u128 CIDR blocks are power-of-2 aligned" {
    const seed: u64 = 42;
    var rng = std.Random.DefaultPrng.init(seed);
    const rand = rng.random();

    for (0..1000) |_| {
        const range = randomRange128(rand);
        const block = lib.cidr.computeCidrBlock(u128, range.start, range.end);
        try testing.expect(block.step == 0 or block.addr & (block.step - 1) == 0);
    }
}

test "PROP-006: u128 CIDR step is always a power of 2" {
    const seed: u64 = 42;
    var rng = std.Random.DefaultPrng.init(seed);
    const rand = rng.random();

    for (0..1000) |_| {
        const range = randomRange128(rand);
        const block = lib.cidr.computeCidrBlock(u128, range.start, range.end);
        try testing.expect(block.step == 0 or block.step & (block.step - 1) == 0);
        try testing.expect(block.step <= range.end -% range.start +% 1);
    }
}

test "PROP-007: u128 CIDR block covers at most the requested range" {
    const seed: u64 = 42;
    var rng = std.Random.DefaultPrng.init(seed);
    const rand = rng.random();

    for (0..1000) |_| {
        const range = randomRange128(rand);
        const block = lib.cidr.computeCidrBlock(u128, range.start, range.end);
        try testing.expect(block.addr >= range.start);
        try testing.expect(block.step == 0 or block.addr + (block.step - 1) <= range.end);
    }
}

test "PROP-008: formatIPv6Line output is always newline-terminated" {
    const seed: u64 = 42;
    var rng = std.Random.DefaultPrng.init(seed);
    const rand = rng.random();
    var buf: [64]u8 = undefined;

    for (0..500) |_| {
        const ip = rand.int(u128);
        const prefix: u8 = @intCast(rand.int(u8) % 129);
        const country: u16 = @intCast(rand.int(u16));
        const line = lib.ip.formatIPv6Line(ip, prefix, country, &buf);
        try testing.expect(line.len >= 2);
        try testing.expect(line[line.len - 1] == '\n');
    }
}
