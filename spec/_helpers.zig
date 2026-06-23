/// Test infrastructure shared across all spec files.
///
/// TestEnv: pre-initialized country_map (identity), filter_map (all-true),
///          seen_countries (all-false), and an allocating writer.
///          Used by run.zig, scenario/*.zig tests.
///
/// validateOutputFormat: scans a buffer and asserts every line matches
///                       the expected output format (<ip>/<prefix> <cc>;\n).
///
/// setupMapsInline: mirrors lib.config.setupMapsInline for convenience
///                  (avoids re-importing lib.config in every test).
///
/// us_idx, de_idx: pre-computed u16 country codes for common test countries.
const std = @import("std");
const lib = @import("lib");

pub const TestEnv = struct {
    country_map: [65536]u16,
    filter_map: [65536]bool,
    seen_countries: [65536]bool,
    aw: std.Io.Writer.Allocating,

    pub fn init() TestEnv {
        var country_map: [65536]u16 = undefined;
        for (0..65536) |i| country_map[i] = @intCast(i);
        return .{
            .country_map = country_map,
            .filter_map = [_]bool{true} ** 65536,
            .seen_countries = [_]bool{false} ** 65536,
            .aw = .init(std.testing.allocator),
        };
    }

    pub fn deinit(self: *TestEnv) void {
        self.aw.deinit();
    }
};

pub const eu_idx: u16 = (@as(u16, 'E') << 8) | @as(u16, 'U');
pub const us_idx: u16 = (@as(u16, 'U') << 8) | @as(u16, 'S');
pub const au_idx: u16 = (@as(u16, 'A') << 8) | @as(u16, 'U');
pub const ca_idx: u16 = (@as(u16, 'C') << 8) | @as(u16, 'A');
pub const cn_idx: u16 = (@as(u16, 'C') << 8) | @as(u16, 'N');
pub const de_idx: u16 = (@as(u16, 'D') << 8) | @as(u16, 'E');
pub const fr_idx: u16 = (@as(u16, 'F') << 8) | @as(u16, 'R');
pub const mx_idx: u16 = (@as(u16, 'M') << 8) | @as(u16, 'X');
pub const xx_idx: u16 = (@as(u16, 'X') << 8) | @as(u16, 'X');

pub const setupMapsInline = lib.config.setupMapsInline;

pub fn validateOutputFormat(output: []const u8) !void {
    try std.testing.expect(output.len > 0);

    var line_iter = std.mem.splitScalar(u8, output, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;
        try std.testing.expect(line.len >= 8);
        try std.testing.expect(line[line.len - 1] == ';');
        try std.testing.expect(std.mem.indexOfScalar(u8, line, '/') != null);
        try std.testing.expect(line[line.len - 4] == ' ');
    }
}
