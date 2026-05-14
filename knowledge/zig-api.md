# Zig 0.16.0 API Notes
Updated: 2026-05-12

## Process & IO Init
- `pub fn main(init: std.process.Init) !void`
- Access io via `init.io`, allocator via `init.gpa`
- Args via `init.minimal.args.iterate()` (returns iterator)
- `std.process.run(b.allocator, b.graph.io, ...)` (replaces deprecated `std.process.Child.run`)

## Time & Benchmarking
- `std.time.Timer` has been removed or restructured in `std.time`.
- Use `std.Io.Timestamp.now(init.io, .awake).nanoseconds` to get monotonic uptime (maps to POSIX `CLOCK_MONOTONIC` / `CLOCK_MONOTONIC_RAW`). This is required for accurate benchmarking without NTP drift.
- Use `std.Io.Timestamp.now(init.io, .real)` for wall-clock time (replaces deprecated `std.time.milliTimestamp`).

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

## Input Data Format
- CSV: start_ip, end_ip, country_code
- IPv4: numeric format (e.g., `16777216,16777471,AU`)
- IPv6: numeric format (big integers up to ~2^128)
## Memory Buffers & Testing (`std.Io.Writer.Allocating`)
- In Zig 0.16.0, `std.Io.Writer.Allocating` is the new standard for building strings in memory, replacing the legacy `std.ArrayList(u8).writer()` pattern.
- Init: `var aw: std.Io.Writer.Allocating = .init(allocator);`
- Write: Pass `&aw.writer` to any function expecting a `*std.Io.Writer` (or `anytype`).
- Read Output: `aw.writer.buffered()` returns `[]const u8`.
- Clear/Reset: `aw.clearRetainingCapacity()`. (CRITICAL: The method belongs to the `Allocating` struct `aw`, NOT the internal primitive slice `aw.writer.buffer`).

## Networking (`std.Io.net`)
- IPv4/IPv6 address parsing and structs live in `std.Io.net` in 0.16.0 (e.g., `std.Io.net.IpAddress`).
- **Formatting Trap:** The standard library `format` function (`try w.print("{f}", .{ip})`) enforces strict URI formatting. It will forcibly wrap IPv6 addresses in brackets and append the port (e.g., `[2001:db8::1]:0`). If you need raw IP strings, you must write a custom formatter.

## Hardware Builtins (Performance)
- `@clz(x)`: Count leading zeros. Compiles directly to the hardware `lzcnt` ASM instruction. Extremely useful for eliminating `if` branches inside tight loops (e.g., stripping leading zeros in Hex formatting).
- `@ctz(x)`: Count trailing zeros. Compiles to `tzcnt`.

