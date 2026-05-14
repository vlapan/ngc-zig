# Architecture
Updated: 2026-05-14

## Overview
The `NGC` CLI processes raw GeoIP CSV files, normalizes overlapping blocks, and outputs a mathematically flat and perfectly aggregated format for the Nginx Geo module.

## Core Mechanisms
The system currently uses a "Painter's Algorithm" inside a Radix Trie to handle all processing, but architecturally, the workload is conceptually divided into two distinct phases:

### Phase 1: Conflict Resolution (Data Cleaning)
Upstream datasets are "dirty" and contain heavily overlapping, nested, and conflicting subnets.
- **Input Sorting**: Raw IP blocks are sorted by size descending using a lightweight index array (`[]u32`). This enforces producer priority (`GeoFeed > Whois > ASN`), meaning small specific blocks logically "overwrite" large generalized blocks.
- **Static File Exclusions**: `--static` network files are treated as the ultimate priority block, stamped as a `HOLE` to forcefully punch out internal IP ranges from the CSV output.
- *(Note: Currently, this overlap resolution happens dynamically during Phase 2 Trie insertion via the Painter's Algorithm. Future optimizations aim to pre-flatten this mathematically via a 1D sweep-line algorithm before the Trie is involved.)*

### Phase 2: CIDR Generation & Aggregation (The Radix Trie)
Nginx does not accept arbitrary `start-end` IP ranges; it strictly requires power-of-two aligned CIDR blocks.
- **Binary Prefix Tree (`IpTrie`)**: The Radix Trie acts as our strict CIDR boundary generator. If an arbitrary range like `192.168.1.5 - 192.168.1.250` is inserted, the Trie's binary bounds math naturally fractures the range into the absolute minimum number of valid Nginx CIDRs (e.g., `/32`, `/31`, `/29`).
- **Memory**: The tree uses `std.ArrayListUnmanaged` with an 8-byte packed AoS layout, backed by branchless allocations (`appendAssumeCapacity`) for extreme memory locality.
- **Bottom-Up Optimization**: After insertion, a post-order traversal (`optimize()`) sweeps the tree. If two adjacent sibling CIDRs share the exact same country code, they are mathematically merged back into their parent, guaranteeing the highest possible CIDR compression for the final Nginx config.
- **Dumping**: A pre-order traversal emits the finalized, non-overlapping, heavily aggregated CIDR blocks.
