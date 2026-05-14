const std = @import("std");
const cli = @import("cli.zig");
const ip_mod = @import("ip.zig");
const build_options = @import("build_options.zig");

pub const std_options: std.Options = .{
    .networking = false,
    .log_level = .err,
    .http_disable_tls = true,
};

pub const Stats = struct {
    lines_parsed: usize = 0,
    lines_skipped: usize = 0,
    collisions: usize = 0,
    overrides: usize = 0,
};

pub fn main(init: std.process.Init) void {
    const ts_start = std.Io.Timestamp.now(init.io, .awake).nanoseconds;

    std.debug.print("NGC v{s}-{s} (Zig) ({s})\n", .{
        build_options.version,
        build_options.git_hash,
        build_options.build_iso_date,
    });

    const alloc = init.arena.allocator();

    const config = cli.parseArgs(init, alloc) catch |err| {
        if (err == error.InvalidArgs) {
            std.process.exit(1);
        }
        std.log.err("Failed to parse arguments: {}", .{err});
        std.process.exit(1);
    };

    // Pre-flight checks: ensure all provided input files exist before starting
    if (config.static_file) |p| {
        if (std.Io.Dir.cwd().openFile(init.io, p, .{})) |f| {
            f.close(init.io);
        } else |err| {
            if (err == error.FileNotFound) std.log.err("Static file not found: '{s}'", .{p}) else std.log.err("Cannot access static file '{s}': {}", .{ p, err });
            std.process.exit(1);
        }
    }
    if (config.ipv4_csv) |p| {
        if (std.Io.Dir.cwd().openFile(init.io, p, .{})) |f| {
            f.close(init.io);
        } else |err| {
            if (err == error.FileNotFound) std.log.err("IPv4 CSV file not found: '{s}'", .{p}) else std.log.err("Cannot access IPv4 CSV file '{s}': {}", .{ p, err });
            std.process.exit(1);
        }
    }
    if (config.ipv6_csv) |p| {
        if (std.Io.Dir.cwd().openFile(init.io, p, .{})) |f| {
            f.close(init.io);
        } else |err| {
            if (err == error.FileNotFound) std.log.err("IPv6 CSV file not found: '{s}'", .{p}) else std.log.err("Cannot access IPv6 CSV file '{s}': {}", .{ p, err });
            std.process.exit(1);
        }
    }

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
    var v4_flattened: usize = 0;
    var v6_flattened: usize = 0;
    
    var time_io_ns: i128 = 0;
    var time_flatten_ns: i128 = 0;
    var time_trie_ns: i128 = 0;
    
    var v4_nodes: usize = 0;
    var v6_nodes: usize = 0;
    var v4_merges: usize = 0;
    var v6_merges: usize = 0;

    var seen_v4 = [_]bool{false} ** 65536;
    var seen_v6 = [_]bool{false} ** 65536;
    var static_v4_ranges = std.ArrayList(ip_mod.IPv4Range).empty;
    var static_v6_ranges = std.ArrayList(ip_mod.IPv6Range).empty;

    if (config.static_file) |static_path| {
        const ts_static_start = std.Io.Timestamp.now(init.io, .awake).nanoseconds;
        static_stats = appendStaticFile(init.io, static_path, writer, alloc, &static_v4_ranges, &static_v6_ranges) catch |err| {
            if (err == error.FileNotFound) {
                std.log.err("Static file not found: '{s}'", .{static_path});
            } else {
                std.log.err("Failed to process static file '{s}': {}", .{ static_path, err });
            }
            std.process.exit(1);
        };
        time_io_ns += std.Io.Timestamp.now(init.io, .awake).nanoseconds - ts_static_start;
    }

    if (config.ipv4_csv) |v4_path| {
        const ts_v4_start = std.Io.Timestamp.now(init.io, .awake).nanoseconds;
        var ipv4_ranges = std.ArrayList(ip_mod.IPv4Range).empty;
        v4_stats = parseFile(u32, init.io, v4_path, &ipv4_ranges, alloc, &seen_v4) catch |err| {
            if (err == error.FileNotFound) {
                std.log.err("IPv4 CSV file not found: '{s}'", .{v4_path});
            } else {
                std.log.err("Failed to process IPv4 CSV file '{s}': {}", .{ v4_path, err });
            }
            std.process.exit(1);
        };
        const ts_v4_parsed = std.Io.Timestamp.now(init.io, .awake).nanoseconds;
        time_io_ns += ts_v4_parsed - ts_v4_start;

        var trie_v4 = ip_mod.IpTrie(u32).init(alloc, writer) catch |err| {
            std.log.err("Failed to initialize IPv4 Trie: {}", .{err});
            std.process.exit(1);
        };
        trie_v4.nodes.ensureTotalCapacity(alloc, ipv4_ranges.items.len * 4) catch |err| {
            std.log.err("Failed to pre-allocate IPv4 Trie: {}", .{err});
            std.process.exit(1);
        };

        const flatten_stats = ip_mod.flatten(u32, alloc, ipv4_ranges.items, &trie_v4) catch |err| {
            std.log.err("Failed to flatten IPv4 ranges: {}", .{err});
            std.process.exit(1);
        };
        v4_stats.collisions = flatten_stats.collisions;
        v4_merges = flatten_stats.merges;
        v4_flattened = flatten_stats.flattened;
        
        const ts_v4_flattened = std.Io.Timestamp.now(init.io, .awake).nanoseconds;
        time_flatten_ns += ts_v4_flattened - ts_v4_parsed;

        for (static_v4_ranges.items) |r| {
            v4_stats.overrides += trie_v4.insertRange(1, 0, std.math.maxInt(u32), r.start, r.end, ip_mod.HOLE) catch |err| {
                std.log.err("Failed to insert static IPv4 hole: {}", .{err});
                std.process.exit(1);
            };
        }
        trie_v4.optimize(1);
        v4_cidrs = trie_v4.dump(1, 0, 0) catch |err| {
            std.log.err("Failed to write IPv4 output: {}", .{err});
            std.process.exit(1);
        };
        v4_nodes = trie_v4.nodes.items.len;
        
        const ts_v4_trie = std.Io.Timestamp.now(init.io, .awake).nanoseconds;
        time_trie_ns += ts_v4_trie - ts_v4_flattened;
        
        for (seen_v4) |seen| {
            if (seen) v4_countries += 1;
        }
    }

    if (config.ipv6_csv) |v6_path| {
        const ts_v6_start = std.Io.Timestamp.now(init.io, .awake).nanoseconds;
        var ipv6_ranges = std.ArrayList(ip_mod.IPv6Range).empty;
        v6_stats = parseFile(u128, init.io, v6_path, &ipv6_ranges, alloc, &seen_v6) catch |err| {
            if (err == error.FileNotFound) {
                std.log.err("IPv6 CSV file not found: '{s}'", .{v6_path});
            } else {
                std.log.err("Failed to process IPv6 CSV file '{s}': {}", .{ v6_path, err });
            }
            std.process.exit(1);
        };
        const ts_v6_parsed = std.Io.Timestamp.now(init.io, .awake).nanoseconds;
        time_io_ns += ts_v6_parsed - ts_v6_start;

        var trie_v6 = ip_mod.IpTrie(u128).init(alloc, writer) catch |err| {
            std.log.err("Failed to initialize IPv6 Trie: {}", .{err});
            std.process.exit(1);
        };
        trie_v6.nodes.ensureTotalCapacity(alloc, ipv6_ranges.items.len * 8) catch |err| {
            std.log.err("Failed to pre-allocate IPv6 Trie: {}", .{err});
            std.process.exit(1);
        };

        const flatten_v6_stats = ip_mod.flatten(u128, alloc, ipv6_ranges.items, &trie_v6) catch |err| {
            std.log.err("Failed to flatten IPv6 ranges: {}", .{err});
            std.process.exit(1);
        };
        v6_stats.collisions = flatten_v6_stats.collisions;
        v6_merges = flatten_v6_stats.merges;
        v6_flattened = flatten_v6_stats.flattened;
        
        const ts_v6_flattened = std.Io.Timestamp.now(init.io, .awake).nanoseconds;
        time_flatten_ns += ts_v6_flattened - ts_v6_parsed;

        for (static_v6_ranges.items) |r| {
            v6_stats.overrides += trie_v6.insertRange(1, 0, std.math.maxInt(u128), r.start, r.end, ip_mod.HOLE) catch |err| {
                std.log.err("Failed to insert static IPv6 hole: {}", .{err});
                std.process.exit(1);
            };
        }
        trie_v6.optimize(1);
        v6_cidrs = trie_v6.dump(1, 0, 0) catch |err| {
            std.log.err("Failed to write IPv6 output: {}", .{err});
            std.process.exit(1);
        };
        v6_nodes = trie_v6.nodes.items.len;
        
        const ts_v6_trie = std.Io.Timestamp.now(init.io, .awake).nanoseconds;
        time_trie_ns += ts_v6_trie - ts_v6_flattened;
        
        for (seen_v6) |seen| {
            if (seen) v6_countries += 1;
        }
    }

    out_file_writer.flush() catch |err| {
        std.log.err("Failed to flush output file: {}", .{err});
        std.process.exit(1);
    };

    const ts_end = std.Io.Timestamp.now(init.io, .awake).nanoseconds;
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
    std.debug.print("  Phase 1 (Sweep Line): Topological Collisions: IPv4: {}, IPv6: {}\n", .{
        v4_stats.collisions,
        v6_stats.collisions,
    });
    std.debug.print("  Phase 1 (Sweep Line): Contiguous Merges: IPv4: {}, IPv6: {}\n", .{
        v4_merges,
        v6_merges,
    });
    std.debug.print("  Phase 1 (Sweep Line): Disjoint Segments: IPv4: {}, IPv6: {}\n", .{
        v4_flattened,
        v6_flattened,
    });
    std.debug.print("  Phase 2 (Radix Trie): Nodes Allocated: IPv4: {}, IPv6: {}\n", .{
        v4_nodes,
        v6_nodes,
    });
    std.debug.print("  Phase 2 (Radix Trie): Static Overrides: IPv4: {}, IPv6: {}\n", .{
        v4_stats.overrides,
        v6_stats.overrides,
    });
    std.debug.print("  Phase 2 (Radix Trie): Unique countries mapped: IPv4: {}, IPv6: {}\n", .{
        v4_countries,
        v6_countries,
    });
    std.debug.print("  Outputs (CIDR networks generated): IPv4: {}, IPv6: {}, Static: {}, Total: {}\n", .{
        v4_cidrs,
        v6_cidrs,
        static_stats.lines_parsed,
        total_cidrs,
    });
    std.debug.print("  Pipeline Profiling: I/O & Parsing: {}ms, Phase 1 (Flatten): {}ms, Phase 2 (Radix): {}ms\n", .{
        @divTrunc(time_io_ns, 1_000_000),
        @divTrunc(time_flatten_ns, 1_000_000),
        @divTrunc(time_trie_ns, 1_000_000),
    });
}

fn appendStaticFile(io: std.Io, path: []const u8, writer: *std.Io.Writer, alloc: std.mem.Allocator, static_v4: *std.ArrayList(ip_mod.IPv4Range), static_v6: *std.ArrayList(ip_mod.IPv6Range)) !Stats {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const stat = try file.stat(io);
    if (stat.size == 0) return Stats{};
    const mapped = try std.posix.mmap(null, stat.size, .{ .READ = true }, .{ .TYPE = .PRIVATE }, file.handle, 0);
    defer std.posix.munmap(mapped);
    std.posix.madvise(mapped.ptr, mapped.len, std.posix.MADV.SEQUENTIAL) catch {};
    std.posix.madvise(mapped.ptr, mapped.len, std.posix.MADV.SEQUENTIAL) catch {};

    var stats = Stats{};
    var it = std.mem.splitScalar(u8, mapped, '\n');

    while (it.next()) |line| {
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

        var tokenizer = std.mem.tokenizeAny(u8, final_line, " \t;");
        if (tokenizer.next()) |token| {
            if (std.mem.eql(u8, token, "default")) continue;

            var ip_part = token;
            var prefix_part: ?[]const u8 = null;
            if (std.mem.indexOfScalar(u8, token, '/')) |slash_idx| {
                ip_part = token[0..slash_idx];
                prefix_part = token[slash_idx + 1 ..];
            }

            if (std.Io.net.IpAddress.parseIp4(ip_part, 0)) |ip4| {
                const ip_val = std.mem.readInt(u32, &ip4.ip4.bytes, .big);
                const prefix = if (prefix_part) |p| std.fmt.parseInt(u8, p, 10) catch 32 else 32;
                if (prefix <= 32) {
                    const mask: u32 = if (prefix == 0) 0 else ~(@as(u32, 0)) << @intCast(32 - prefix);
                    try static_v4.append(alloc, .{
                        .start = ip_val & mask,
                        .end = (ip_val & mask) | ~mask,
                        .country = ip_mod.HOLE,
                        .size = 0,
                    });
                }
            } else |_| {
                if (std.Io.net.IpAddress.parseIp6(ip_part, 0)) |ip6| {
                    const ip_val = std.mem.readInt(u128, &ip6.ip6.bytes, .big);
                    const prefix = if (prefix_part) |p| std.fmt.parseInt(u8, p, 10) catch 128 else 128;
                    if (prefix <= 128) {
                        const mask: u128 = if (prefix == 0) 0 else ~(@as(u128, 0)) << @intCast(128 - prefix);
                        try static_v6.append(alloc, .{
                            .start = ip_val & mask,
                            .end = (ip_val & mask) | ~mask,
                            .country = ip_mod.HOLE,
                            .size = 0,
                        });
                    }
                } else |_| {}
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
fn fastParseInt(comptime T: type, str: []const u8) !T {
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

fn parseFile(comptime T: type, io: std.Io, path: []const u8, ranges: *std.ArrayList(ip_mod.IPRange(T)), alloc: std.mem.Allocator, seen_countries: *[65536]bool) !Stats {
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
    std.posix.madvise(mapped.ptr, mapped.len, std.posix.MADV.SEQUENTIAL) catch {};

    var stats = Stats{};
    var it = std.mem.splitScalar(u8, mapped, '\n');

    while (it.next()) |line| {
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

        const start = fastParseInt(T, start_str) catch {
            stats.lines_skipped += 1;
            continue;
        };
        const end = fastParseInt(T, end_str) catch {
            stats.lines_skipped += 1;
            continue;
        };
        const size = end -% start +% 1;

        var c_val: u16 = 0;
        if (country.len >= 2) {
            c_val = (@as(u16, country[0]) << 8) | @as(u16, country[1]);
            seen_countries[c_val] = true;
        }
        try ranges.append(alloc, .{
            .start = start,
            .end = end,
            .country = c_val,
            .size = size,
        });
        stats.lines_parsed += 1;
    }
    return stats;
}

test {
    std.testing.refAllDecls(@This());
}
