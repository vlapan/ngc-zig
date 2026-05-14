const std = @import("std");
const config_mod = @import("config.zig");
const ip_mod = @import("ip.zig");
const trie_mod = @import("trie.zig");
const flatten_mod = @import("flatten.zig");
const parser_mod = @import("parser.zig");
const build_options = @import("build_options.zig");

pub const std_options: std.Options = .{
    .networking = false,
    .log_level = .err,
    .http_disable_tls = true,
};

pub fn main(init: std.process.Init) void {
    const ts_start = std.Io.Timestamp.now(init.io, .awake).nanoseconds;

    std.debug.print("NGC v{s}-{s} (Zig) ({s})\n", .{
        build_options.version,
        build_options.git_hash,
        build_options.build_iso_date,
    });

    const alloc = init.arena.allocator();

    const config = config_mod.parseArgs(init, alloc) catch |err| {
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

    var static_stats = parser_mod.Stats{};
    var v4_stats = parser_mod.Stats{};
    var v6_stats = parser_mod.Stats{};
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

    var country_map: [65536]u16 = undefined;
    var filter_map: [65536]bool = undefined;

    config_mod.setupMaps(init.io, config, &country_map, &filter_map) catch |err| {
        std.log.err("Failed to setup mappings: {}", .{err});
        std.process.exit(1);
    };

    if (config.static_file) |static_path| {
        const ts_static_start = std.Io.Timestamp.now(init.io, .awake).nanoseconds;
        static_stats = parser_mod.appendStaticFile(init.io, static_path, writer, alloc, &static_v4_ranges, &static_v6_ranges) catch |err| {
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
        v4_stats = parser_mod.parseFile(u32, init.io, v4_path, &ipv4_ranges, alloc, &seen_v4, &country_map, &filter_map) catch |err| {
            if (err == error.FileNotFound) {
                std.log.err("IPv4 CSV file not found: '{s}'", .{v4_path});
            } else {
                std.log.err("Failed to process IPv4 CSV file '{s}': {}", .{ v4_path, err });
            }
            std.process.exit(1);
        };
        const ts_v4_parsed = std.Io.Timestamp.now(init.io, .awake).nanoseconds;
        time_io_ns += ts_v4_parsed - ts_v4_start;

        var trie_v4 = trie_mod.IpTrie(u32).init(alloc, writer) catch |err| {
            std.log.err("Failed to initialize IPv4 Trie: {}", .{err});
            std.process.exit(1);
        };
        trie_v4.nodes.ensureTotalCapacity(alloc, ipv4_ranges.items.len * 4) catch |err| {
            std.log.err("Failed to pre-allocate IPv4 Trie: {}", .{err});
            std.process.exit(1);
        };

        const flatten_stats = flatten_mod.flatten(u32, alloc, ipv4_ranges.items, &trie_v4) catch |err| {
            std.log.err("Failed to flatten IPv4 ranges: {}", .{err});
            std.process.exit(1);
        };
        v4_stats.collisions = flatten_stats.collisions;
        v4_merges = flatten_stats.merges;
        v4_flattened = flatten_stats.flattened;

        const ts_v4_flattened = std.Io.Timestamp.now(init.io, .awake).nanoseconds;
        time_flatten_ns += ts_v4_flattened - ts_v4_parsed;

        for (static_v4_ranges.items) |r| {
            v4_stats.overrides += trie_v4.insertRange(1, 0, std.math.maxInt(u32), r.start, r.end, trie_mod.HOLE) catch |err| {
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
        v6_stats = parser_mod.parseFile(u128, init.io, v6_path, &ipv6_ranges, alloc, &seen_v6, &country_map, &filter_map) catch |err| {
            if (err == error.FileNotFound) {
                std.log.err("IPv6 CSV file not found: '{s}'", .{v6_path});
            } else {
                std.log.err("Failed to process IPv6 CSV file '{s}': {}", .{ v6_path, err });
            }
            std.process.exit(1);
        };
        const ts_v6_parsed = std.Io.Timestamp.now(init.io, .awake).nanoseconds;
        time_io_ns += ts_v6_parsed - ts_v6_start;

        var trie_v6 = trie_mod.IpTrie(u128).init(alloc, writer) catch |err| {
            std.log.err("Failed to initialize IPv6 Trie: {}", .{err});
            std.process.exit(1);
        };
        trie_v6.nodes.ensureTotalCapacity(alloc, ipv6_ranges.items.len * 8) catch |err| {
            std.log.err("Failed to pre-allocate IPv6 Trie: {}", .{err});
            std.process.exit(1);
        };

        const flatten_v6_stats = flatten_mod.flatten(u128, alloc, ipv6_ranges.items, &trie_v6) catch |err| {
            std.log.err("Failed to flatten IPv6 ranges: {}", .{err});
            std.process.exit(1);
        };
        v6_stats.collisions = flatten_v6_stats.collisions;
        v6_merges = flatten_v6_stats.merges;
        v6_flattened = flatten_v6_stats.flattened;

        const ts_v6_flattened = std.Io.Timestamp.now(init.io, .awake).nanoseconds;
        time_flatten_ns += ts_v6_flattened - ts_v6_parsed;

        for (static_v6_ranges.items) |r| {
            v6_stats.overrides += trie_v6.insertRange(1, 0, std.math.maxInt(u128), r.start, r.end, trie_mod.HOLE) catch |err| {
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

    const total_filtered = v4_stats.lines_filtered + v6_stats.lines_filtered;
    const total_skipped = static_stats.lines_skipped + v4_stats.lines_skipped + v6_stats.lines_skipped;
    const total_cidrs = static_stats.lines_parsed + v4_cidrs + v6_cidrs;

    std.debug.print("Done in {} ms.\n", .{elapsed_ms});
    std.debug.print("  Inputs (ranges parsed): IPv4: {}, IPv6: {}, Static: {}, Skipped: {}, Filtered: {}\n", .{
        v4_stats.lines_parsed,
        v6_stats.lines_parsed,
        static_stats.lines_parsed,
        total_skipped,
        total_filtered,
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

    // Heuristic: ~64 bytes per IPv4 CIDR, ~128 bytes per IPv6 CIDR in Nginx's ngx_radix_tree_t
    const est_ram_v4 = v4_cidrs * 64;
    const est_ram_v6 = v6_cidrs * 128;
    const est_ram_mb = (est_ram_v4 + est_ram_v6) / (1024 * 1024);
    std.debug.print("  Estimated Nginx RAM footprint: ~{} MB (heuristic: 64B/v4, 128B/v6 node)\n", .{est_ram_mb});

    std.debug.print("  Pipeline Profiling: I/O & Parsing: {}ms, Phase 1 (Flatten): {}ms, Phase 2 (Radix): {}ms\n", .{
        @divTrunc(time_io_ns, 1_000_000),
        @divTrunc(time_flatten_ns, 1_000_000),
        @divTrunc(time_trie_ns, 1_000_000),
    });
}

test {
    std.testing.refAllDecls(@This());
}
