const std = @import("std");
const ip_mod = @import("ip.zig");
const flatten_mod = @import("flatten.zig");
const parse = @import("parse.zig");
const cidr_mod = @import("cidr.zig");

pub const StreamResult = struct {
    stats: parse.Stats,
    cidrs: usize,
    countries: usize,
    flattened: usize,
    segments: usize,
    segments_filtered: usize,
    time_io_ns: i128,
    time_flatten_ns: i128,
    time_cidr_ns: i128,
};

pub fn processStream(
    comptime T: type,
    io: std.Io,
    path: []const u8,
    static_ranges: []const ip_mod.IPRange(T),
    seen_countries: *[65536]bool,
    writer: *std.Io.Writer,
    alloc: std.mem.Allocator,
    country_map: *const [65536]u16,
    filter_map: *const [65536]bool,
) !StreamResult {
    const ts_start = std.Io.Timestamp.now(io, .awake).nanoseconds;

    var ranges = std.ArrayList(ip_mod.IPRange(T)).empty;
    defer ranges.deinit(alloc);
    var stats = try parse.csvFile(T, io, path, &ranges, alloc, country_map);
    const ts_parsed = std.Io.Timestamp.now(io, .awake).nanoseconds;
    const time_io_ns = ts_parsed - ts_start;

    for (static_ranges) |r| {
        try ranges.append(alloc, r);
    }

    var segments = std.ArrayList(flatten_mod.Segment(T)).empty;
    defer segments.deinit(alloc);

    const flatten_stats = try flatten_mod.flatten(T, alloc, ranges.items, &segments);
    stats.collisions = flatten_stats.collisions;
    stats.overrides = flatten_stats.overrides;
    const flattened = flatten_stats.flattened;

    const ts_flattened = std.Io.Timestamp.now(io, .awake).nanoseconds;
    const time_flatten_ns = ts_flattened - ts_parsed;

    @memset(seen_countries, false);

    const filter_result = filterSegments(T, &segments, filter_map, seen_countries);

    var cidrs: usize = 0;
    for (segments.items) |seg| {
        const cidr_stats = try cidr_mod.rangeToCidrs(T, writer, seg.start, seg.end, seg.country);
        cidrs += cidr_stats.cidrs;
    }
    const seg_count = segments.items.len;

    const ts_cidr = std.Io.Timestamp.now(io, .awake).nanoseconds;
    const time_cidr_ns = ts_cidr - ts_flattened;

    return StreamResult{
        .stats = stats,
        .cidrs = cidrs,
        .countries = filter_result.countries,
        .flattened = flattened,
        .segments = seg_count,
        .segments_filtered = filter_result.segments_filtered,
        .time_io_ns = time_io_ns,
        .time_flatten_ns = time_flatten_ns,
        .time_cidr_ns = time_cidr_ns,
    };
}

pub const FilterResult = struct {
    segments_filtered: usize,
    countries: usize,
};

pub fn filterSegments(
    comptime T: type,
    segments: *std.ArrayList(flatten_mod.Segment(T)),
    filter_map: *const [65536]bool,
    seen_countries: *[65536]bool,
) FilterResult {
    var segments_filtered: usize = 0;
    var countries: usize = 0;
    var write_idx: usize = 0;
    for (segments.items) |seg| {
        if (!filter_map[seg.country]) {
            segments_filtered += 1;
            continue;
        }
        if (write_idx > 0 and
            segments.items[write_idx - 1].end + 1 == seg.start and
            segments.items[write_idx - 1].country == seg.country)
        {
            segments.items[write_idx - 1].end = seg.end;
        } else {
            segments.items[write_idx] = seg;
            write_idx += 1;
        }
        if (!seen_countries[seg.country]) {
            seen_countries[seg.country] = true;
            countries += 1;
        }
    }
    segments.shrinkRetainingCapacity(write_idx);
    return .{ .segments_filtered = segments_filtered, .countries = countries };
}
