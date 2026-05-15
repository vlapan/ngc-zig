const std = @import("std");
const ip_mod = @import("ip.zig");
const trie_mod = @import("trie.zig");

pub const FlattenStats = struct {
    collisions: usize,
    merges: usize,
    flattened: usize,
};

pub fn flatten(comptime T: type, alloc: std.mem.Allocator, ranges: []const ip_mod.IPRange(T), trie: *trie_mod.IpTrie(T)) !FlattenStats {
    const Event = struct {
        val: T,
        is_end: bool,
        id: u32,
    };

    var stats = FlattenStats{ .collisions = 0, .merges = 0, .flattened = 0 };
    if (ranges.len == 0) return stats;

    var events = try std.ArrayList(Event).initCapacity(alloc, ranges.len * 2);
    defer events.deinit(alloc);

    for (ranges, 0..) |r, i| {
        events.appendAssumeCapacity(.{ .val = r.start, .is_end = false, .id = @intCast(i) });
        if (r.end < std.math.maxInt(T)) {
            events.appendAssumeCapacity(.{ .val = r.end + 1, .is_end = true, .id = @intCast(i) });
        }
    }

    std.mem.sort(Event, events.items, {}, struct {
        fn less(_: void, a: Event, b: Event) bool {
            if (a.val != b.val) return a.val < b.val;
            return @intFromBool(a.is_end) > @intFromBool(b.is_end);
        }
    }.less);

    var active_ids = try std.ArrayList(u32).initCapacity(alloc, 64);
    defer active_ids.deinit(alloc);

    var current_country: ?u16 = null;
    var segment_start: T = 0;

    var i: usize = 0;
    while (i < events.items.len) {
        const current_val = events.items[i].val;

        while (i < events.items.len and events.items[i].val == current_val) {
            const ev = events.items[i];
            i += 1;

            if (ev.is_end) {
                for (active_ids.items, 0..) |id, idx| {
                    if (id == ev.id) {
                        _ = active_ids.swapRemove(idx);
                        break;
                    }
                }
            } else {
                for (active_ids.items) |id| {
                    if (ranges[id].country != ranges[ev.id].country) {
                        stats.collisions += 1;
                        break;
                    }
                }
                try active_ids.append(alloc, ev.id);
            }
        }

        var best_id: ?u32 = null;

        for (active_ids.items) |id| {
            if (best_id == null) {
                best_id = id;
            } else {
                const current_best = ranges[best_id.?];
                const candidate = ranges[id];

                if (candidate.size != current_best.size) {
                    if (candidate.size < current_best.size) best_id = id;
                } else if (candidate.end != current_best.end) {
                    if (candidate.end < current_best.end) best_id = id;
                } else if (candidate.country != current_best.country) {
                    if (candidate.country < current_best.country) best_id = id;
                }
            }
        }

        const new_country = if (best_id) |id| ranges[id].country else null;

        if (new_country != current_country) {
            @branchHint(.likely);
            if (current_country) |c| {
                if (current_val > segment_start) {
                    stats.flattened += 1;
                    _ = try trie.insertRange(1, 0, std.math.maxInt(T), segment_start, current_val - 1, c);
                }
            }
            current_country = new_country;
            segment_start = current_val;
        } else if (current_country != null) {
            @branchHint(.unlikely);
            stats.merges += 1;
        }
    }

    return stats;
}

const testing = std.testing;

test "flatten disjoint ranges" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    var trie = try trie_mod.IpTrie(u32).init(testing.allocator, &aw.writer);
    defer trie.nodes.deinit(testing.allocator);

    var ranges = std.ArrayList(ip_mod.IPv4Range).empty;
    defer ranges.deinit(testing.allocator);

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const ca_idx: u16 = (@as(u16, 'C') << 8) | @as(u16, 'A');

    // 0.0.0.0 - 0.0.0.255 (US)
    try ranges.append(testing.allocator, .{ .start = 0, .end = 255, .country = us_idx, .size = 256 });
    // 0.0.1.0 - 0.0.1.255 (CA)
    try ranges.append(testing.allocator, .{ .start = 256, .end = 511, .country = ca_idx, .size = 256 });

    const stats = try flatten(u32, testing.allocator, ranges.items, &trie);

    try testing.expectEqual(@as(usize, 0), stats.collisions);
    try testing.expectEqual(@as(usize, 0), stats.merges);
    try testing.expectEqual(@as(usize, 2), stats.flattened);

    trie.optimize(1);
    _ = try trie.dump(1, 0, 0);

    const expected = "0.0.0.0/24 US;\n0.0.1.0/24 CA;\n";
    try testing.expectEqualStrings(expected, aw.writer.buffered());
}

test "flatten overlapping ranges smaller overrides larger" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    var trie = try trie_mod.IpTrie(u32).init(testing.allocator, &aw.writer);
    defer trie.nodes.deinit(testing.allocator);

    var ranges = std.ArrayList(ip_mod.IPv4Range).empty;
    defer ranges.deinit(testing.allocator);

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
    const ca_idx: u16 = (@as(u16, 'C') << 8) | @as(u16, 'A');

    // Large background block: 0.0.0.0 - 0.0.1.255 (US)
    try ranges.append(testing.allocator, .{ .start = 0, .end = 511, .country = us_idx, .size = 512 });

    // Small override block: 0.0.0.128 - 0.0.0.255 (CA)
    try ranges.append(testing.allocator, .{ .start = 128, .end = 255, .country = ca_idx, .size = 128 });

    const stats = try flatten(u32, testing.allocator, ranges.items, &trie);

    try testing.expectEqual(@as(usize, 1), stats.collisions);
    try testing.expectEqual(@as(usize, 0), stats.merges);
    try testing.expectEqual(@as(usize, 3), stats.flattened); // [0..127 US], [128..255 CA], [256..511 US]

    trie.optimize(1);
    _ = try trie.dump(1, 0, 0);

    const expected = "0.0.0.0/25 US;\n0.0.0.128/25 CA;\n0.0.1.0/24 US;\n";
    try testing.expectEqualStrings(expected, aw.writer.buffered());
}

test "flatten contiguous sibling merge" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    var trie = try trie_mod.IpTrie(u32).init(testing.allocator, &aw.writer);
    defer trie.nodes.deinit(testing.allocator);

    var ranges = std.ArrayList(ip_mod.IPv4Range).empty;
    defer ranges.deinit(testing.allocator);

    const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');

    // Contiguous blocks with the same country should trigger a merge.
    // 0.0.0.0 - 0.0.0.127 (US)
    try ranges.append(testing.allocator, .{ .start = 0, .end = 127, .country = us_idx, .size = 128 });
    // 0.0.0.128 - 0.0.0.255 (US)
    try ranges.append(testing.allocator, .{ .start = 128, .end = 255, .country = us_idx, .size = 128 });

    const stats = try flatten(u32, testing.allocator, ranges.items, &trie);

    try testing.expectEqual(@as(usize, 0), stats.collisions);
    try testing.expectEqual(@as(usize, 1), stats.merges);
    try testing.expectEqual(@as(usize, 1), stats.flattened); // [0..255 US]

    trie.optimize(1);
    _ = try trie.dump(1, 0, 0);

    const expected = "0.0.0.0/24 US;\n";
    try testing.expectEqualStrings(expected, aw.writer.buffered());
}
