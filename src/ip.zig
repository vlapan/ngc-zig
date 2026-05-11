const std = @import("std");

pub fn IPRange(comptime T: type) type {
    return struct { start: T, end: T, country: []const u8, size: T };
}

pub const IPv4Range = IPRange(u32);
pub const IPv6Range = IPRange(u128);

pub fn sortRanges(comptime T: type, ranges: []IPRange(T)) void {
    std.mem.sort(IPRange(T), ranges, {}, struct {
        fn less(_: void, a: IPRange(T), b: IPRange(T)) bool {
            if (a.end != b.end) return a.end < b.end;
            if (a.size != b.size) return a.size < b.size;
            return std.mem.order(u8, a.country, b.country) == .lt;
        }
    }.less);
}

pub fn sortRangesBySizeDesc(comptime T: type, ranges: []IPRange(T)) void {
    std.mem.sort(IPRange(T), ranges, {}, struct {
        fn less(_: void, a: IPRange(T), b: IPRange(T)) bool {
            // Largest size first
            if (a.size != b.size) return a.size > b.size;
            if (a.end != b.end) return a.end > b.end;
            return std.mem.order(u8, a.country, b.country) == .gt;
        }
    }.less);
}

pub fn isPrivateIPv4(ip: u32) bool {
    return (ip & 0xFF000000) == 0x7F000000 or // 127.0.0.0/8
        (ip & 0xFFFF0000) == 0xA9FE0000 or // 169.254.0.0/16
        (ip & 0xFF000000) == 0x0A000000 or // 10.0.0.0/8
        (ip & 0xFFF00000) == 0xAC100000 or // 172.16.0.0/12
        (ip & 0xFFFF0000) == 0xC0A80000; // 192.168.0.0/16
}

pub fn formatIPv4(writer: anytype, ip: u32, prefix: u8, country: []const u8) !void {
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

    try writer.writeAll(buf[0..idx]);
    try writer.writeAll(country);
    try writer.writeAll(";\n");
}

fn formatU8Int(buf: []u8, val: u8) usize {
    var v = val;
    var idx: usize = 0;
    if (v >= 100) {
        buf[idx] = '0' + (v / 100);
        idx += 1;
        v %= 100;
        buf[idx] = '0' + (v / 10);
        idx += 1;
        buf[idx] = '0' + (v % 10);
        idx += 1;
    } else if (v >= 10) {
        buf[idx] = '0' + (v / 10);
        idx += 1;
        buf[idx] = '0' + (v % 10);
        idx += 1;
    } else {
        buf[idx] = '0' + v;
        idx += 1;
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
            buf[idx] = '0';
            idx += 1;
        } else {
            var started = false;
            inline for (0..4) |nibble| {
                const n_shift: u4 = @intCast((3 - nibble) * 4);
                const nib: u8 = @intCast((chunk >> n_shift) & 0xF);
                if (nib != 0 or started) {
                    buf[idx] = HEX_CHARS[nib];
                    idx += 1;
                    started = true;
                }
            }
        }

        if (i < 7) {
            buf[idx] = ':';
            idx += 1;
        }
    }

    buf[idx] = '/';
    idx += 1;
    idx += formatU8Int(buf[idx..], prefix);
    buf[idx] = ' ';
    idx += 1;

    try writer.writeAll(buf[0..idx]);
    try writer.writeAll(country);
    try writer.writeAll(";\n");
}

pub const TrieNode = struct {
    left: u32 = 0,
    right: u32 = 0,
    country_idx: u32 = 0,
};

pub const HOLE: u32 = std.math.maxInt(u32);
pub const MIXED: u32 = 0;

pub fn IpTrie(comptime T: type) type {
    return struct {
        nodes: std.ArrayListUnmanaged(TrieNode),
        countries: std.ArrayListUnmanaged([]const u8),
        alloc: std.mem.Allocator,
        writer: *std.Io.Writer,

        pub fn init(allocator: std.mem.Allocator, writer: *std.Io.Writer) !IpTrie(T) {
            var self = IpTrie(T){
                .nodes = std.ArrayListUnmanaged(TrieNode).empty,
                .countries = std.ArrayListUnmanaged([]const u8).empty,
                .alloc = allocator,
                .writer = writer,
            };
            // Pre-allocate to prevent early reallocs
            try self.nodes.ensureTotalCapacity(allocator, 1_000_000);
            try self.nodes.append(allocator, .{}); // 0 (null node)
            try self.nodes.append(allocator, .{}); // 1 (root node)
            try self.countries.append(allocator, ""); // 0 is MIXED
            return self;
        }

        pub fn getCountryIdx(self: *IpTrie(T), country: []const u8) !u32 {
            for (self.countries.items, 0..) |c, i| {
                if (std.mem.eql(u8, c, country)) return @intCast(i);
            }
            const new_idx = self.countries.items.len;
            try self.countries.append(self.alloc, try self.alloc.dupe(u8, country));
            return @intCast(new_idx);
        }

        fn allocNode(self: *IpTrie(T)) !u32 {
            const idx = self.nodes.items.len;
            try self.nodes.append(self.alloc, .{});
            return @intCast(idx);
        }

        pub fn insertRange(self: *IpTrie(T), node_idx: u32, node_start: T, node_end: T, rs: T, re: T, country_idx: u32) !void {
            if (rs <= node_start and re >= node_end) {
                self.nodes.items[node_idx].country_idx = country_idx;
                self.nodes.items[node_idx].left = 0;
                self.nodes.items[node_idx].right = 0;
                return;
            }

            const c = self.nodes.items[node_idx].country_idx;
            if (c != MIXED) {
                var left_idx = self.nodes.items[node_idx].left;
                if (left_idx == 0) {
                    left_idx = try self.allocNode();
                    self.nodes.items[node_idx].left = left_idx;
                }
                var right_idx = self.nodes.items[node_idx].right;
                if (right_idx == 0) {
                    right_idx = try self.allocNode();
                    self.nodes.items[node_idx].right = right_idx;
                }
                self.nodes.items[left_idx].country_idx = c;
                self.nodes.items[right_idx].country_idx = c;
                self.nodes.items[node_idx].country_idx = MIXED;
            }

            var left_idx = self.nodes.items[node_idx].left;
            if (left_idx == 0) {
                left_idx = try self.allocNode();
                self.nodes.items[node_idx].left = left_idx;
            }
            var right_idx = self.nodes.items[node_idx].right;
            if (right_idx == 0) {
                right_idx = try self.allocNode();
                self.nodes.items[node_idx].right = right_idx;
            }

            const mid = node_start + (node_end - node_start) / 2;

            if (rs <= mid) {
                try self.insertRange(left_idx, node_start, mid, rs, re, country_idx);
            }
            if (re > mid) {
                try self.insertRange(right_idx, mid + 1, node_end, rs, re, country_idx);
            }
        }

        fn getCountry(self: *IpTrie(T), idx: u32) u32 {
            if (idx == 0) return HOLE;
            return self.nodes.items[idx].country_idx;
        }

        pub fn optimize(self: *IpTrie(T), node_idx: u32) void {
            if (node_idx == 0) return;

            const c = self.nodes.items[node_idx].country_idx;
            if (c != MIXED) return;

            const left_idx = self.nodes.items[node_idx].left;
            const right_idx = self.nodes.items[node_idx].right;

            if (left_idx != 0) self.optimize(left_idx);
            if (right_idx != 0) self.optimize(right_idx);

            const lc = self.getCountry(left_idx);
            const rc = self.getCountry(right_idx);

            if (lc != MIXED and lc == rc) {
                self.nodes.items[node_idx].country_idx = lc;
                self.nodes.items[node_idx].left = 0;
                self.nodes.items[node_idx].right = 0;
            }
        }

        pub fn dump(self: *IpTrie(T), node_idx: u32, ip: T, depth: u8) !usize {
            if (node_idx == 0) return 0;

            const c = self.nodes.items[node_idx].country_idx;
            if (c != MIXED) {
                if (c != HOLE) {
                    if (T == u32) {
                        if (!isPrivateIPv4(@intCast(ip))) {
                            try formatIPv4(self.writer, @intCast(ip), depth, self.countries.items[c]);
                            return 1;
                        }
                    } else {
                        try formatIPv6(self.writer, @intCast(ip), depth, self.countries.items[c]);
                        return 1;
                    }
                }
                return 0;
            }

            var count: usize = 0;
            const left_idx = self.nodes.items[node_idx].left;
            if (left_idx != 0) {
                count += try self.dump(left_idx, ip, depth + 1);
            }

            const right_idx = self.nodes.items[node_idx].right;
            if (right_idx != 0) {
                const shift: u8 = @as(u8, @intCast(@bitSizeOf(T))) - 1 - depth;
                const right_ip = ip | (@as(T, 1) << @intCast(shift));
                count += try self.dump(right_idx, right_ip, depth + 1);
            }
            return count;
        }
    };
}

const testing = std.testing;

test "IPv4 Trie formatting and basic insertion" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    var trie = try IpTrie(u32).init(testing.allocator, &aw.writer);
    defer {
        trie.nodes.deinit(testing.allocator);
        for (trie.countries.items) |c| testing.allocator.free(c);
        trie.countries.deinit(testing.allocator);
    }

    const us_idx = try trie.getCountryIdx("US");
    const ca_idx = try trie.getCountryIdx("CA");

    // Insert 0.0.0.0/0 -> US
    try trie.insertRange(1, 0, std.math.maxInt(u32), 0, std.math.maxInt(u32), us_idx);

    // Insert 128.0.0.0/1 -> CA (size: 2^31)
    const mid = std.math.maxInt(u32) / 2;
    try trie.insertRange(1, 0, std.math.maxInt(u32), mid + 1, std.math.maxInt(u32), ca_idx);

    trie.optimize(1);
    _ = try trie.dump(1, 0, 0);

    const expected = "0.0.0.0/1 US;\n128.0.0.0/1 CA;\n";
    try testing.expectEqualStrings(expected, aw.writer.buffered());
}

test "IPv4 Trie optimization of siblings" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    var trie = try IpTrie(u32).init(testing.allocator, &aw.writer);
    defer {
        trie.nodes.deinit(testing.allocator);
        for (trie.countries.items) |c| testing.allocator.free(c);
        trie.countries.deinit(testing.allocator);
    }

    const fr_idx = try trie.getCountryIdx("FR");

    // Insert two halves of 0.0.0.0/0 explicitly
    const mid = std.math.maxInt(u32) / 2;
    try trie.insertRange(1, 0, std.math.maxInt(u32), 0, mid, fr_idx);
    try trie.insertRange(1, 0, std.math.maxInt(u32), mid + 1, std.math.maxInt(u32), fr_idx);

    trie.optimize(1);
    _ = try trie.dump(1, 0, 0);

    // They should merge perfectly into 0.0.0.0/0
    const expected = "0.0.0.0/0 FR;\n";
    try testing.expectEqualStrings(expected, aw.writer.buffered());
}
