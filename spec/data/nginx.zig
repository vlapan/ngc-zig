pub const EstimateRamBytesRow = struct {
    id: []const u8,
    given: []const u8,
    v4: usize,
    v6: usize,
    expected: usize,
};

pub const estimate_ram_bytes_rows = [_]EstimateRamBytesRow{
    .{ .id = "ERB-001", .given = "zero counts", .v4 = 0, .v6 = 0, .expected = 0 },
    .{ .id = "ERB-002", .given = "single IPv4", .v4 = 1, .v6 = 0, .expected = 97 },
    .{ .id = "ERB-003", .given = "single IPv6", .v4 = 0, .v6 = 1, .expected = 97 },
    .{ .id = "ERB-004", .given = "mixed counts", .v4 = 1, .v6 = 1, .expected = 97 + 97 },
    .{ .id = "ERB-005", .given = "mixed counts 10 each", .v4 = 10, .v6 = 10, .expected = 970 + 970 },
    .{ .id = "ERB-006", .given = "realistic dataset", .v4 = 498_745, .v6 = 507_843, .expected = (498_745 + 507_843) * 97 },
};

pub const EstimateRamMBRow = struct {
    id: []const u8,
    given: []const u8,
    v4: usize,
    v6: usize,
    expected: usize,
};

pub const estimate_ram_mb_rows = [_]EstimateRamMBRow{
    .{ .id = "ERM-001", .given = "zero counts", .v4 = 0, .v6 = 0, .expected = 0 },
    .{ .id = "ERM-002", .given = "small counts round down", .v4 = 1000, .v6 = 1000, .expected = 0 },
    .{ .id = "ERM-003", .given = "realistic dataset", .v4 = 498_745, .v6 = 507_843, .expected = (498_745 + 507_843) * 97 / (1024 * 1024) },
    .{ .id = "ERM-004", .given = "exactly 1 MB threshold below", .v4 = 10_810, .v6 = 0, .expected = 0 },
    .{ .id = "ERM-005", .given = "exactly 1 MB threshold above", .v4 = 10_811, .v6 = 0, .expected = 1 },
};
