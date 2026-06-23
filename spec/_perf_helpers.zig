const std = @import("std");

const timespec = extern struct { tv_sec: i64, tv_nsec: i64 };

const clock_gettime: *const fn (clock_id: c_int, tp: *timespec) callconv(.c) c_int = @extern(*const fn (clock_id: c_int, tp: *timespec) callconv(.c) c_int, .{ .name = "clock_gettime" });

const CLOCK_MONOTONIC: c_int = 6;

pub fn now() u64 {
    var ts: timespec = undefined;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) @panic("clock_gettime failed");
    return @as(u64, @intCast(ts.tv_sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.tv_nsec));
}

pub const cache_line = std.atomic.cache_line;
