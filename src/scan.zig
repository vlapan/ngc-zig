const std = @import("std");

/// Callers needing two occurrences: call findByte twice (on haystack and
/// haystack[comma1+1..]). A single-pass helper was evaluated at +63% slower
/// due to match-tracking overhead across 8-byte chunks. Two calls is faster
/// for typical sub-50 byte inputs.
pub fn findByte(haystack: []const u8, needle: u8) ?usize {
    if (haystack.len == 0) return null;

    const needle8: u64 = @as(u64, needle) * 0x0101010101010101;

    var i: usize = 0;
    while (i + 8 <= haystack.len) : (i += 8) {
        var chunk = std.mem.readInt(u64, haystack[i .. i + 8][0..8], .little);
        chunk ^= needle8;

        const has_zero = (chunk -% 0x0101010101010101) & ~chunk & 0x8080808080808080;
        if (has_zero != 0) {
            return i + (@ctz(has_zero) >> 3);
        }
    }

    while (i < haystack.len) : (i += 1) {
        if (haystack[i] == needle) return i;
    }

    return null;
}
