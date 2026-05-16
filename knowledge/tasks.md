# Project Tasks & Backlog
Updated: 2026-05-16

## Active / Next Up

- [ ] **Remove Dead Code**: Delete `src/trie.zig`, dead `flatten`/`IpTrie` in `src/ip.zig:10-111,300-452`, unused `build_info` import. ~250 lines. (Details: `notes/2026-05-16.md`)
- [ ] **Fix Silent Error Swallowing**: Fail or warn on invalid static file data (bad prefix, invalid IPs, parse errors). `parser.zig:58,68,71,81,176-182`. (Details: `notes/2026-05-16.md`)
- [ ] **Fail on Unknown CLI Args**: Return error on unrecognized flags instead of silently ignoring. `config.zig:50-52`. (Details: `notes/2026-05-16.md`)
- [ ] **Add `--help` / `--version` Flags**: Basic CLI usability. (Details: `notes/2026-05-16.md`)
- [ ] **Add `config.zig` Tests**: Test `parseArgs()`, `setupMaps()`, edge cases. (Details: `notes/2026-05-16.md`)
- [ ] **Fix CI: Build Binary Step**: Add `zig build` to CI workflow to verify compilation. (Details: `notes/2026-05-16.md`)
- [ ] **Fix CI: Run Tests Before Release**: Add test step to release workflow. (Details: `notes/2026-05-16.md`)
- [ ] **Fix Makefile Hardcoded SHELL**: Replace `/opt/homebrew/bin/zsh` with portable path. (Details: `notes/2026-05-16.md`)
- [ ] **Extract Generic `processStream()`**: Eliminate IPv4/IPv6 copy-paste in `main.zig:112-214`. (Details: `notes/2026-05-16.md`)
- [ ] **Remove Redundant Pre-flight File Checks**: Delete double I/O in `main.zig:35-58`. (Details: `notes/2026-05-16.md`)
- [ ] **Fix O(65536) Country Counting**: Replace array iteration with O(1) counter. `main.zig:159-161,211-213`. (Details: `notes/2026-05-16.md`)
- [ ] **Add Digit Validation to `fastParseInt`**: Reject non-digit characters. `parser.zig:93-129`. (Details: `notes/2026-05-16.md`)
- [ ] **Add Input Validation**: Check `start <= end`, country code format, file size limits. (Details: `notes/2026-05-16.md`)
- [ ] **Add `--quiet` / `--verbose` Flags**: Suppress output for CI, debug mode for troubleshooting. (Details: `notes/2026-05-16.md`)
- [ ] **Improve README**: Add install instructions, benchmarks, license, Nginx example, CSV format docs. (Details: `notes/2026-05-16.md`)
- [x] ~~**Verify RAM Footprint Heuristic**~~: Completed. Created `src/nginx.zig` with constants from Nginx source analysis. IPv4: 56B, IPv6: 72B. Old estimate ~92 MB → new ~61 MB. 10 TDD tests. (Completed: 2026-05-16)
- [ ] **Add Progress Indication**: Show progress for large files (1M+ ranges). (Details: `notes/2026-05-16.md`)
- [ ] **Add Linux Profiling Scripts**: Replace macOS-only `samply` with portable alternative. (Details: `notes/2026-05-16.md`)
- [ ] **Add Dry-Run Mode**: Validate input without producing output. (Details: `notes/2026-05-16.md`)
- [ ] **Verify RAM Footprint Heuristic**: Profile actual Nginx memory usage vs `64B/v4, 128B/v6` estimate. (Details: `notes/2026-05-16.md`)
- [ ] **Add Benchmark Regression Detection to CI**: Run `make bench` in CI, fail on regression. (Details: `notes/2026-05-16.md`)

## Completed (Recent)
- [x] **Eliminate Recursive Trie `insertRange`**: Converted to iterative stack-based traversal. -708M instructions (-30%), -18% cycles, -20% runtime. (Completed: 2026-05-15)
- [x] **Evaluate `@branchHint` placement**: Audited hot loops for predictable branches. Removed dynamic filter hint, fixed backwards flatten hints. (Completed: 2026-05-15)
- [x] **Remove duplicate `madvise` calls**: `MADV.SEQUENTIAL` called twice on same region. (Completed: 2026-05-15)
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

## Performance Optimization Backlog
Sorted by estimated theoretical impact. **Validate first** (per Validation Rule) before implementing any item.

### Tier 1: High Impact (10-50% speedup)
- [x] ~~**Direct CIDR output from sweep-line**~~: Completed. Eliminated Trie entirely, replaced with iterative rangeToCidrs(). -52.4% instructions, -66.2% cycles, -34.0% RSS. (Completed: 2026-05-16)

### Tier 2: Medium Impact (5-10% speedup)
- [x] ~~**Replace `std.mem.sort` with radix sort for events**~~: Rejected. +10.3% instructions, +35.8% RSS due to 4-8 allocation passes and memory bandwidth overhead. `std.mem.sort` (Introsort) is already optimal for 660k integer events. (Evaluated: 2026-05-16)
- [x] ~~**SWAR CSV tokenization**~~: Completed. Created `src/swar.zig` with `findChar()`. -22.9M instructions (-2.7%), -6.0M cycles (-2.9%). I/O & Parsing: 51ms → 48ms. (Completed: 2026-05-16)

### Tier 3: Low Impact (marginal gains)
- [x] ~~**Reduce `formatIPv6` buffer from 128 to 48**~~: Completed. Max IPv6 string is 39 chars; buffer is 48 bytes. (Completed: 2026-05-16)

### Rejected / Invalidated (Learnings)
- [x] ~~**Multi-threading / Parallel Pipelines**~~: Rejected. 10ms wall-clock savings for ~165 lines of complexity and +30% RSS. Tool runs in 80ms already; cost-benefit unfavorable. Reconsider if dataset grows 10x+ or becomes a real-time service. (Evaluated: 2026-05-16)
- [x] ~~**Replace `active_ids` linear scan with O(1) lookup**~~: Rejected. BGP data overlaps are shallow (depth 1-3). Linear scan over 3 elements in L1 cache beats O(1) map overhead. (Evaluated: 2026-05-15)
- [x] ~~**Avoid `@intCast` in hot trie paths**~~: Invalidated. `insertRange` is now iterative. The only remaining cast (`usize`→`u24`) is a deliberate 8-byte packing trade-off; removing it bloats `TrieNode` by 25%. (Evaluated: 2026-05-15)
- [x] ~~**Pre-allocate `active_ids` with known max**~~: Invalidated. Already `initCapacity(alloc, 64)`. BGP nesting depth is 1-3, so capacity is 20x over-provisioned. Growth never triggers. (Evaluated: 2026-05-15)
- [x] ~~**Batch writer flushes**~~: Invalidated. `formatIPv4`/`formatIPv6` write to a 64KB buffered writer. Multiple `writeAll` calls are memcpy into buffer, not syscalls. Flush only on buffer fill. (Evaluated: 2026-05-15)
- [x] ~~**Inline `getCountry`**~~: Completed. Changed to `inline fn` for explicit zero-overhead guarantee in recursive `optimize()` path. (Completed: 2026-05-15)
- [x] ~~**SWAR/SIMD further optimization**~~: Exhausted. Pipeline limited by I/O and control flow, not byte scanning. Remaining targets are branch-heavy or variable-length. (Evaluated: 2026-05-16)

## Explored / Backlog (Future Research)

- [ ] **Nginx Binary Geo Cache Generation**: Generate `.bin` file alongside text output for instant Nginx reloads. IPv4 only (ranges mode). ~200 lines, auto-loaded by Nginx. (Details: `notes/2026-05-16.md`)
- [ ] **Single Config File**: Replace `--static`, `--groups-file`, `--filters-file` with one flat key-value file. ~30 lines parser, ~2ms startup, zero dependencies. CLI args as overrides. (Details: `notes/2026-05-16.md`)
- [ ] **Io Concurrency API**: Zig 0.16.0 `io.async`/`io.concurrent`/`std.Io.Group` provides Promise-like parallelism. Revisit if dataset grows 10x+ or becomes real-time service. (Details: `notes/2026-05-16.md`)
- [ ] **Machine-Readable Telemetry**: Add `--json` flag to export stats as JSON for CI/CD ingestion. (Details: `notes/2026-05-13.md`)
- [ ] **Automatic Diffing**: Output `+ Added`, `- Removed`, `~ Changed` delta log between runs. (Details: `notes/2026-05-13.md`)

## Validation Rule Noted:
*In future sessions, before beginning work on a specific implementation task from the backlog, I must always verify against the current codebase that the underlying assumptions, functions, and architecture it targets have not organically mutated or been rendered obsolete by other changes. Validate first, then implement.*
