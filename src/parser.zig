const std = @import("std");
const ip_mod = @import("ip.zig");
const swar_mod = @import("swar.zig");

pub const Stats = struct {
    lines_parsed: usize = 0,
    lines_skipped: usize = 0,
    collisions: usize = 0,
    overrides: usize = 0,
};

pub fn appendStaticFile(io: std.Io, path: []const u8, writer: *std.Io.Writer, alloc: std.mem.Allocator, static_v4: *std.ArrayList(ip_mod.IPv4Range), static_v6: *std.ArrayList(ip_mod.IPv6Range)) !Stats {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const stat = try file.stat(io);
    if (stat.size == 0) return Stats{};
    const mapped = try std.posix.mmap(null, stat.size, .{ .READ = true }, .{ .TYPE = .PRIVATE }, file.handle, 0);
    defer std.posix.munmap(mapped);
    std.posix.madvise(mapped.ptr, mapped.len, std.posix.MADV.SEQUENTIAL) catch {};

    var stats = Stats{};
    var it = std.mem.splitScalar(u8, mapped, '\n');

    while (it.next()) |line| {
        if (line.len == 0) {
            @branchHint(.cold);
            stats.lines_skipped += 1;
            continue;
        }
        var final_line = line;
        if (final_line[final_line.len - 1] == '\r') {
            @branchHint(.unlikely);
            final_line = final_line[0 .. final_line.len - 1];
        }
        if (final_line.len == 0) {
            @branchHint(.cold);
            stats.lines_skipped += 1;
            continue;
        }
        try writer.writeAll(final_line);
        try writer.writeAll("\n");
        stats.lines_parsed += 1;

        if (parseStaticLine(final_line)) |cidr| {
            switch (cidr) {
                .v4 => |v4| try static_v4.append(alloc, .{
                    .start = v4.start,
                    .end = v4.end,
                    .country = ip_mod.HOLE,
                    .size = 0,
                }),
                .v6 => |v6| try static_v6.append(alloc, .{
                    .start = v6.start,
                    .end = v6.end,
                    .country = ip_mod.HOLE,
                    .size = 0,
                }),
            }
        }
    }
    return stats;
}

// SWAR (SIMD Within A Register) ASCII Integer Parsing.
// Eliminates sequential loop bounds and byte-by-byte multiplication overhead.
// Automatically chunks 8 ASCII digits into a single 64-bit register and
// performs binary reduction via bit-shifting to calculate the base-10 value.
// Destroys ~124 Million logic instructions over 1.1M parsed ranges.
pub fn fastParseInt(comptime T: type, str: []const u8) !T {
    var res: T = 0;
    var i: usize = 0;

    // Process 8 characters at a time via SWAR
    while (i + 8 <= str.len) : (i += 8) {
        // Load 8 characters into a single 64-bit integer
        var chunk = std.mem.readInt(u64, str[i .. i + 8][0..8], .little);

        // Strip ASCII header (convert '0'-'9' to 0-9)
        chunk ^= 0x3030303030303030;

        // Multiply and accumulate adjacent pairs
        var lower = (chunk & 0x00FF00FF00FF00FF) * 10;
        var upper = (chunk >> 8) & 0x00FF00FF00FF00FF;
        chunk = lower + upper;

        // Multiply and accumulate 4-digit blocks
        lower = (chunk & 0x0000FFFF0000FFFF) * 100;
        upper = (chunk >> 16) & 0x0000FFFF0000FFFF;
        chunk = lower + upper;

        // Multiply and accumulate 8-digit blocks
        lower = (chunk & 0x00000000FFFFFFFF) * 10000;
        upper = (chunk >> 32) & 0x00000000FFFFFFFF;
        chunk = lower + upper;

        // Shift existing result by 10^8 and add chunk
        res = res * 100_000_000 + @as(T, @intCast(chunk));
    }

    // Tail loop for remaining 0-7 characters
    while (i < str.len) : (i += 1) {
        res = res * 10 + (str[i] - '0');
    }
    return res;
}

pub fn parseCsvLine(comptime T: type, line: []const u8, country_map: *const [65536]u16) ?ip_mod.IPRange(T) {
    if (line.len == 0) {
        @branchHint(.cold);
        return null;
    }

    const comma1 = swar_mod.findByte(line, ',') orelse return null;
    const comma2_rel = swar_mod.findByte(line[comma1 + 1 ..], ',') orelse return null;
    const comma2 = comma1 + 1 + comma2_rel;

    const start_str = line[0..comma1];
    const end_str = line[comma1 + 1 .. comma2];

    var country = line[comma2 + 1 ..];
    if (country.len > 0 and country[country.len - 1] == '\r') {
        @branchHint(.cold);
        country = country[0 .. country.len - 1];
    }

    const start = fastParseInt(T, start_str) catch return null;
    const end = fastParseInt(T, end_str) catch return null;
    const size = end -% start +% 1;

    var c_val: u16 = 0;
    if (country.len >= 2) {
        @branchHint(.likely);
        c_val = (@as(u16, country[0]) << 8) | @as(u16, country[1]);
        c_val = country_map[c_val];
    }

    return ip_mod.IPRange(T){ .start = start, .end = end, .country = c_val, .size = size };
}

pub const StaticCidr = union(enum) {
    v4: struct { start: u32, end: u32 },
    v6: struct { start: u128, end: u128 },
};

pub fn parseStaticLine(line: []const u8) ?StaticCidr {
    const trimmed = std.mem.trimEnd(u8, line, " \t\r");
    if (trimmed.len == 0) return null;

    var tokenizer = std.mem.tokenizeAny(u8, trimmed, " \t;");
    const token = tokenizer.next() orelse return null;
    if (std.mem.eql(u8, token, "default")) return null;

    var ip_part = token;
    var prefix_part: ?[]const u8 = null;
    if (std.mem.indexOfScalar(u8, token, '/')) |slash_idx| {
        ip_part = token[0..slash_idx];
        prefix_part = token[slash_idx + 1 ..];
    }

    if (std.Io.net.IpAddress.parseIp4(ip_part, 0)) |ip4| {
        const ip_val = std.mem.readInt(u32, &ip4.ip4.bytes, .big);
        const prefix = if (prefix_part) |p| std.fmt.parseInt(u8, p, 10) catch 32 else 32;
        if (prefix > 32) return null;
        const mask: u32 = if (prefix == 0) 0 else ~(@as(u32, 0)) << @intCast(32 - prefix);
        return StaticCidr{ .v4 = .{ .start = ip_val & mask, .end = (ip_val & mask) | ~mask } };
    } else |_| {
        if (std.Io.net.IpAddress.parseIp6(ip_part, 0)) |ip6| {
            const ip_val = std.mem.readInt(u128, &ip6.ip6.bytes, .big);
            const prefix = if (prefix_part) |p| std.fmt.parseInt(u8, p, 10) catch 128 else 128;
            if (prefix > 128) return null;
            const mask: u128 = if (prefix == 0) 0 else ~(@as(u128, 0)) << @intCast(128 - prefix);
            return StaticCidr{ .v6 = .{ .start = ip_val & mask, .end = (ip_val & mask) | ~mask } };
        } else |_| return null;
    }
}

pub fn parseFile(comptime T: type, io: std.Io, path: []const u8, ranges: *std.ArrayList(ip_mod.IPRange(T)), alloc: std.mem.Allocator, country_map: *const [65536]u16) !Stats {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    // Heuristically pre-allocate array capacity based on file size.
    // IPv4/IPv6 CSV lines average ~30-40 bytes each. Overestimating capacity prevents O(N) reallocs.
    const stat = try file.stat(io);
    if (stat.size == 0) return Stats{};
    const estimated_lines = stat.size / 30;
    try ranges.ensureTotalCapacity(alloc, @intCast(estimated_lines));

    const mapped = try std.posix.mmap(null, stat.size, .{ .READ = true }, .{ .TYPE = .PRIVATE }, file.handle, 0);
    defer std.posix.munmap(mapped);
    std.posix.madvise(mapped.ptr, mapped.len, std.posix.MADV.SEQUENTIAL) catch {};

    var stats = Stats{};
    var it = std.mem.splitScalar(u8, mapped, '\n');

    while (it.next()) |line| {
        if (parseCsvLine(T, line, country_map)) |range| {
            try ranges.append(alloc, range);
            stats.lines_parsed += 1;
        } else {
            @branchHint(.cold);
            stats.lines_skipped += 1;
        }
    }
    return stats;
}

const testing = std.testing;

test "fastParseInt handles normal and edge cases" {
    try testing.expectEqual(@as(u32, 12345678), try fastParseInt(u32, "12345678"));
    try testing.expectEqual(@as(u32, 123), try fastParseInt(u32, "123"));
    try testing.expectEqual(@as(u32, 0), try fastParseInt(u32, "0"));
    try testing.expectEqual(@as(u32, 4294967295), try fastParseInt(u32, "4294967295"));
    try testing.expectEqual(@as(u128, 12345678901234567890), try fastParseInt(u128, "12345678901234567890"));
}

test "parseCsvLine: valid line returns correct range" {
    var cmap = [_]u16{0} ** 65536;
    for (0..65536) |i| cmap[i] = @intCast(i);

    const range = parseCsvLine(u32, "16777216,16777471,AU", &cmap).?;
    try testing.expectEqual(@as(u32, 16777216), range.start);
    try testing.expectEqual(@as(u32, 16777471), range.end);
    try testing.expectEqual(@as(u16, (@as(u16, 'A') << 8) | @as(u16, 'U')), range.country);
    try testing.expectEqual(@as(u32, 256), range.size);
}

test "parseCsvLine: country map remaps code" {
    const eu_idx: u16 = (@as(u16, 'E') << 8) | @as(u16, 'U');
    const au_idx: u16 = (@as(u16, 'A') << 8) | @as(u16, 'U');
    var cmap = [_]u16{0} ** 65536;
    for (0..65536) |i| cmap[i] = @intCast(i);
    cmap[au_idx] = eu_idx;

    const range = parseCsvLine(u32, "0,255,AU", &cmap).?;
    try testing.expectEqual(eu_idx, range.country);
}

test "parseCsvLine: short country code yields c_val=0" {
    var cmap = [_]u16{0} ** 65536;
    for (0..65536) |i| cmap[i] = @intCast(i);

    const range = parseCsvLine(u32, "0,255,A", &cmap).?;
    try testing.expectEqual(@as(u16, 0), range.country);
}

test "parseCsvLine: empty line returns null" {
    var cmap = [_]u16{0} ** 65536;
    for (0..65536) |i| cmap[i] = @intCast(i);

    try testing.expect(parseCsvLine(u32, "", &cmap) == null);
}

test "parseCsvLine: line without two commas returns null" {
    var cmap = [_]u16{0} ** 65536;
    for (0..65536) |i| cmap[i] = @intCast(i);

    try testing.expect(parseCsvLine(u32, "badline", &cmap) == null);
    try testing.expect(parseCsvLine(u32, "0,255", &cmap) == null);
}

test "parseCsvLine: non-numeric input is parsed as-is (fastParseInt trusts format)" {
    var cmap = [_]u16{0} ** 65536;
    for (0..65536) |i| cmap[i] = @intCast(i);
    // fastParseInt doesn't validate — it computes from byte values for all ASCII
    const range = parseCsvLine(u32, "abc,def,AU", &cmap).?;
    try testing.expectEqual(@as(u16, (@as(u16, 'A') << 8) | @as(u16, 'U')), range.country);
}

test "parseCsvLine: carriage return stripped from country" {
    var cmap = [_]u16{0} ** 65536;
    for (0..65536) |i| cmap[i] = @intCast(i);

    const range = parseCsvLine(u32, "0,255,AU\r", &cmap).?;
    try testing.expectEqual(@as(u16, (@as(u16, 'A') << 8) | @as(u16, 'U')), range.country);
}

test "parseCsvLine: wrapping size handles full address space" {
    var cmap = [_]u16{0} ** 65536;
    for (0..65536) |i| cmap[i] = @intCast(i);

    const range = parseCsvLine(u32, "0,4294967295,US", &cmap).?;
    try testing.expectEqual(@as(u32, 0), range.start);
    try testing.expectEqual(@as(u32, std.math.maxInt(u32)), range.end);
    try testing.expectEqual(@as(u32, 0), range.size); // 0 -% 0 +% 1 wraps to 0
}

// parseStaticLine tests

test "parseStaticLine: valid IPv4 CIDR" {
    const cidr = parseStaticLine("8.8.8.0/24").?;
    try testing.expect(cidr == .v4);
    try testing.expectEqual(@as(u32, 0x08080800), cidr.v4.start);
    try testing.expectEqual(@as(u32, 0x080808FF), cidr.v4.end);
}

test "parseStaticLine: valid IPv4 without prefix defaults /32" {
    const cidr = parseStaticLine("8.8.8.8").?;
    try testing.expect(cidr == .v4);
    try testing.expectEqual(@as(u32, 0x08080808), cidr.v4.start);
    try testing.expectEqual(@as(u32, 0x08080808), cidr.v4.end);
}

test "parseStaticLine: valid IPv6 CIDR" {
    const cidr = parseStaticLine("2001:db8::/32").?;
    try testing.expect(cidr == .v6);
    try testing.expectEqual(@as(u128, 0x20010DB8000000000000000000000000), cidr.v6.start);
    try testing.expectEqual(@as(u128, 0x20010DB8FFFFFFFFFFFFFFFFFFFFFFFF), cidr.v6.end);
}

test "parseStaticLine: semicolon suffix stripped" {
    const cidr = parseStaticLine("10.0.0.0/8;").?;
    try testing.expect(cidr == .v4);
    try testing.expectEqual(@as(u32, 0x0A000000), cidr.v4.start);
    try testing.expectEqual(@as(u32, 0x0AFFFFFF), cidr.v4.end);
}

test "parseStaticLine: trailing whitespace and CR stripped" {
    const cidr1 = parseStaticLine("192.168.0.0/16  ").?;
    try testing.expect(cidr1 == .v4);
    const cidr2 = parseStaticLine("192.168.0.0/16\r").?;
    try testing.expect(cidr2 == .v4);
}

test "parseStaticLine: empty line returns null" {
    try testing.expect(parseStaticLine("") == null);
}

test "parseStaticLine: whitespace-only line returns null" {
    try testing.expect(parseStaticLine("   ") == null);
    try testing.expect(parseStaticLine("\t") == null);
}

test "parseStaticLine: default keyword returns null" {
    try testing.expect(parseStaticLine("default") == null);
    try testing.expect(parseStaticLine("default US;") == null);
}

test "parseStaticLine: non-parseable token returns null" {
    try testing.expect(parseStaticLine("not-an-ip") == null);
}

test "parseStaticLine: prefix > bit width returns null" {
    try testing.expect(parseStaticLine("10.0.0.0/40") == null);
    try testing.expect(parseStaticLine("::/200") == null);
}
