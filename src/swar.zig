const std = @import("std");

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

pub const TwoBytes = struct { first: usize, second: usize };

pub fn findTwoBytes(haystack: []const u8, needle: u8) ?TwoBytes {
    if (haystack.len == 0) return null;

    const needle8: u64 = @as(u64, needle) * 0x0101010101010101;
    const ones: u64 = 0x0101010101010101;
    const highs: u64 = 0x8080808080808080;

    var first: ?usize = null;
    var i: usize = 0;

    while (i + 8 <= haystack.len) : (i += 8) {
        var chunk = std.mem.readInt(u64, haystack[i .. i + 8][0..8], .little);
        chunk ^= needle8;

        var matches = (chunk -% ones) & ~chunk & highs;
        while (matches != 0) {
            const pos = i + (@ctz(matches) >> 3);
            if (first) |f| {
                return TwoBytes{ .first = f, .second = pos };
            }
            first = pos;
            matches &= matches - 1;
        }
    }

    while (i < haystack.len) : (i += 1) {
        if (haystack[i] == needle) {
            if (first) |f| {
                return TwoBytes{ .first = f, .second = i };
            }
            first = i;
        }
    }

    return null;
}

const testing = std.testing;

test "swar.findByte: single byte match" {
    try testing.expectEqual(@as(usize, 0), findByte(",", ',').?);
    try testing.expectEqual(@as(usize, 1), findByte("a,b", ',').?);
    try testing.expectEqual(@as(usize, 2), findByte("ab,c", ',').?);
}

test "swar.findByte: no match" {
    try testing.expect(findByte("abc", ',') == null);
    try testing.expect(findByte("", ',') == null);
    try testing.expect(findByte("no commas here", ',') == null);
}

test "swar.findByte: match at position 0" {
    try testing.expectEqual(@as(usize, 0), findByte(",hello", ',').?);
}

test "swar.findByte: match at position 7 (last byte of first chunk)" {
    try testing.expectEqual(@as(usize, 7), findByte("abcdefg,hij", ',').?);
}

test "swar.findByte: match at position 8 (first byte of second chunk)" {
    try testing.expectEqual(@as(usize, 8), findByte("abcdefgh,ijk", ',').?);
}

test "swar.findByte: match at position 15 (last byte of second chunk)" {
    try testing.expectEqual(@as(usize, 15), findByte("abcdefghijklmno,pqr", ',').?);
}

test "swar.findByte: multiple matches returns first" {
    try testing.expectEqual(@as(usize, 1), findByte("a,b,c", ',').?);
    try testing.expectEqual(@as(usize, 3), findByte("abc,def,ghi", ',').?);
}

test "swar.findByte: short strings (< 8 bytes)" {
    try testing.expectEqual(@as(usize, 0), findByte(",", ',').?);
    try testing.expectEqual(@as(usize, 1), findByte("a,", ',').?);
    try testing.expectEqual(@as(usize, 2), findByte("ab,", ',').?);
    try testing.expectEqual(@as(usize, 3), findByte("abc,", ',').?);
    try testing.expectEqual(@as(usize, 4), findByte("abcd,", ',').?);
    try testing.expectEqual(@as(usize, 5), findByte("abcde,", ',').?);
    try testing.expectEqual(@as(usize, 6), findByte("abcdef,", ',').?);
    try testing.expectEqual(@as(usize, 7), findByte("abcdefg,", ',').?);
}

test "swar.findByte: exactly 8 bytes, match at end" {
    try testing.expectEqual(@as(usize, 7), findByte("abcdefg,", ',').?);
}

test "swar.findByte: exactly 8 bytes, no match" {
    try testing.expect(findByte("abcdefgh", ',') == null);
}

test "swar.findByte: CSV-like lines" {
    try testing.expectEqual(@as(usize, 8), findByte("12345678,90123456,US", ',').?);
    try testing.expectEqual(@as(usize, 8), findByte("12345678,90123456,US"[9..], ',').?);
}

test "swar.findByte: different needle bytes" {
    try testing.expectEqual(@as(usize, 5), findByte("hello world", ' ').?);
    try testing.expectEqual(@as(usize, 4), findByte("path/to/file", '/').?);
    try testing.expectEqual(@as(usize, 0), findByte(";", ';').?);
}

test "swar.findTwoBytes: basic CSV line" {
    const result = findTwoBytes("12345678,90123456,US", ',').?;
    try testing.expectEqual(@as(usize, 8), result.first);
    try testing.expectEqual(@as(usize, 17), result.second);
}

test "swar.findTwoBytes: adjacent commas" {
    const result = findTwoBytes("a,,b", ',').?;
    try testing.expectEqual(@as(usize, 1), result.first);
    try testing.expectEqual(@as(usize, 2), result.second);
}

test "swar.findTwoBytes: commas at start" {
    const result = findTwoBytes(",a,b", ',').?;
    try testing.expectEqual(@as(usize, 0), result.first);
    try testing.expectEqual(@as(usize, 2), result.second);
}

test "swar.findTwoBytes: commas in same 8-byte chunk" {
    const result = findTwoBytes("a,b,cdef", ',').?;
    try testing.expectEqual(@as(usize, 1), result.first);
    try testing.expectEqual(@as(usize, 3), result.second);
}

test "swar.findTwoBytes: commas across chunk boundary" {
    const result = findTwoBytes("abcdefg,hijklmno,pqr", ',').?;
    try testing.expectEqual(@as(usize, 7), result.first);
    try testing.expectEqual(@as(usize, 16), result.second);
}

test "swar.findTwoBytes: only one comma returns null" {
    try testing.expect(findTwoBytes("abc,def", ',') == null);
}

test "swar.findTwoBytes: no commas returns null" {
    try testing.expect(findTwoBytes("abcdef", ',') == null);
}

test "swar.findTwoBytes: empty string returns null" {
    try testing.expect(findTwoBytes("", ',') == null);
}

test "swar.findTwoBytes: short strings" {
    try testing.expect(findTwoBytes(",", ',') == null);
    try testing.expect(findTwoBytes("a,", ',') == null);
    const result = findTwoBytes(",,", ',').?;
    try testing.expectEqual(@as(usize, 0), result.first);
    try testing.expectEqual(@as(usize, 1), result.second);
}

test "swar.findTwoBytes: different needle bytes" {
    const result = findTwoBytes("hello world foo bar", ' ').?;
    try testing.expectEqual(@as(usize, 5), result.first);
    try testing.expectEqual(@as(usize, 11), result.second);
}
