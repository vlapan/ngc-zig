const std = @import("std");
const ip_mod = @import("ip.zig");

pub const FlattenStats = struct {
    collisions: usize,
    flattened: usize,
    overrides: usize,
};

pub fn Segment(comptime T: type) type {
    return struct {
        start: T,
        end: T,
        country: u16,
    };
}

pub fn flatten(comptime T: type, alloc: std.mem.Allocator, ranges: []const ip_mod.IPRange(T), segments: *std.ArrayList(Segment(T))) !FlattenStats {
    const Event = struct {
        val: T,
        is_end: bool,
        id: u32,
    };

    var stats = FlattenStats{ .collisions = 0, .flattened = 0, .overrides = 0 };
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
                    if (c == ip_mod.HOLE) stats.overrides += 1;
                    try segments.append(alloc, .{ .start = segment_start, .end = current_val - 1, .country = c });
                }
            }
            current_country = new_country;
            segment_start = current_val;
        }
    }

    return stats;
}
