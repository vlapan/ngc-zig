/// Tier: REGRESSION
/// Maps past bug descriptions to the IAE row IDs that protect against them.
/// Not executable — a human-readable cross-reference for debugging.
///
/// When a regression test fails, look up the IAE row ID here to find:
///   - When the bug was first fixed (date)
///   - Root cause
///   - Which commit fixed it (if known)
///
/// Entries:
///   REG-2026-06-05-01: CR not stripped from CSV country field  → CSV-007
///   REG-2026-06-05-02: Short country code (<2 chars) not rejected → CSV-003
///
pub const Entry = struct {
    id: []const u8,
    date: []const u8,
    description: []const u8,
    cause: []const u8,
    protected_by: []const []const u8,
};

pub const entries = [_]Entry{
    .{
        .id = "REG-2026-06-05-01",
        .date = "2026-06-05",
        .description = "CR character not stripped from country code in CSV line",
        .cause = "parseCsvLine checked for \\r on the full line but country extraction happened after trim",
        .protected_by = &.{"CSV-007"},
    },
    .{
        .id = "REG-2026-06-05-02",
        .date = "2026-06-05",
        .description = "Short country code (<2 chars) yields c_val=0 instead of skipping",
        .cause = "country.len < 2 check was missing, 0-initialized field used as-is",
        .protected_by = &.{"CSV-003"},
    },
};
