# Project Tasks & Backlog
Updated: 2026-05-14

## Active / Next Up

- [ ] **Performance: Future Optimizations**: Continuously profile and research new algorithmic or structural optimization possibilities. (Details: `notes/2026-05-14.md`)
- [ ] **Machine-Readable Telemetry**: Add a `--json` or `--quiet` flag to export strictly machine-readable JSON stats (collisions, overrides, runtime) for CI/CD ingestion and historical tracking. (Details: `notes/2026-05-13.md`)
- [ ] **Automatic Diffing**: Output a clean `+ Added`, `- Removed`, `~ Changed` delta log instead of a raw dump when generating new routing tables. (Details: `notes/2026-05-13.md`)
- [ ] **Multi-threading / Parallel Pipelines**: Parallelize the independent IPv4 and IPv6 Trie construction/parsing streams. (Details: `notes/2026-05-13.md`)

## Completed (Recent)
- [x] **Test Engineering: TDD & Expanded Coverage**: Unit tests generated for pure algorithmic components, including `src/flatten.zig` (1D Sweep-Line Pre-Flattening merges and priorities) and `src/ip.zig` IPv4 routines. (Completed: 2026-05-14)
- [x] **Architecture: Module Separation**: Decoupled monolithic files into `trie.zig`, `flatten.zig`, `parser.zig`, `config.zig`, `ip.zig`, and `main.zig`. (Completed: 2026-05-14)
- [x] **Test Infrastructure: Feature-Specific Benchmarking**: Created dedicated `Makefile` commands to benchmark filtering and grouping isolated from the baseline, capturing metrics in separate log files. (Completed: 2026-05-14)
- [x] **Test Infrastructure: Feature-Specific Validation**: Created dedicated `Makefile` commands to test and verify (via `git diff`) the `--group` and `--filter` outputs to catch regressions before releases. (Completed: 2026-05-14)
- [x] **Test Infrastructure: Baseline Benchmark Relocation**: Moved `benchmarks.log` to `test/baseline-benchmarks.log` to clarify it tests the raw, unfiltered architecture. (Completed: 2026-05-14)
- [x] **Country Filtering**: Add `--filter` and `--filters-file` to allowlist specific source countries before grouping. (Completed: 2026-05-14)
- [x] **Custom Country Grouping**: Implemented `--group` and `--groups-file` to aggregate countries into blocks (e.g., `EU`) and seamlessly merge Nginx output. (Completed: 2026-05-14)
- [x] **Estimated Nginx RAM footprint**: Added heuristic to approximate RAM usage of resulting Nginx CIDRs (`~64B/v4`, `~128B/v6`). (Completed: 2026-05-14)
- [x] **Memory Optimization: Stream Flattened Output to Trie**: Refactored `flatten` to stream segments directly into the `IpTrie`, eliminating intermediate `flattened_vX` arrays and dropping Max RSS by ~18.3MB. (Completed: 2026-05-14)
- [x] **Telemetry Enhancements**: Added tracking for Radix Nodes, Contiguous Merges, and Granular Pipeline Profiling to CLI output. (Completed: 2026-05-14)
- [x] **Algorithmic Pre-Flattening**: Repurpose the sweep-line 1D collision algorithm to resolve overlaps *before* Radix tree insertion, eliminating fragmentation and backtracking overhead entirely. (Completed: 2026-05-14)
- [x] **Branchless Trie Node Allocation**: Switch `Trie.append()` to `.appendAssumeCapacity()` in the inner loop, stripping bounds-check branches since the tree is mathematically pre-allocated. (Completed: 2026-05-14)
- [x] **Lightweight Index Sorting**: Run `std.sort` on a tightly packed `[]u32` array of array indices instead of swapping bulky 64-byte IPv6 structs in memory. (Completed: 2026-05-14)
- [x] **Branchless IPv6 Formatting**: Replaced boolean flags and branches in the IPv6 text formatter with hardware Count Leading Zeros (`@clz`). (Completed: 2026-05-14)
- [x] **IPv6 Zero Compression**: Custom 2-pass u128 formatter. (Completed: 2026-05-13)
- [x] **Zero-Allocation Country Code Casting (u16)**. (Completed: 2026-05-13)
- [x] **Node Memory Packing (8-byte packed struct)**. (Completed: 2026-05-13)
- [x] **Proportional Trie Pre-allocation**. (Completed: 2026-05-13)
- [x] **File Memory-Mapping (mmap)**. (Completed: 2026-05-13)
- [x] **SWAR (SIMD Within A Register) Integer Parsing**. (Completed: 2026-05-13)
- [x] **OS Memory Hinting (MADV.SEQUENTIAL)**. (Completed: 2026-05-13)
- [x] **Dataset Overlap/Collision Reporting**. (Completed: 2026-05-13)
- [x] **Look-Up Table (LUT) for Zero-Division IP Formatting**. (Completed: 2026-05-13)
- [x] **ETag Desynchronization Fix**: Store `.etag` in git. (Completed: 2026-05-14)

## Validation Rule Noted:
*In future sessions, before beginning work on a specific implementation task from the backlog, I must always verify against the current codebase that the underlying assumptions, functions, and architecture it targets have not organically mutated or been rendered obsolete by other changes. Validate first, then implement.*
