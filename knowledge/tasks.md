# Project Tasks & Backlog
Updated: 2026-06-05

## Active / Next Up
Sorted by score descending. Score = Impact(1-10) / Difficulty(1-10).

- [x] **Add `config.zig` Tests** `[S: 40]`: Added 12 new tests for `parseArgList()` covering valid args, missing output, no input, unknown args, missing values, help/version flags, multiple groups/filters. Added 4 tests for `setupMapsInline()` covering identity mapping, filter defaults, inline groups, inline filters. Enhanced existing `parseGroupLine` and `parseFilterLine` tests. Refactored `parseArgs()` to use testable `parseArgList(args: []const []const u8, alloc)` with explicit error types (`MissingValue`, `UnknownArgument`, `HelpRequested`, `VersionRequested`). Added `setupMapsInline()` for file-free testing. Total: 79 tests passing. (Completed: 2026-05-16)
- [x] **Remove Dead Code** `[S: 25]`: Deleted `src/trie.zig` (232 lines), dead `flatten`/`IpTrie` in `src/ip.zig` (256 lines), unused `build_info` import in `build.zig` (4 lines). Total: -492 lines. 3 atomic commits. 81 tests pass, release build verified. (Completed: 2026-05-16)
- [x] **Extract Generic `processStream()`** `[S: 20]`: Eliminated IPv4/IPv6 copy-paste in `main.zig`. Created `src/pipeline.zig` module with `processStream(comptime T: type, ...)` generic function + `StreamResult` struct. Replaced ~100 lines of duplicated pipeline code with two generic calls. Added 5 TDD tests covering IPv4, IPv6, static overrides, filtering, and country grouping via `TestEnv` helper. 86 tests pass, output matches baseline, zero performance regression. `main.zig` reduced from 275 to 227 lines. (Completed: 2026-05-16)
- [x] **Fix O(65536) Country Counting** `[S: 3.0]`: Replaced 64K bool array iteration with O(1) counter in `parser_mod.Stats.countries_seen`. Incremented during parsing on first-seen transition. Removed loop from `pipeline.zig`. Added test verifying counter matches manual iteration. 87 tests pass, output matches baseline, instructions 826-831M. (Completed: 2026-05-16)
- [ ] **Fix CI: Build Binary Step** `[S: 3.0]`: Add `zig build` to CI workflow to verify compilation. ~10 lines, D:1, I:3. (Details: `notes/2026-05-16.md`)
- [ ] **Fix CI: Run Tests Before Release** `[S: 3.0]`: Add test step to release workflow. ~10 lines, D:1, I:3. (Details: `notes/2026-05-16.md`)
- [ ] **Add Input Validation** `[S: 1.5]`: Check `start <= end`, country code format, file size limits. ~40 lines, D:2, I:3. (Details: `notes/2026-05-16.md`)
- [ ] **Fix Silent Error Swallowing** `[S: 1.5]`: Fail or warn on invalid static file data (bad prefix parse, unparseable IPs). `parser.zig:59,72,82`. ~30 lines, D:2, I:3. (Details: `notes/2026-05-16.md`)
- [x] **Remove Redundant Pre-flight File Checks** `[S: 2.0]`: Deleted 25 lines of double I/O in `main.zig:33-56`. Files are opened once during processing with proper error handling. No functional change. (Completed: 2026-05-16)
- [x] **Add `--help` / `--version` Flags** `[S: 2.0]`: `--help`/`-h` prints usage, `--version`/`-v` prints version. Both exit 0. `config.zig:80-85`, `main.zig:28`. 4 tests. (Completed: 2026-05-16)
- [ ] **Add Digit Validation to `fastParseInt`** `[S: 2.0]`: Reject non-digit characters. `parser.zig:94-129`. ~10 lines, D:1, I:2. (Details: `notes/2026-05-16.md`)
- [x] **Fail on Unknown CLI Args** `[S: 2.0]`: Returns `error.UnknownArgument` for unrecognized flags. `config.zig:87`, `main.zig:29`. 1 test. (Completed: 2026-05-16)
- [x] **Move Filter to Post-Processing** `[S: 1.5]`: Current filter at `parser.zig:191` runs during parsing (before sweep-line). This lets kept countries absorb filtered countries' IP space — wrong for an allowlist. Move filter to segment level in `pipeline.zig` after sweep-line, with adjacent same-country re-merge. Also fix filter-before-group ordering (swap lines 191/195). ~30 lines, D:4, I:6. (Details: `notes/2026-06-05.md`)
- [ ] **Add Dry-Run Mode** `[S: 1.0]`: Validate input without producing output. ~30 lines, D:2, I:2. (Details: `notes/2026-05-16.md`)
- [ ] **Add Benchmark Regression Detection to CI** `[S: 1.0]`: Run `make bench` in CI, fail on regression. ~20 lines, D:2, I:2. (Details: `notes/2026-05-16.md`)
- [ ] **Improve README** `[S: 1.0]`: Add install instructions, benchmarks, license, Nginx example, CSV format docs. ~100 lines, D:1, I:1. (Details: `notes/2026-05-16.md`)
- [ ] **Add `--quiet` / `--verbose` Flags** `[S: 1.0]`: Suppress output for CI, debug mode for troubleshooting. ~30 lines, D:1, I:1. (Details: `notes/2026-05-16.md`)
- [ ] **Fix Makefile Hardcoded SHELL** `[S: 1.0]`: Replace `/opt/homebrew/bin/zsh` with portable path. ~2 lines, D:1, I:1. (Details: `notes/2026-05-16.md`)
- [ ] **Add Linux Profiling Scripts** `[S: 0.5]`: Replace macOS-only `samply` with portable alternative. ~50 lines, D:2, I:1. (Details: `notes/2026-05-16.md`)
- [ ] **Add Progress Indication** `[S: 0.5]`: Show progress for large files (1M+ ranges). ~20 lines, D:2, I:1. (Details: `notes/2026-05-16.md`)

## Completed (Recent)
- [x] **Verify RAM Footprint Heuristic**: Profiled actual Nginx RSS with 1M CIDRs. Measured 96.68 bytes/CIDR vs estimated 64B. Updated `src/nginx.zig` to 97B/CIDR (unified v4/v6). Created `test/nginx-profile/profile.sh` for automated profiling. (Completed: 2026-05-16)
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
- [x] **Estimated Nginx RAM footprint**: Added heuristic to approximate RAM usage of resulting Nginx CIDRs. Updated to 97B/CIDR (unified v4/v6) after actual profiling showed 64B estimate was 50% low. (Completed: 2026-05-14, Updated: 2026-05-16)
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
- [ ] **Add Session Handoff Protocol** `[S: 2.0]`: Define what to do when session ends abruptly: save state, push commits, write final note entry. ~10 lines, D:1, I:2. (Details: `notes/2026-05-16.md`)
- [ ] **Add Error Handling Conventions** `[S: 2.0]`: Standardize error unions vs `catch unreachable`, when to fail vs warn, error message formatting. ~15 lines, D:1, I:2. (Details: `notes/2026-05-16.md`)
- [ ] **Add Naming Conventions** `[S: 2.0]`: Document module naming, variable naming (snake_case vs camelCase), constant naming (SCREAMING_SNAKE_CASE), test naming. ~15 lines, D:1, I:2. (Details: `notes/2026-05-16.md`)
- [ ] **Add Module Documentation Conventions** `[S: 2.0]`: Require `///` doc comments on all public functions, structs, constants. ~15 lines, D:1, I:2. (Details: `notes/2026-05-16.md`)

## Validation Rule Noted:
*In future sessions, before beginning work on a specific implementation task from the backlog, I must always verify against the current codebase that the underlying assumptions, functions, and architecture it targets have not organically mutated or been rendered obsolete by other changes. Validate first, then implement.*

## Task Scoring Rule:
Every task in the Active/Next Up table must include a **Score** in the format `[S: X]` where X is calculated as:

**Score = Impact(1-10) / Difficulty(1-10)**

- **Impact**: 1 (marginal) to 10 (critical). Accounts for performance gains, correctness fixes, or user value.
- **Difficulty**: 1 (trivial) to 10 (complex/architectural). Accounts for risk, testing needs, and unknowns.

**Score ranges**: 0.1 (hard, low-value) to 10.0 (trivial, critical).

**Priority**: Sort tasks by score descending. High score = best ROI (high impact, low effort). Low score = poor ROI (low impact, high effort).

**Example**: Fix CI Build (~10 lines, trivial, critical) → `3 / 1 = 3.0` → `[S: 3.0]`
**Example**: Add Input Validation (~40 lines, moderate, high impact) → `3 / 2 = 1.5` → `[S: 1.5]`
**Example**: Improve README (~100 lines, trivial, marginal) → `1 / 1 = 1.0` → `[S: 1.0]`
