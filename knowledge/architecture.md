# Architecture
Updated: 2026-05-16

## Overview
The `NGC` CLI processes raw GeoIP CSV files, normalizes overlapping blocks, and outputs a mathematically flat and perfectly aggregated format for the Nginx Geo module.

## Core Mechanisms
The system processes data in a strictly pipelined architecture, decoupled into distinct single-responsibility modules:

### Phase 0: High-Speed Parsing (`src/parser.zig` & `src/config.zig` & `src/swar.zig`)
- **Memory-Mapped I/O**: Upstream CSVs are loaded via zero-copy `std.posix.mmap` with aggressive OS prefetching (`MADV.SEQUENTIAL`) to eliminate SSD I/O stalls.
- **SWAR CSV Tokenization**: Comma delimiters are found 8 bytes at a time using SIMD Within A Register bit manipulation (`src/swar.zig`). Replaces linear `std.mem.indexOfScalar` scans. -2.7% total instructions.
- **SWAR Integer Parsing**: Sequential loops and byte-by-byte parsing are bypassed entirely. A SIMD Within A Register (SWAR) algorithm chunks 8 ASCII digits into a 64-bit integer, calculating base-10 representations via bit-shifting, destroying millions of logic instructions.
- **Zero-Cost Filtering & Grouping**: `src/config.zig` translates incoming 2-byte country strings immediately into `u16` tokens via an O(1) Look-Up Table (LUT). Allowlist filters aggressively drop unwanted networks here before they consume memory or processing time.

### Phase 1: Conflict Resolution (`src/flatten.zig`)
Upstream datasets are "dirty" and contain heavily overlapping, nested, and conflicting subnets.
- **Input Sorting**: Raw IP blocks are sorted by size descending using a lightweight index array (`[]u32`). This enforces producer priority (`GeoFeed > Whois > ASN`), meaning small specific blocks logically "overwrite" large generalized blocks.
- **1D Sweep-Line Pre-Flattening**: A sweep-line algorithm walks all IP boundaries, mathematically resolving overlaps, collisions, and subsumptions. Contiguous sibling blocks belonging to the same country are seamlessly merged. Static overrides (HOLE entries) are appended to the input with `size=0`, ensuring they naturally win every collision via the priority rule.
- **Result**: The output of this phase is a `[]Segment(T)` array of mathematically perfect, non-overlapping, disjoint IP segments with resolved country assignments.

### Phase 2: CIDR Generation (`src/cidr.zig` & `src/ip.zig`)
Nginx does not accept arbitrary `start-end` IP ranges; it strictly requires power-of-two aligned CIDR blocks.
- **Iterative Range-to-CIDR**: Each disjoint segment is converted to minimum CIDR blocks via a tight iterative loop. For each position, the largest power-of-2 aligned block fitting within the remaining range is emitted, then the cursor advances. Zero allocations, zero recursion.
- **HOLE Handling**: Segments with `country=HOLE` produce no output, effectively punching holes for private/static ranges.
- **Private IPv4 Filtering**: RFC1918 ranges are automatically suppressed from output.
- **Branchless Formatting**: IPv4 uses LUTs, IPv6 uses hardware Count Leading Zeros (`@clz`) for RFC 5952 compliant zero-compression.
