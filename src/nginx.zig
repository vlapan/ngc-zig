const std = @import("std");

/// Estimated Nginx geo module memory footprint per CIDR entry.
/// Derived from analysis of ngx_http_geo_module.c source code.
///
/// CIDR Mode (what our output uses):
/// - IPv4: ngx_radix32tree_t node (~32-48 bytes) + pool overhead (~16 bytes) = ~56 bytes
/// - IPv6: ngx_radix128tree_t node (~48-64 bytes) + pool overhead (~16 bytes) = ~72 bytes
///
/// Country values are deduplicated via rbtree and stored once per unique country,
/// so they are NOT included in the per-CIDR cost.
///
/// Source: https://github.com/nginx/nginx/blob/master/src/http/modules/ngx_http_geo_module.c
pub const bytes_per_ipv4: usize = 56;
pub const bytes_per_ipv6: usize = 72;

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
    try testing.expectEqual(@as(usize, 56), estimateRamBytes(1, 0));
}

test "nginx.estimateRamBytes: single IPv6" {
    try testing.expectEqual(@as(usize, 72), estimateRamBytes(0, 1));
}

test "nginx.estimateRamBytes: mixed counts" {
    try testing.expectEqual(@as(usize, 56 + 72), estimateRamBytes(1, 1));
    try testing.expectEqual(@as(usize, 560 + 720), estimateRamBytes(10, 10));
}

test "nginx.estimateRamBytes: realistic dataset" {
    // ~500k IPv4, ~500k IPv6 (typical GeoIP dataset)
    const v4: usize = 498_745;
    const v6: usize = 507_843;
    const expected = v4 * 56 + v6 * 72;
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
    // With only IPv4: 1,048,576 / 56 = 18,724.57... so 18,724 = 1,048,544 bytes (< 1 MB)
    // 18,725 = 1,048,600 bytes (> 1 MB)
    try testing.expectEqual(@as(usize, 0), estimateRamMB(18_724, 0));
    try testing.expectEqual(@as(usize, 1), estimateRamMB(18_725, 0));
}
