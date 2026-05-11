const std = @import("std");
const cli = @import("cli.zig");
const ip_mod = @import("ip.zig");
const build_options = @import("options");

pub const Stats = struct {
    lines_parsed: usize = 0,
    lines_skipped: usize = 0,
};

pub fn main(init: std.process.Init) void {
    const ts_start = std.Io.Timestamp.now(init.io, .real).nanoseconds;

    std.debug.print("NGC v{s}-{s} (Zig) ({s})\n", .{
        build_options.version,
        build_options.git_hash,
        build_options.build_iso_date,
    });

    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    const config = cli.parseArgs(init, alloc) catch |err| {
        if (err == error.InvalidArgs) {
            std.process.exit(1);
        }
        std.log.err("Failed to parse arguments: {}", .{err});
        std.process.exit(1);
    };

    const out_file = std.Io.Dir.cwd().createFile(init.io, config.output, .{}) catch |err| {
        std.log.err("Failed to create output file '{s}': {}", .{ config.output, err });
        std.process.exit(1);
    };
    defer out_file.close(init.io);

    var out_buf: [65536]u8 = undefined;
    var out_file_writer = out_file.writer(init.io, &out_buf);
    const writer = &out_file_writer.interface;

    var static_stats = Stats{};
    var v4_stats = Stats{};
    var v6_stats = Stats{};
    var v4_cidrs: usize = 0;
    var v6_cidrs: usize = 0;
    var v4_countries: usize = 0;
    var v6_countries: usize = 0;

    if (config.static_file) |static_path| {
        static_stats = appendStaticFile(init.io, static_path, writer) catch |err| {
            if (err == error.FileNotFound) {
                std.log.err("Static file not found: '{s}'", .{static_path});
            } else {
                std.log.err("Failed to process static file '{s}': {}", .{ static_path, err });
            }
            std.process.exit(1);
        };
    }

    if (config.ipv4_csv) |v4_path| {
        var ipv4_ranges = std.ArrayList(ip_mod.IPv4Range).empty;
        v4_stats = parseFile(u32, init.io, v4_path, &ipv4_ranges, alloc) catch |err| {
            if (err == error.FileNotFound) {
                std.log.err("IPv4 CSV file not found: '{s}'", .{v4_path});
            } else {
                std.log.err("Failed to process IPv4 CSV file '{s}': {}", .{ v4_path, err });
            }
            std.process.exit(1);
        };
        ip_mod.sortRangesBySizeDesc(u32, ipv4_ranges.items);

        var trie_v4 = ip_mod.IpTrie(u32).init(alloc, writer) catch |err| {
            std.log.err("Failed to initialize IPv4 Trie: {}", .{err});
            std.process.exit(1);
        };
        for (ipv4_ranges.items) |r| {
            const c_idx = trie_v4.getCountryIdx(r.country) catch |err| {
                std.log.err("Failed to map country '{s}': {}", .{ r.country, err });
                std.process.exit(1);
            };
            trie_v4.insertRange(1, 0, std.math.maxInt(u32), r.start, r.end, c_idx) catch |err| {
                std.log.err("Failed to insert IPv4 range: {}", .{err});
                std.process.exit(1);
            };
        }
        trie_v4.optimize(1);
        v4_cidrs = trie_v4.dump(1, 0, 0) catch |err| {
            std.log.err("Failed to write IPv4 output: {}", .{err});
            std.process.exit(1);
        };
        v4_countries = trie_v4.countries.items.len - 1;
    }

    if (config.ipv6_csv) |v6_path| {
        var ipv6_ranges = std.ArrayList(ip_mod.IPv6Range).empty;
        v6_stats = parseFile(u128, init.io, v6_path, &ipv6_ranges, alloc) catch |err| {
            if (err == error.FileNotFound) {
                std.log.err("IPv6 CSV file not found: '{s}'", .{v6_path});
            } else {
                std.log.err("Failed to process IPv6 CSV file '{s}': {}", .{ v6_path, err });
            }
            std.process.exit(1);
        };
        ip_mod.sortRangesBySizeDesc(u128, ipv6_ranges.items);

        var trie_v6 = ip_mod.IpTrie(u128).init(alloc, writer) catch |err| {
            std.log.err("Failed to initialize IPv6 Trie: {}", .{err});
            std.process.exit(1);
        };
        for (ipv6_ranges.items) |r| {
            const c_idx = trie_v6.getCountryIdx(r.country) catch |err| {
                std.log.err("Failed to map country '{s}': {}", .{ r.country, err });
                std.process.exit(1);
            };
            trie_v6.insertRange(1, 0, std.math.maxInt(u128), r.start, r.end, c_idx) catch |err| {
                std.log.err("Failed to insert IPv6 range: {}", .{err});
                std.process.exit(1);
            };
        }
        trie_v6.optimize(1);
        v6_cidrs = trie_v6.dump(1, 0, 0) catch |err| {
            std.log.err("Failed to write IPv6 output: {}", .{err});
            std.process.exit(1);
        };
        v6_countries = trie_v6.countries.items.len - 1;
    }

    out_file_writer.flush() catch |err| {
        std.log.err("Failed to flush output file: {}", .{err});
        std.process.exit(1);
    };

    const ts_end = std.Io.Timestamp.now(init.io, .real).nanoseconds;
    const elapsed_ms = @divTrunc(ts_end - ts_start, 1_000_000);

    const total_skipped = static_stats.lines_skipped + v4_stats.lines_skipped + v6_stats.lines_skipped;
    const total_cidrs = static_stats.lines_parsed + v4_cidrs + v6_cidrs;

    std.debug.print("Done in {} ms.\n", .{elapsed_ms});
    std.debug.print("  Inputs (ranges parsed): IPv4: {}, IPv6: {}, Static: {}, Skipped: {}\n", .{
        v4_stats.lines_parsed,
        v6_stats.lines_parsed,
        static_stats.lines_parsed,
        total_skipped,
    });
    std.debug.print("  Unique countries mapped: IPv4: {}, IPv6: {}\n", .{
        v4_countries,
        v6_countries,
    });
    std.debug.print("  Outputs (networks generated): IPv4: {}, IPv6: {}, Static: {}, Total: {}\n", .{
        v4_cidrs,
        v6_cidrs,
        static_stats.lines_parsed,
        total_cidrs,
    });
}

fn appendStaticFile(io: std.Io, path: []const u8, writer: *std.Io.Writer) !Stats {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var in_buf: [65536]u8 = undefined;
    var file_reader = file.reader(io, &in_buf);
    const reader = &file_reader.interface;

    var stats = Stats{};

    while (try reader.takeDelimiter('\n')) |line| {
        if (line.len == 0) {
            stats.lines_skipped += 1;
            continue;
        }
        var final_line = line;
        if (final_line[final_line.len - 1] == '\r') {
            final_line = final_line[0 .. final_line.len - 1];
        }
        if (final_line.len == 0) {
            stats.lines_skipped += 1;
            continue;
        }
        try writer.writeAll(final_line);
        try writer.writeAll("\n");
        stats.lines_parsed += 1;
    }
    return stats;
}

fn parseFile(comptime T: type, io: std.Io, path: []const u8, ranges: *std.ArrayList(ip_mod.IPRange(T)), alloc: std.mem.Allocator) !Stats {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var in_buf: [65536]u8 = undefined;
    var file_reader = file.reader(io, &in_buf);
    const reader = &file_reader.interface;

    var stats = Stats{};

    while (try reader.takeDelimiter('\n')) |line| {
        if (line.len == 0) {
            stats.lines_skipped += 1;
            continue;
        }

        const comma1 = std.mem.indexOfScalar(u8, line, ',') orelse {
            stats.lines_skipped += 1;
            continue;
        };
        const comma2 = std.mem.indexOfScalarPos(u8, line, comma1 + 1, ',') orelse {
            stats.lines_skipped += 1;
            continue;
        };

        const start_str = line[0..comma1];
        const end_str = line[comma1 + 1 .. comma2];

        var country = line[comma2 + 1 ..];
        if (country.len > 0 and country[country.len - 1] == '\r') {
            country = country[0 .. country.len - 1];
        }

        const start = std.fmt.parseInt(T, start_str, 10) catch {
            stats.lines_skipped += 1;
            continue;
        };
        const end = std.fmt.parseInt(T, end_str, 10) catch {
            stats.lines_skipped += 1;
            continue;
        };
        const size = end -% start +% 1;

        try ranges.append(alloc, .{
            .start = start,
            .end = end,
            .country = try alloc.dupe(u8, country),
            .size = size,
        });
        stats.lines_parsed += 1;
    }
    return stats;
}

test {
    std.testing.refAllDecls(@This());
}
