const std = @import("std");
const ip_mod = @import("ip.zig");

pub const TrieNode = packed struct {
    left: u24 = 0,
    right: u24 = 0,
    country: u16 = 0,
};

pub const HOLE: u16 = 0xFFFF;
pub const MIXED: u16 = 0;

pub fn IpTrie(comptime T: type) type {
    return struct {
        nodes: std.ArrayListUnmanaged(TrieNode),
        alloc: std.mem.Allocator,
        writer: *std.Io.Writer,

        pub fn init(allocator: std.mem.Allocator, writer: *std.Io.Writer) !IpTrie(T) {
            var self = IpTrie(T){
                .nodes = std.ArrayListUnmanaged(TrieNode).empty,
                .alloc = allocator,
                .writer = writer,
            };
            // Pre-allocate to prevent early reallocs
            try self.nodes.ensureTotalCapacity(allocator, 1_000_000);
            try self.nodes.append(allocator, .{}); // 0 (null node)
            try self.nodes.append(allocator, .{}); // 1 (root node)
            return self;
        }

        fn allocNode(self: *IpTrie(T)) !u24 {
            const idx = self.nodes.items.len;
            if (idx == self.nodes.capacity) {
                try self.nodes.ensureUnusedCapacity(self.alloc, 4096);
            }
            self.nodes.appendAssumeCapacity(.{});
            return @intCast(idx);
        }

        pub fn insertRange(self: *IpTrie(T), node_idx: u24, node_start: T, node_end: T, rs: T, re: T, country: u16) !usize {
            var overrides: usize = 0;

            const StackFrame = struct {
                idx: u24,
                start: T,
                end: T,
            };

            var stack: [128]StackFrame = undefined;
            var sp: usize = 1;

            stack[0] = .{ .idx = node_idx, .start = node_start, .end = node_end };

            while (sp > 0) {
                sp -= 1;
                const frame = stack[sp];

                var cur_idx = frame.idx;
                var cur_start = frame.start;
                var cur_end = frame.end;

                while (true) {
                    if (rs <= cur_start and re >= cur_end) {
                        const old_c = self.nodes.items[cur_idx].country;
                        if (old_c != MIXED and old_c != country) {
                            overrides += 1;
                        }
                        self.nodes.items[cur_idx].country = country;
                        self.nodes.items[cur_idx].left = 0;
                        self.nodes.items[cur_idx].right = 0;
                        break;
                    }

                    var left_idx = self.nodes.items[cur_idx].left;
                    if (left_idx == 0) {
                        left_idx = try self.allocNode();
                        self.nodes.items[cur_idx].left = left_idx;
                    }
                    var right_idx = self.nodes.items[cur_idx].right;
                    if (right_idx == 0) {
                        right_idx = try self.allocNode();
                        self.nodes.items[cur_idx].right = right_idx;
                    }

                    const c = self.nodes.items[cur_idx].country;
                    if (c != MIXED) {
                        self.nodes.items[left_idx].country = c;
                        self.nodes.items[right_idx].country = c;
                        self.nodes.items[cur_idx].country = MIXED;
                    }

                    const mid = cur_start + (cur_end - cur_start) / 2;

                    const go_left = rs <= mid;
                    const go_right = re > mid;

                    if (go_left and go_right) {
                        @branchHint(.unlikely);
                        std.debug.assert(sp < stack.len - 1);
                        stack[sp] = .{ .idx = right_idx, .start = mid + 1, .end = cur_end };
                        sp += 1;
                        cur_idx = left_idx;
                        cur_end = mid;
                        continue;
                    } else if (go_left) {
                        cur_idx = left_idx;
                        cur_end = mid;
                    } else {
                        cur_idx = right_idx;
                        cur_start = mid + 1;
                    }
                }
            }

            return overrides;
        }

        inline fn getCountry(self: *IpTrie(T), idx: u24) u16 {
            if (idx == 0) return HOLE;
            return self.nodes.items[idx].country;
        }

        pub fn optimize(self: *IpTrie(T), node_idx: u24) void {
            if (node_idx == 0) return;

            const c = self.nodes.items[node_idx].country;
            if (c != MIXED) {
                @branchHint(.likely);
                return;
            }

            const left_idx = self.nodes.items[node_idx].left;
            const right_idx = self.nodes.items[node_idx].right;

            if (left_idx != 0) self.optimize(left_idx);
            if (right_idx != 0) self.optimize(right_idx);

            const lc = self.getCountry(left_idx);
            const rc = self.getCountry(right_idx);

            if (lc != MIXED and lc == rc) {
                self.nodes.items[node_idx].country = lc;
                self.nodes.items[node_idx].left = 0;
                self.nodes.items[node_idx].right = 0;
            }
        }

        pub fn dump(self: *IpTrie(T), node_idx: u24, ip: T, depth: u8) !usize {
            if (node_idx == 0) return 0;

            const c = self.nodes.items[node_idx].country;
            if (c != MIXED) {
                @branchHint(.likely);
                if (c != HOLE) {
                    if (T == u32) {
                        if (!ip_mod.isPrivateIPv4(@intCast(ip))) {
                            @branchHint(.likely);
                            try ip_mod.formatIPv4(self.writer, @intCast(ip), depth, c);
                            return 1;
                        }
                    } else {
                        try ip_mod.formatIPv6(self.writer, @intCast(ip), depth, c);
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
    defer trie.nodes.deinit(testing.allocator);

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const ca_idx: u16 = (@as(u16, 'C') << 8) | @as(u16, 'A');

    // Insert 0.0.0.0/0 -> US
    _ = try trie.insertRange(1, 0, std.math.maxInt(u32), 0, std.math.maxInt(u32), us_idx);

    // Insert 128.0.0.0/1 -> CA (size: 2^31)
    const mid = std.math.maxInt(u32) / 2;
    _ = try trie.insertRange(1, 0, std.math.maxInt(u32), mid + 1, std.math.maxInt(u32), ca_idx);

    trie.optimize(1);
    _ = try trie.dump(1, 0, 0);

    const expected = "0.0.0.0/1 US;\n128.0.0.0/1 CA;\n";
    try testing.expectEqualStrings(expected, aw.writer.buffered());
}

test "IPv4 Trie optimization of siblings" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    var trie = try IpTrie(u32).init(testing.allocator, &aw.writer);
    defer trie.nodes.deinit(testing.allocator);

    const fr_idx: u16 = (@as(u16, 'F') << 8) | @as(u16, 'R');

    // Insert two halves of 0.0.0.0/0 explicitly
    const mid = std.math.maxInt(u32) / 2;
    _ = try trie.insertRange(1, 0, std.math.maxInt(u32), 0, mid, fr_idx);
    _ = try trie.insertRange(1, 0, std.math.maxInt(u32), mid + 1, std.math.maxInt(u32), fr_idx);

    trie.optimize(1);
    _ = try trie.dump(1, 0, 0);

    const expected = "0.0.0.0/0 FR;\n";
    try testing.expectEqualStrings(expected, aw.writer.buffered());
}
