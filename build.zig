const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const optimize_mode = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "geoip-converter",
        .root_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .optimize = optimize_mode,
        .target = b.standardTargetOptions(.{}),
    }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const step = b.step("run", "Run the geoip-converter");
    step.dependOn(&run_cmd.step);
}