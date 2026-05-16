const std = @import("std");
const config_mod = @import("config.zig");
const ip_mod = @import("ip.zig");
const parser_mod = @import("parser.zig");
const pipeline_mod = @import("pipeline.zig");
const nginx_mod = @import("nginx.zig");
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
        switch (err) {
            error.HelpRequested, error.VersionRequested => std.process.exit(0),
            error.InvalidArgs, error.MissingValue, error.UnknownArgument, error.OutOfMemory => std.process.exit(1),
        }
    };

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
    var v4_segments: usize = 0;
    var v6_segments: usize = 0;

    var time_io_ns: i128 = 0;
    var time_flatten_ns: i128 = 0;
    var time_cidr_ns: i128 = 0;

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
        const v4_result = pipeline_mod.processStream(
            u32,
            init.io,
            v4_path,
            static_v4_ranges.items,
            &seen_v4,
            writer,
            alloc,
            &country_map,
            &filter_map,
        ) catch |err| {
            if (err == error.FileNotFound) {
                std.log.err("IPv4 CSV file not found: '{s}'", .{v4_path});
            } else {
                std.log.err("Failed to process IPv4 CSV file '{s}': {}", .{ v4_path, err });
            }
            std.process.exit(1);
        };
        v4_stats = v4_result.stats;
        v4_cidrs = v4_result.cidrs;
        v4_countries = v4_result.countries;
        v4_flattened = v4_result.flattened;
        v4_segments = v4_result.segments;
        time_io_ns += v4_result.time_io_ns;
        time_flatten_ns += v4_result.time_flatten_ns;
        time_cidr_ns += v4_result.time_cidr_ns;
    }

    if (config.ipv6_csv) |v6_path| {
        const v6_result = pipeline_mod.processStream(
            u128,
            init.io,
            v6_path,
            static_v6_ranges.items,
            &seen_v6,
            writer,
            alloc,
            &country_map,
            &filter_map,
        ) catch |err| {
            if (err == error.FileNotFound) {
                std.log.err("IPv6 CSV file not found: '{s}'", .{v6_path});
            } else {
                std.log.err("Failed to process IPv6 CSV file '{s}': {}", .{ v6_path, err });
            }
            std.process.exit(1);
        };
        v6_stats = v6_result.stats;
        v6_cidrs = v6_result.cidrs;
        v6_countries = v6_result.countries;
        v6_flattened = v6_result.flattened;
        v6_segments = v6_result.segments;
        time_io_ns += v6_result.time_io_ns;
        time_flatten_ns += v6_result.time_flatten_ns;
        time_cidr_ns += v6_result.time_cidr_ns;
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
    std.debug.print("  Phase 1 (Sweep Line): Disjoint Segments: IPv4: {}, IPv6: {}\n", .{
        v4_flattened,
        v6_flattened,
    });
    std.debug.print("  Phase 2 (CIDR Gen): Segments processed: IPv4: {}, IPv6: {}\n", .{
        v4_segments,
        v6_segments,
    });
    std.debug.print("  Phase 2 (CIDR Gen): Static Overrides: IPv4: {}, IPv6: {}\n", .{
        v4_stats.overrides,
        v6_stats.overrides,
    });
    std.debug.print("  Phase 2 (CIDR Gen): Unique countries mapped: IPv4: {}, IPv6: {}\n", .{
        v4_countries,
        v6_countries,
    });
    std.debug.print("  Outputs (CIDR networks generated): IPv4: {}, IPv6: {}, Static: {}, Total: {}\n", .{
        v4_cidrs,
        v6_cidrs,
        static_stats.lines_parsed,
        total_cidrs,
    });

    const est_ram_mb = nginx_mod.estimateRamMB(v4_cidrs, v6_cidrs);
    std.debug.print("  Estimated Nginx RAM footprint: ~{} MB (97B/CIDR, verified via profiling)\n", .{est_ram_mb});

    std.debug.print("  Pipeline Profiling: I/O & Parsing: {}ms, Phase 1 (Flatten): {}ms, Phase 2 (CIDR Gen): {}ms\n", .{
        @divTrunc(time_io_ns, 1_000_000),
        @divTrunc(time_flatten_ns, 1_000_000),
        @divTrunc(time_cidr_ns, 1_000_000),
    });
}

test {
    std.testing.refAllDecls(@This());
}
