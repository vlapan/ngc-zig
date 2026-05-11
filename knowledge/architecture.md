# Architecture
Updated: 2026-05-12

## Overview
The `NGC` CLI processes raw GeoIP CSV files, normalizes overlapping blocks, and outputs a mathematically flat and perfectly aggregated format for the Nginx Geo module.

## Core Mechanism: Radix Trie
1. **Input Sorting**: Raw IP blocks are loaded and sorted by `size` DESCENDING (`sortRangesBySizeDesc`). This mimics the producer's specific priority overlay (`GeoFeed > Whois > ASN`). The massive generalized ASN blocks form the "base," while specific GeoFeed overrides rewrite blocks inside the trie later.
2. **Binary Prefix Tree (IpTrie)**: 
   - A single binary prefix tree is used per IP version (`u32` for IPv4, `u128` for IPv6). 
   - Implemented using `std.ArrayListUnmanaged` for zero-overhead, extremely compact memory storage. Memory stays under ~140MB for the full IPv4/IPv6 sets.
3. **Range Insertion**: Starts from the root (`0` to `maxInt`). Recursively maps bounds. If a range exactly matches a node's bounds, the node is stamped with the `country_idx`. Otherwise, it splits into `left` and `right` children (`MIXED` parent state).
4. **Bottom-Up Optimization**: 
   - A post-order traversal (`optimize()`) checks if `left` and `right` sibling nodes share the exact same `country_idx` and are not `MIXED`.
   - If they match, they are merged back into the parent node, naturally folding contiguous networks spanning multiple smaller CIDRs into their absolute maximum possible CIDR blocks.
5. **Dumping**: A pre-order traversal traverses the optimized tree, emitting perfectly disjoint non-overlapping CIDR blocks.
