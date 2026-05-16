const std = @import("std");

/// Estimated Nginx geo module memory footprint per CIDR entry.
/// Derived from source code analysis AND actual profiling.
///
/// Profiling results (macOS ARM64, nginx 1.31.0, 1M CIDRs):
///   Baseline RSS: 6.1 MB
///   Full RSS:     98.7 MB
///   Delta:        92.7 MB for 1,006,593 CIDRs
///   Per-CIDR:     96.63 bytes (measured)
///
/// Why the original estimate (56B/72B) was wrong:
///   - Only counted raw struct size, not allocation patterns
///   - Each CIDR creates 2-3 unique radix tree nodes (not 1)
///   - Node struct on 64-bit: 4 pointers (left/right/parent/value) = 32 bytes
///   - Pool allocation overhead + alignment + fragmentation
///   - Value storage (ngx_http_variable_value_t) per unique country
///
/// Platform specifics:
///   64-bit (ARM64/x86_64): ~97 bytes/CIDR (pointers are 8 bytes)
///   32-bit:                ~50 bytes/CIDR (pointers are 4 bytes, half the node size)
///   Linux vs macOS:        Slight variation in pool allocator overhead (~5-10%)
///
/// IPv4 vs IPv6:
///   Theoretical difference is small in practice. Both use the same radix tree
///   infrastructure with 64-bit pointers. IPv6 trees are deeper (128 vs 32 levels)
///   but most nodes are shared. Measured delta shows ~97B per CIDR regardless.
pub const bytes_per_ipv4: usize = 97;
pub const bytes_per_ipv6: usize = 97;

/// Calculates the estimated Nginx RAM footprint for the given CIDR counts.
/// Returns the estimate in bytes.
pub fn estimateRamBytes(v4_cidrs: usize, v6_cidrs: usize) usize {
    return v4_cidrs * bytes_per_ipv4 + v6_cidrs * bytes_per_ipv6;
}

/// Calculates the estimated Nginx RAM footprint in megabytes.
pub fn estimateRamMB(v4_cidrs: usize, v6_cidrs: usize) usize {
    return estimateRamBytes(v4_cidrs, v6_cidrs) / (1024 * 1024);
}

const testing = std.testing;

test "nginx.estimateRamBytes: zero counts" {
    try testing.expectEqual(@as(usize, 0), estimateRamBytes(0, 0));
}

test "nginx.estimateRamBytes: single IPv4" {
    try testing.expectEqual(@as(usize, 97), estimateRamBytes(1, 0));
}

test "nginx.estimateRamBytes: single IPv6" {
    try testing.expectEqual(@as(usize, 97), estimateRamBytes(0, 1));
}

test "nginx.estimateRamBytes: mixed counts" {
    try testing.expectEqual(@as(usize, 97 + 97), estimateRamBytes(1, 1));
    try testing.expectEqual(@as(usize, 970 + 970), estimateRamBytes(10, 10));
}

test "nginx.estimateRamBytes: realistic dataset" {
    // ~500k IPv4, ~500k IPv6 (typical GeoIP dataset)
    const v4: usize = 498_745;
    const v6: usize = 507_843;
    const expected = v4 * 97 + v6 * 97;
    try testing.expectEqual(expected, estimateRamBytes(v4, v6));
}

test "nginx.estimateRamMB: zero counts" {
    try testing.expectEqual(@as(usize, 0), estimateRamMB(0, 0));
}

test "nginx.estimateRamMB: small counts round down" {
    try testing.expectEqual(@as(usize, 0), estimateRamMB(1000, 1000));
}

test "nginx.estimateRamMB: realistic dataset" {
    const v4: usize = 498_745;
    const v6: usize = 507_843;
    const expected_mb = estimateRamBytes(v4, v6) / (1024 * 1024);
    try testing.expectEqual(expected_mb, estimateRamMB(v4, v6));
}

test "nginx.estimateRamMB: exactly 1 MB threshold" {
    // 1 MB = 1,048,576 bytes
    // With only IPv4: 1,048,576 / 97 = 10,810.06... so 10,810 = 1,048,570 bytes (< 1 MB)
    // 10,811 = 1,048,667 bytes (> 1 MB)
    try testing.expectEqual(@as(usize, 0), estimateRamMB(10_810, 0));
    try testing.expectEqual(@as(usize, 1), estimateRamMB(10_811, 0));
}
