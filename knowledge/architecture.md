# Architecture
Updated: 2026-05-14

## Overview
The `NGC` CLI processes raw GeoIP CSV files, normalizes overlapping blocks, and outputs a mathematically flat and perfectly aggregated format for the Nginx Geo module.

## Core Mechanisms
The system processes data in a strictly pipelined architecture, decoupled into distinct single-responsibility modules:

### Phase 0: High-Speed Parsing (`src/parser.zig` & `src/config.zig`)
- **Memory-Mapped I/O**: Upstream CSVs are loaded via zero-copy `std.posix.mmap` with aggressive OS prefetching (`MADV.SEQUENTIAL`) to eliminate SSD I/O stalls.
- **SWAR Integer Parsing**: Sequential loops and byte-by-byte parsing are bypassed entirely. A SIMD Within A Register (SWAR) algorithm chunks 8 ASCII digits into a 64-bit integer, calculating base-10 representations via bit-shifting, destroying millions of logic instructions.
- **Zero-Cost Filtering & Grouping**: `src/config.zig` translates incoming 2-byte country strings immediately into `u16` tokens via an O(1) Look-Up Table (LUT). Allowlist filters aggressively drop unwanted networks here before they consume memory or processing time.

### Phase 1: Conflict Resolution (`src/flatten.zig`)
Upstream datasets are "dirty" and contain heavily overlapping, nested, and conflicting subnets.
- **Input Sorting**: Raw IP blocks are sorted by size descending using a lightweight index array (`[]u32`). This enforces producer priority (`GeoFeed > Whois > ASN`), meaning small specific blocks logically "overwrite" large generalized blocks.
- **1D Sweep-Line Pre-Flattening**: Before hitting the Trie, a sweep-line algorithm walks all IP boundaries, mathematically resolving overlaps, collisions, and subsumptions. Contiguous sibling blocks belonging to the same country are seamlessly merged.
- **Result**: The output of this phase is a mathematically perfect, non-overlapping stream of disjoint IP segments.

### Phase 2: CIDR Generation & Aggregation (`src/trie.zig` & `src/ip.zig`)
Nginx does not accept arbitrary `start-end` IP ranges; it strictly requires power-of-two aligned CIDR blocks.
- **Binary Prefix Tree (`IpTrie`)**: The Radix Trie acts strictly as a CIDR boundary generator. When the pre-flattened disjoint segments are streamed into the Trie, its binary math naturally fractures them into the absolute minimum number of valid Nginx CIDRs (e.g., `/32`, `/31`, `/29`).
- **Memory**: The tree uses `std.ArrayListUnmanaged` with an 8-byte packed AoS layout, backed by branchless allocations (`appendAssumeCapacity`) for extreme memory locality.
- **Static Overrides**: `--static` network files are stamped at the very end as a `HOLE` to forcefully punch out internal IP ranges.
- **Bottom-Up Optimization**: A post-order traversal (`optimize()`) sweeps the tree to merge any adjacent `/24` siblings back into a `/23` if they somehow share the exact same country.
- **Branchless Formatting**: A pre-order traversal dumps the networks using LUTs for IPv4 and hardware Count Leading Zeros (`@clz`) for RFC 5952 compliant IPv6 zero-compression.
