# Zig 0.16.0 API Notes
Updated: 2026-05-11

## Process & IO Init
- `pub fn main(init: std.process.Init) !void`
- Access io via `init.io`, allocator via `init.gpa`
- Args via `init.minimal.args.iterate()` (returns iterator)

## File/Directory Operations
- `std.Io.Dir.cwd()` - get current working directory
- `try dir.createFile(io, path, .{})` - create file
- `try dir.readFileAlloc(io, path, alloc, limit)` - read entire file
- `Io.Limit` enum: `.unlimited`, `.nothing`, `.limited(n: usize)`

## File Writer
- `pub fn writer(file: File, io: Io, buffer: []u8) Writer`
- Buffer must be a slice of u8 (e.g., `var buf: [4096]u8 = undefined; out_file.writer(io, &buf)`)

## ArrayList
- `.empty` - create without allocator (needs allocator for operations)
- `.append(self, gpa, item)` - requires gpa parameter

## Common Patterns
- `fmt.parseInt(u32, s, 10)` - parse integer
- `fmt.allocPrintZ(alloc, format, args)` - alloc print with null terminator
- `mem.tokenizeAny(u8, content, "\n")` - split by newlines
- `mem.tokenizeAny(u8, line, ",")` - split by comma

## Type Casting
- `@as(T, value)` - coerce to type
- `@intCast(value)` - integer conversion (may truncate)
- `@truncate(T, value)` - bit truncation
- `@clz(x)` - count leading zeros
- `@ctz(x)` - count trailing zeros

## CIDR Math
- Prefix 0-32 for IPv4, 0-128 for IPv6
- u5 can only hold 0-31, use u6 for values up to 64
- Shift operations require u6 for 32-bit shifts