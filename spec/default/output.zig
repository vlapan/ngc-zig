/// Stage: OUTPUT
/// Converts disjoint Segments (from RESOLVE stage) into CIDR text lines,
/// filtering out HOLE and private ranges. This is the final stage of the
/// pipeline — output is ready for Nginx geo module consumption.
///
/// Input:
///   Segment(T)  — { start: T, end: T, country: u16 }
///
/// Output line format (Nginx geo module):
///   <ip>/<prefix> <cc>;
///   <ip>/<prefix> <cc>;\n
///   Examples:
///     8.8.8.0/24 US;\n
///     2001:db8::/32 US;\n
///     ::/0 US;\n
///
/// Data structures:
///   CidrBlock(T)   — { addr: T, prefix: u8, step: T }
///   CidrStats      — { cidrs: usize }
///
/// Functions:
///   computeCidrBlock(T, addr, end)
///     — Given current address and range end, compute the largest
///       power-of-2 aligned CIDR block that fits within [addr, end].
///       Invariant: addr is prefix-aligned, step is a power of 2.
///
///   rangeToCidrs(T, writer, start, end, country)
///     — Iteratively calls computeCidrBlock, writes output lines.
///     - HOLE country (0xFFFF) → no output
///     - IPv4 private ranges (RFC 1918 + loopback + link-local) → no output
///     - IPv6 private ranges (fc00::/7 unique-local, fe80::/10 link-local) → no output
///     - c_val=0 (null/empty country) → writes \x00\x00 as country string
///       (intentional: exposes bad data in output for debugging)
///
///   formatIPv4Line / formatIPv6Line
///     — Format a single CIDR line into a fixed buffer (no allocator).
///     Always newline-terminated.
///
///   formatIPv4 / formatIPv6
///     — Write a single CIDR line to a buffered writer.
///
///   isPrivateIPv4(ip)
///     — Returns true if ip falls in: 10.0.0.0/8, 127.0.0.0/8,
///       169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16.
///
/// Invariants:
///   - Every output line ends with \n
///   - rangeToCidrs produces minimal CIDRs (no sub-optimal grouping)
///   - HOLE and private ranges produce exactly 0 CIDRs
///   - Full address space (0..maxInt(T)) emits exactly 1 CIDR (/0)
///
/// Non-goals:
///   - No segment resolution (see resolve.zig)
///   - No file output
const std = @import("std");
const lib = @import("lib");
const helpers = @import("../_helpers.zig");
const testing = std.testing;

const compute_cidr_block_u32_rows = [_]struct {
    id: []const u8,
    given: []const u8,
    addr: u32,
    end: u32,
    expected_addr: u32,
    expected_prefix: u8,
    expected_step: u32,
}{
    .{ .id = "CIDR-001", .given = "single IP (remaining=1)", .addr = 10, .end = 10, .expected_addr = 10, .expected_prefix = 32, .expected_step = 1 },
    .{ .id = "CIDR-002", .given = "aligned /24 boundary", .addr = 0x01020300, .end = 0x010203FF, .expected_addr = 0x01020300, .expected_prefix = 24, .expected_step = 256 },
    .{ .id = "CIDR-003", .given = "non-aligned range [10, 20]", .addr = 10, .end = 20, .expected_addr = 10, .expected_prefix = 31, .expected_step = 2 },
    .{ .id = "CIDR-004", .given = "address at zero boundary", .addr = 0, .end = 255, .expected_addr = 0, .expected_prefix = 24, .expected_step = 256 },
};

const compute_cidr_block_u128_rows = [_]struct {
    id: []const u8,
    given: []const u8,
    addr: u128,
    end: u128,
    expected_addr: u128,
    expected_prefix: u8,
    expected_step: u128,
}{
    .{ .id = "CIDR-005", .given = "IPv6 single address", .addr = 1, .end = 1, .expected_addr = 1, .expected_prefix = 128, .expected_step = 1 },
    .{ .id = "CIDR-006", .given = "IPv6 non-aligned range [1,3]", .addr = 0x20010DB8000000000000000000000001, .end = 0x20010DB8000000000000000000000003, .expected_addr = 0x20010DB8000000000000000000000001, .expected_prefix = 128, .expected_step = 1 },
};

const format_ipv4_line_rows = [_]struct {
    id: []const u8,
    given: []const u8,
    ip: u32,
    prefix: u8,
    country: u16,
    expected: []const u8,
}{
    .{ .id = "IP-001", .given = "8.8.8.8/32 US", .ip = 0x08080808, .prefix = 32, .country = helpers.us_idx, .expected = "8.8.8.8/32 US;\n" },
    .{ .id = "IP-002", .given = "0.0.0.0/0 US", .ip = 0, .prefix = 0, .country = helpers.us_idx, .expected = "0.0.0.0/0 US;\n" },
    .{ .id = "IP-003", .given = "255.255.255.255/32 US", .ip = 0xFFFFFFFF, .prefix = 32, .country = helpers.us_idx, .expected = "255.255.255.255/32 US;\n" },
    .{ .id = "IP-004", .given = "1.1.1.0/24 DE", .ip = 0x01010100, .prefix = 24, .country = helpers.de_idx, .expected = "1.1.1.0/24 DE;\n" },
};

const format_ipv6_line_rows = [_]struct {
    id: []const u8,
    given: []const u8,
    ip: u128,
    prefix: u8,
    country: u16,
    expected: []const u8,
}{
    .{ .id = "IP-005", .given = "2001:db8::1/128 US", .ip = 0x20010DB8000000000000000000000001, .prefix = 128, .country = helpers.us_idx, .expected = "2001:db8::1/128 US;\n" },
    .{ .id = "IP-006", .given = "::/0 US (full space)", .ip = 0, .prefix = 0, .country = helpers.us_idx, .expected = "::/0 US;\n" },
    .{ .id = "IP-007", .given = "::/128 US (all zeros)", .ip = 0, .prefix = 128, .country = helpers.us_idx, .expected = "::/128 US;\n" },
};

const is_private_ipv6_rows = [_]struct {
    id: []const u8,
    given: []const u8,
    ip: u128,
    expected: bool,
}{
    .{ .id = "IP-015", .given = "fc00:: is private (unique local)", .ip = 0xFC000000000000000000000000000000, .expected = true },
    .{ .id = "IP-016", .given = "fdff:: is private (unique local)", .ip = 0xFDFF0000000000000000000000000000, .expected = true },
    .{ .id = "IP-017", .given = "fe80:: is private (link-local)", .ip = 0xFE800000000000000000000000000000, .expected = true },
    .{ .id = "IP-018", .given = "febf:: is private (link-local)", .ip = 0xFEBF0000000000000000000000000000, .expected = true },
    .{ .id = "IP-019", .given = "2001:db8:: is not private", .ip = 0x20010DB8000000000000000000000000, .expected = false },
    .{ .id = "IP-020", .given = ":: is not private", .ip = 0, .expected = false },
    .{ .id = "IP-021", .given = "ff00:: is not private", .ip = 0xFF000000000000000000000000000000, .expected = false },
};

const is_private_ipv4_rows = [_]struct {
    id: []const u8,
    given: []const u8,
    ip: u32,
    expected: bool,
}{
    .{ .id = "IP-008", .given = "127.0.0.1 is private", .ip = 0x7F000001, .expected = true },
    .{ .id = "IP-009", .given = "169.254.0.1 is private", .ip = 0xA9FE0001, .expected = true },
    .{ .id = "IP-010", .given = "10.0.0.1 is private", .ip = 0x0A000001, .expected = true },
    .{ .id = "IP-011", .given = "172.16.0.1 is private", .ip = 0xAC100001, .expected = true },
    .{ .id = "IP-012", .given = "192.168.0.1 is private", .ip = 0xC0A80001, .expected = true },
    .{ .id = "IP-013", .given = "8.8.8.8 is not private", .ip = 0x08080808, .expected = false },
    .{ .id = "IP-014", .given = "1.1.1.1 is not private", .ip = 0x01010101, .expected = false },
};

test "cidr: single /32 IPv4" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const stats = try lib.cidr.rangeToCidrs(u32, &aw.writer, 0x08080808, 0x08080808, us_idx);
    try testing.expectEqual(@as(usize, 1), stats.cidrs);
    try testing.expectEqualStrings("8.8.8.8/32 US;\n", aw.writer.buffered());
}

test "cidr: single /24 IPv4 block" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const stats = try lib.cidr.rangeToCidrs(u32, &aw.writer, 0x01020300, 0x010203FF, us_idx);
    try testing.expectEqual(@as(usize, 1), stats.cidrs);
    try testing.expectEqualStrings("1.2.3.0/24 US;\n", aw.writer.buffered());
}

test "cidr: non-aligned range produces multiple CIDRs" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const stats = try lib.cidr.rangeToCidrs(u32, &aw.writer, 10, 20, us_idx);
    try testing.expectEqual(@as(usize, 4), stats.cidrs);
    const expected = "0.0.0.10/31 US;\n0.0.0.12/30 US;\n0.0.0.16/30 US;\n0.0.0.20/32 US;\n";
    try testing.expectEqualStrings(expected, aw.writer.buffered());
}

test "cidr: full IPv4 space /0" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const stats = try lib.cidr.rangeToCidrs(u32, &aw.writer, 0, std.math.maxInt(u32), us_idx);
    try testing.expectEqual(@as(usize, 1), stats.cidrs);
    try testing.expectEqualStrings("0.0.0.0/0 US;\n", aw.writer.buffered());
}

test "cidr: two halves merge into /1 blocks" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const mid = std.math.maxInt(u32) / 2;
    const stats = try lib.cidr.rangeToCidrs(u32, &aw.writer, 0, mid, us_idx);
    try testing.expectEqual(@as(usize, 1), stats.cidrs);
    try testing.expectEqualStrings("0.0.0.0/1 US;\n", aw.writer.buffered());
}

test "cidr: HOLE country produces no output" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    const stats = try lib.cidr.rangeToCidrs(u32, &aw.writer, 0, 255, lib.cidr.HOLE);
    try testing.expectEqual(@as(usize, 0), stats.cidrs);
    try testing.expectEqualStrings("", aw.writer.buffered());
}

test "cidr: private IPv4 ranges are skipped" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const stats = try lib.cidr.rangeToCidrs(u32, &aw.writer, 0x0A000000, 0x0A0000FF, us_idx);
    try testing.expectEqual(@as(usize, 0), stats.cidrs);
    try testing.expectEqualStrings("", aw.writer.buffered());
}

test "cidr: IPv6 single /128" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const ip: u128 = 0x20010DB8000000000000000000000001;
    const stats = try lib.cidr.rangeToCidrs(u128, &aw.writer, ip, ip, us_idx);
    try testing.expectEqual(@as(usize, 1), stats.cidrs);
    try testing.expectEqualStrings("2001:db8::1/128 US;\n", aw.writer.buffered());
}

test "cidr: IPv6 /64 block" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const start: u128 = 0x20010DB8000100000000000000000000;
    const end: u128 = 0x20010DB800010000FFFFFFFFFFFFFFFF;
    const stats = try lib.cidr.rangeToCidrs(u128, &aw.writer, start, end, us_idx);
    try testing.expectEqual(@as(usize, 1), stats.cidrs);
    try testing.expectEqualStrings("2001:db8:1::/64 US;\n", aw.writer.buffered());
}

test "cidr: IPv6 full /0 space" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const stats = try lib.cidr.rangeToCidrs(u128, &aw.writer, 0, std.math.maxInt(u128), us_idx);
    try testing.expectEqual(@as(usize, 1), stats.cidrs);
    try testing.expectEqualStrings("::/0 US;\n", aw.writer.buffered());
}

test "cidr: range at top of IPv4 space boundary" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const max = std.math.maxInt(u32);
    const stats = try lib.cidr.rangeToCidrs(u32, &aw.writer, max - 255, max, us_idx);
    try testing.expectEqual(@as(usize, 1), stats.cidrs);
    try testing.expectEqualStrings("255.255.255.0/24 US;\n", aw.writer.buffered());
}

test "cidr: range with c_val=0 (null country) produces output" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    const stats = try lib.cidr.rangeToCidrs(u32, &aw.writer, 0x08080808, 0x08080808, 0);
    try testing.expectEqual(@as(usize, 1), stats.cidrs);
    try testing.expectEqualStrings("8.8.8.8/32 \x00\x00;\n", aw.writer.buffered());
}

test "cidr: IPv6 non-aligned range" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const start: u128 = 0x20010DB8000000000000000000000001;
    const end: u128 = 0x20010DB8000000000000000000000003;
    const stats = try lib.cidr.rangeToCidrs(u128, &aw.writer, start, end, us_idx);
    try testing.expectEqual(@as(usize, 2), stats.cidrs);
    const expected = "2001:db8::1/128 US;\n2001:db8::2/127 US;\n";
    try testing.expectEqualStrings(expected, aw.writer.buffered());
}

test "IPv6 RFC 5952 Zero Compression Edge Cases" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    const country: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');

    aw.clearRetainingCapacity();
    const ip1: u128 = (0x2001 << 112) | (0x0db8 << 96);
    try lib.ip.formatIPv6(&aw.writer, ip1, 32, country);
    try testing.expectEqualStrings("2001:db8::/32 US;\n", aw.writer.buffered());

    aw.clearRetainingCapacity();
    const ip2: u128 = (0x2001 << 112) | (0x0db8 << 96) | (0x0002 << 16) | (0x0001);
    try lib.ip.formatIPv6(&aw.writer, ip2, 128, country);
    try testing.expectEqualStrings("2001:db8::2:1/128 US;\n", aw.writer.buffered());

    aw.clearRetainingCapacity();
    const ip3: u128 = 1;
    try lib.ip.formatIPv6(&aw.writer, ip3, 128, country);
    try testing.expectEqualStrings("::1/128 US;\n", aw.writer.buffered());

    aw.clearRetainingCapacity();
    const ip4: u128 = 0;
    try lib.ip.formatIPv6(&aw.writer, ip4, 0, country);
    try testing.expectEqualStrings("::/0 US;\n", aw.writer.buffered());

    aw.clearRetainingCapacity();
    const ip5: u128 = (0x2001 << 112) | (0x0db8 << 96) | (0x0001 << 64) | (0x0001 << 48) | (0x0001 << 32) | (0x0001 << 16) | (0x0001);
    try lib.ip.formatIPv6(&aw.writer, ip5, 128, country);
    try testing.expectEqualStrings("2001:db8:0:1:1:1:1:1/128 US;\n", aw.writer.buffered());

    aw.clearRetainingCapacity();
    const ip6: u128 = (0x2001 << 112) | (0x0db8 << 96) | (0x0001 << 48) | (0x0001);
    try lib.ip.formatIPv6(&aw.writer, ip6, 128, country);
    try testing.expectEqualStrings("2001:db8::1:0:0:1/128 US;\n", aw.writer.buffered());

    aw.clearRetainingCapacity();
    const ip7: u128 = (0x2001 << 112) | (0x0001 << 64) | (0x0001);
    try lib.ip.formatIPv6(&aw.writer, ip7, 128, country);
    try testing.expectEqualStrings("2001:0:0:1::1/128 US;\n", aw.writer.buffered());
}

test "IPv4 formatting handles edges" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');

    try lib.ip.formatIPv4(&aw.writer, 0, 0, us_idx);
    try testing.expectEqualStrings("0.0.0.0/0 US;\n", aw.writer.buffered());

    aw.clearRetainingCapacity();
    try lib.ip.formatIPv4(&aw.writer, 0xFFFFFFFF, 32, us_idx);
    try testing.expectEqualStrings("255.255.255.255/32 US;\n", aw.writer.buffered());
}

test "computeCidrBlock: u32 cases" {
    for (compute_cidr_block_u32_rows) |row| {
        const block = lib.cidr.computeCidrBlock(u32, row.addr, row.end);
        if (block.addr != row.expected_addr or block.prefix != row.expected_prefix or block.step != row.expected_step) {
            std.debug.print("FAIL {s}: {s} — expected ({d},{d},{d}), got ({d},{d},{d})\n", .{ row.id, row.given, row.expected_addr, row.expected_prefix, row.expected_step, block.addr, block.prefix, block.step });
            return error.TestFailed;
        }
    }
}

test "computeCidrBlock: u128 cases" {
    for (compute_cidr_block_u128_rows) |row| {
        const block = lib.cidr.computeCidrBlock(u128, row.addr, row.end);
        try testing.expectEqual(row.expected_addr, block.addr);
        try testing.expectEqual(row.expected_prefix, block.prefix);
        try testing.expectEqual(row.expected_step, block.step);
    }
}

test "formatIPv4Line: all cases" {
    var buf: [64]u8 = undefined;
    for (format_ipv4_line_rows) |row| {
        const result = lib.ip.formatIPv4Line(row.ip, row.prefix, row.country, &buf);
        if (!std.mem.eql(u8, row.expected, result)) {
            std.debug.print("FAIL {s}: {s} — expected '{s}', got '{s}'\n", .{ row.id, row.given, row.expected, result });
            return error.TestFailed;
        }
    }
}

test "formatIPv6Line: all cases" {
    var buf: [64]u8 = undefined;
    for (format_ipv6_line_rows) |row| {
        const result = lib.ip.formatIPv6Line(row.ip, row.prefix, row.country, &buf);
        if (!std.mem.eql(u8, row.expected, result)) {
            std.debug.print("FAIL {s}: {s} — expected '{s}', got '{s}'\n", .{ row.id, row.given, row.expected, result });
            return error.TestFailed;
        }
    }
}

test "isPrivateIPv6: all cases" {
    for (is_private_ipv6_rows) |row| {
        const result = lib.ip.isPrivateIPv6(row.ip);
        if (result != row.expected) {
            std.debug.print("FAIL {s}: {s} — expected {any}, got {any}\n", .{ row.id, row.given, row.expected, result });
            return error.TestFailed;
        }
    }
}

test "cidr: IPv6 private ranges produce no output" {
    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');

    {
        var aw: std.Io.Writer.Allocating = .init(testing.allocator);
        defer aw.deinit();
        const stats = try lib.cidr.rangeToCidrs(u128, &aw.writer, 0xFC000000000000000000000000000000, 0xFC000000000000000000000000000001, us_idx);
        try testing.expectEqual(@as(usize, 0), stats.cidrs);
        try testing.expectEqualStrings("", aw.writer.buffered());
    }
    {
        var aw: std.Io.Writer.Allocating = .init(testing.allocator);
        defer aw.deinit();
        const stats = try lib.cidr.rangeToCidrs(u128, &aw.writer, 0xFE800000000000000000000000000001, 0xFE800000000000000000000000000001, us_idx);
        try testing.expectEqual(@as(usize, 0), stats.cidrs);
        try testing.expectEqualStrings("", aw.writer.buffered());
    }
}

test "isPrivateIPv4: all cases" {
    for (is_private_ipv4_rows) |row| {
        const result = lib.ip.isPrivateIPv4(row.ip);
        if (result != row.expected) {
            std.debug.print("FAIL {s}: {s} — expected {any}, got {any}\n", .{ row.id, row.given, row.expected, result });
            return error.TestFailed;
        }
    }
}
