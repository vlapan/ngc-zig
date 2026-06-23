/// Scenario: CLI ORCHESTRATION
/// Tests the full `main.run()` function which ties all pipeline stages
/// together with real file I/O. Verifies output file content and format.
///
/// SCENARIO-008: basic v4 run with known fixtures
/// SCENARIO-009: v4 with static file (HOLE echo only, no CIDRs)
const std = @import("std");
const lib = @import("lib");
const main_runner = @import("main_runner");
const helpers = @import("../_helpers.zig");
const testing = std.testing;

test "SCENARIO-008: basic v4 run produces CIDR output" {
    const alloc = testing.allocator;
    const dir = std.Io.Dir.cwd();
    const io = std.testing.io;
    const out_path = "ngc-test-output.conf";

    defer dir.deleteFile(io, out_path) catch {};

    const config = lib.config.Config{
        .ipv4_csv = "spec/fixtures/ipv4.csv",
        .output = out_path,
    };

    _ = try main_runner.run(io, alloc, config);

    const file = try dir.openFile(io, out_path, .{});
    defer file.close(io);
    const stat = try file.stat(io);
    try testing.expect(stat.size > 0);

    const mapped = try std.posix.mmap(null, stat.size, .{ .READ = true }, .{ .TYPE = .PRIVATE }, file.handle, 0);
    defer std.posix.munmap(mapped);
    const output = mapped[0..stat.size];

    try helpers.validateOutputFormat(output);
    try testing.expect(std.mem.indexOf(u8, output, "AU;") != null);
    try testing.expect(std.mem.indexOf(u8, output, "CN;") != null);
}

test "SCENARIO-009: v4 run with static file echoes lines" {
    const alloc = testing.allocator;
    const dir = std.Io.Dir.cwd();
    const io = std.testing.io;
    const out_path = "ngc-test-output-static.conf";
    const static_path = "ngc-test-static-input.txt";

    try dir.writeFile(io, .{ .sub_path = static_path, .data = "10.0.0.0/8\n" });
    defer {
        dir.deleteFile(io, static_path) catch {};
        dir.deleteFile(io, out_path) catch {};
    }

    const config = lib.config.Config{
        .ipv4_csv = "spec/fixtures/empty.csv",
        .static_file = static_path,
        .output = out_path,
    };

    _ = try main_runner.run(io, alloc, config);

    const file = try dir.openFile(io, out_path, .{});
    defer file.close(io);
    const stat = try file.stat(io);
    try testing.expect(stat.size > 0);

    const mapped = try std.posix.mmap(null, stat.size, .{ .READ = true }, .{ .TYPE = .PRIVATE }, file.handle, 0);
    defer std.posix.munmap(mapped);
    const output = mapped[0..stat.size];

    try testing.expect(std.mem.indexOf(u8, output, "10.0.0.0/8") != null);
}
