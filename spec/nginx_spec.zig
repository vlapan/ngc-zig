/// Module: NGINX MEMORY ESTIMATION
/// Estimates Nginx RSS for a given number of IPv4 and IPv6 CIDRs.
/// Used in CLI telemetry output to warn users about RAM requirements.
///
/// Constants (verified via profiling, 2026-05-16):
///   bytes_per_ipv4 = 97
///   bytes_per_ipv6 = 97  (same struct size for both trees on 64-bit)
///
/// Functions:
///   estimateRamBytes(v4, v6) — total bytes = v4*97 + v6*97
///   estimateRamMB(v4, v6)    — bytes → mebibytes (ceiling division)
///
/// Invariants:
///   - 0 CIDRs → 0 bytes, 0 MB
///   - estimateRamMB is always ceil(estimateRamBytes / 2^20)
const std = @import("std");
const lib = @import("lib");
const data = @import("data/nginx.zig");
const testing = std.testing;

test "estimateRamBytes: all cases" {
    for (&data.estimate_ram_bytes_rows) |row| {
        const result = lib.nginx.estimateRamBytes(row.v4, row.v6);
        if (result != row.expected) {
            std.debug.print("FAIL {s}: {s} — expected {d}, got {d}\n", .{ row.id, row.given, row.expected, result });
            return error.TestFailed;
        }
    }
}

test "estimateRamMB: all cases" {
    for (&data.estimate_ram_mb_rows) |row| {
        const result = lib.nginx.estimateRamMB(row.v4, row.v6);
        if (result != row.expected) {
            std.debug.print("FAIL {s}: {s} — expected {d}, got {d}\n", .{ row.id, row.given, row.expected, result });
            return error.TestFailed;
        }
    }
}
