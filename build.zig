const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const zon = @import("build.zig.zon");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Capture Git Hash safely
    var git_hash: []const u8 = "release";
    if (optimize == .Debug) {
        const result = std.process.run(b.allocator, b.graph.io, .{
            .argv = &.{ "git", "rev-parse", "--short", "HEAD" },
        }) catch null;

        if (result) |res| {
            git_hash = std.mem.trim(u8, res.stdout, &std.ascii.whitespace);
        } else {
            git_hash = "unknown";
        }
    }
    const clean_hash = std.mem.trim(u8, git_hash, &std.ascii.whitespace);

    const should_stamp = b.option(bool, "stamp", "Include build timestamp") orelse true;

    const iso_string = if (should_stamp) blk: {
        const ts = std.Io.Timestamp.now(b.graph.io, .real);
        const now_ms = @as(u64, @intCast(@divFloor(ts.nanoseconds, 1_000_000)));
        const now_secs: u64 = @intCast(@divFloor(now_ms, 1000));

        const epoch_secs = std.time.epoch.EpochSeconds{ .secs = now_secs };
        const epoch_day = epoch_secs.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        const secs_into_day = @mod(now_secs, std.time.s_per_day);

        break :blk b.fmt("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z", .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            @divFloor(secs_into_day, std.time.s_per_hour),
            @divFloor(@mod(secs_into_day, std.time.s_per_hour), std.time.s_per_min),
            @mod(secs_into_day, std.time.s_per_min),
            @mod(now_ms, 1000),
        });
    } else "dev-build";

    const exe = b.addExecutable(.{
        .name = "geoip-converter",
        .version = std.SemanticVersion.parse(zon.version) catch unreachable,
        .root_module = b.createModule(.{
            .root_source_file = .{ .cwd_relative = "src/main.zig" },
            .target = target,
            .optimize = optimize,
            .single_threaded = false,
            .strip = false,
            .link_libc = false,
        }),
    });

    exe.root_module.addImport("build_info", b.createModule(.{
        .root_source_file = b.path("build.zig.zon"),
    }));

    const options = b.addOptions();
    options.addOption([]const u8, "version", zon.version);
    options.addOption([]const u8, "git_hash", clean_hash);
    options.addOption([]const u8, "build_iso_date", iso_string);
    options.addOption(std.builtin.OptimizeMode, "optimize", optimize);

    exe.root_module.addOptions("options", options);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const step = b.step("run", "Run the geoip-converter");
    step.dependOn(&run_cmd.step);
}
