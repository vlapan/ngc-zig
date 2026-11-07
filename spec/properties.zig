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

test "PROP-009: parseInt round-trips valid decimal integers" {
    const seed: u64 = 12345;
    var rng = std.Random.DefaultPrng.init(seed);
    const rand = rng.random();
    var buf: [20]u8 = undefined;

    for (0..19) |_| {
        const n: u32 = rand.int(u32);
        const text = try std.fmt.bufPrint(&buf, "{d}", .{n});
        try testing.expectEqual(n, try lib.parse.parseInt(u32, text));
    }
}

test "PROP-010: parseInt rejects malformed numeric spellings" {
    try testing.expectError(error.InvalidCharacter, lib.parse.parseInt(u32, ""));
    try testing.expectError(error.InvalidCharacter, lib.parse.parseInt(u32, "12A45"));
    try testing.expectError(error.InvalidCharacter, lib.parse.parseInt(u32, " 123"));
    try testing.expectError(error.InvalidCharacter, lib.parse.parseInt(u32, "123 "));
}

test "PROP-011: flatten output is ordered and non-overlapping" {
    const seed: u64 = 98765;
    var rng = std.Random.DefaultPrng.init(seed);
    const rand = rng.random();
    var ranges = std.ArrayList(lib.ip.IPRange(u32)).empty;
    defer ranges.deinit(std.testing.allocator);

    for (0..50) |_| {
        ranges.clearRetainingCapacity();
        const count = rand.int(u8) % 12 + 1;
        for (0..count) |_| {
            const start = rand.int(u32) % 96;
            const width = rand.int(u32) % 32 + 1;
            const end = if (start + width - 1 < start) std.math.maxInt(u32) else start + width - 1;
            try ranges.append(std.testing.allocator, .{
                .start = start,
                .end = end,
                .country = @as(u16, @intCast(rand.int(u8) % 8)),
                .size = end -% start +% 1,
            });
        }

        var segments = std.ArrayList(lib.flatten.Segment(u32)).empty;
        defer segments.deinit(std.testing.allocator);
        _ = try lib.flatten.flatten(u32, std.testing.allocator, ranges.items, &segments);

        var prev_end: ?u32 = null;
        for (segments.items) |seg| {
            if (prev_end) |p| try testing.expect(seg.start > p);
            prev_end = seg.end;
        }
    }
}
