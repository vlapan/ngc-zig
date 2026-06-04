# Architecture
Updated: 2026-06-05

## Overview
The `NGC` CLI processes raw GeoIP CSV files, normalizes overlapping blocks, and outputs a mathematically flat and perfectly aggregated format for the Nginx Geo module.

## Core Mechanisms
The system processes data in a strictly pipelined architecture, decoupled into distinct single-responsibility modules:

### Phase 0: High-Speed Parsing (`src/parser.zig` & `src/config.zig` & `src/swar.zig`)
- **Memory-Mapped I/O**: Upstream CSVs are loaded via zero-copy `std.posix.mmap` with aggressive OS prefetching (`MADV.SEQUENTIAL`) to eliminate SSD I/O stalls.
- **SWAR CSV Tokenization**: Comma delimiters are found 8 bytes at a time using SIMD Within A Register bit manipulation (`src/swar.zig`). Replaces linear `std.mem.indexOfScalar` scans. -2.7% total instructions.
- **SWAR Integer Parsing**: Sequential loops and byte-by-byte parsing are bypassed entirely. A SIMD Within A Register (SWAR) algorithm chunks 8 ASCII digits into a 64-bit integer, calculating base-10 representations via bit-shifting, destroying millions of logic instructions.
- **Country Code Tokenization**: 2-byte country strings (e.g., "US", "FR") are converted to `u16` via `(char0 << 8) | char1` for O(1) LUT lookup.
- **Group Remap**: `c_val = country_map[c_val]` remaps country codes (e.g., FR → EU) during parsing. Safe — sweep-line handles same-country mergers regardless of when remapping happens.
- **Allowlist Filter**: `if (!filter_map[c_val]) continue;` — an INCLUSION filter. Skip ranges whose country is NOT in the allowlist. This happens during parsing (before sweep-line), which is correct: filtered ranges don't consume sweep-line resources, and the topology collapses naturally (remaining ranges fill the space, which is the desired allowlist behavior).

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

## Pipeline Orchestration (`src/pipeline.zig`)
The `processStream(comptime T: type, ...)` generic function orchestrates Phases 0-2 for a single IP version (IPv4 or IPv6):
- **Input**: CSV path, static ranges, country/filter maps, allocator, writer
- **Flow**: parse (group remap only) → append static → flatten → **filter + re-merge segments** → CIDR gen → count countries

## Filter/Group Design Rules

### `--filter` is an ALLOWLIST (Inclusion Filter)
`config.zig:199-200`:
- No `--filter` flags → `filter_map[i] = true` for all i (identity — everything passes)
- One or more `--filter` flags → `filter_map[i] = false` for all i, then specified countries set to `true`

### Group Remap During Parse, Filter at Segment Level
Group remap (`country_map[c_val]`) runs during parsing. Filter runs AFTER sweep-line at segment level. This prevents kept countries from absorbing filtered countries' IP space:

`--filter "EU" --group "EU:FR,DE"` on `[DE:/8→EU, CN:/16, FR:/24→EU]`:
- Sweep-line: `CN:0-65535, FR(EU):1024-1279, DE(EU):65536-16777215` (CN wins collision over DE)
- Filter keep EU → drop CN → gaps at 0-65535 where CN was → **CN's IPs not claimed by EU** ✓
- Parse-time filter would remove CN → DE/EU fills 0-65535 → **incorrectly claims CN's IPs** ✗

### Filter + Re-Merge (Single Pass)
After sweep-line, iterate segments: skip if not in allowlist; if adjacent to previous kept segment with same country, merge into it (extend end). This collapses adjacent same-country segments split by now-filtered foreign segments.

### Filter-Before-Group Order Bug
`parser.zig:191-195` has an additional bug: filter runs BEFORE group remap:
```
if (!filter_map[c_val]) continue;   // filter on ORIGINAL code
c_val = country_map[c_val];         // group remap (too late)
```
`--filter "EU" --group "EU:FR,DE"`: FR checked against original code (0x4652) before remap → not in filter → dropped. Fix: swap the two lines so group remap runs before filter check.

### Static Overrides Always Survive
Static HOLE ranges are appended in `pipeline.zig:37-39` after `parseFile` returns, bypassing `parseFile` entirely. HOLE (0xFFFF) segments survive sweep-line as normal. CIDR gen skips them (cidr.zig:17,37). They're unaffected by country filter — intentional: user's static "remove this IP" should work regardless.

## Nginx Memory Footprint
The `src/nginx.zig` module provides `estimateRamBytes()` and `estimateRamMB()` for telemetry output.

**Constants** (verified via actual profiling, 2026-05-16):
- `bytes_per_ipv4 = 97`
- `bytes_per_ipv6 = 97`
- Unified because nginx uses the same `ngx_radix_node_t` (4 pointers = 32B) for both IPv4 and IPv6 trees on 64-bit platforms

**Platform variations**:
- 64-bit (ARM64/x86_64): ~97 bytes/CIDR
- 32-bit: ~50 bytes/CIDR (pointers are 4 bytes)
- Linux vs macOS: ~5-10% variation in pool allocator overhead

**Geo lookup latency**: ~0.001ms per lookup (effectively zero). The radix tree over 1M CIDRs adds no measurable latency.
