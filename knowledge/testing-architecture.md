# Testing Architecture
Updated: 2026-06-10

See `knowledge/testing-framework.md` for the abstract framework. This file
documents the project-specific implementation.

The test framework is the **living specification** — it defines what the system
must do. The `src/` directory is the implementation that fulfills that contract.
Spec tests are the authoritative reference for expected behavior. `spec/` is not
secondary code; it is the primary behavioral contract.

All tiers run together via `make test`.

---

## Test Types

| Kind | What | Where |
|---|---|---|
| **AAA** | Inline `test "..."` blocks with hardcoded inputs. Edge cases and complex logic that don't repeat. | `default/*.zig` |
| **IAE** | Struct array of (input, expected output, expected error) + a runner loop. Exhaustive coverage of pure functions. Inline in the same file as AAA. | `default/*.zig` |
| **Scenario** | Multi-step end-to-end using fixture files. Exercises full pipeline. | `scenario/*.zig` |
| **Property** | Randomized tests (seed 42). Generate inputs, verify invariants. | `properties.zig` |
| **Regression** | Bug registry. One row per fixed bug, added before the fix. | `regressions.zig` |
| **Perf** | Microbenchmark. No pass/fail. Measures ns/iter against committed snapshot for drift review. | `data/perf_*.zig` + `perf.zig` |

---

## File Structure

```
spec/main.zig [ROOT]
spec/
  _helpers.zig                    TestEnv, setupMapsInline, allocator helpers
  _perf_helpers.zig               Perf instrumentation (now(), cache_line)
  regressions.zig                 Bug registry
  properties.zig                  Randomized property tests

  default/                        Behavioral contracts by pipeline stage (AAA + IAE)
    input.zig                     findByte, parseInt, csvLine, staticLine
    resolve.zig                   flatten (sweep-line), filterSegments
    output.zig                    computeCidrBlock, formatIPv4Line, formatIPv6Line, rangeToCidrs
    run.zig                       processStream (full pipeline orchestration)
    options.zig                   parseArgList, parseGroupLine, parseFilterLine, setupMaps

  data/                           IAE tables for standalone utilities
    nginx.zig                     estimateRamBytes, estimateRamMB

  nginx_spec.zig                  IAE runner for nginx

  data/                           Perf microbenchmark data
    perf_parse.zig                scan + parseInt benchmarks (Parse Input stage)
    perf_output.zig               block math + format benchmarks (Output stage)

  perf.zig                        Perf binary entry (make perf)
  snapshots/
    perf-baselines.snap           Committed baseline thresholds
  fixtures/                       CSV fixture files for scenario tests
    ipv4.csv, ipv6.csv, empty.csv, ipv4-short.csv
  scenario/                       End-to-end pipeline scenarios
    basic_pipeline.zig
    filtered_pipeline.zig
    grouped_pipeline.zig
    static_override.zig

src/lib.zig                       Re-exports all 8 production modules
  cidr.zig, config.zig, flatten.zig, ip.zig, nginx.zig, parse.zig, pipeline.zig, scan.zig
test/                             CSV data files, benchmark scripts, profiling data
```

---

## Convention

Files under `default/` are named by **pipeline stage** (input, resolve, output, run, options), not by source module. Each file contains everything needed to specify that stage:

- IAE tables (struct arrays defining expected behavior)
- AAA edge case tests (inline test blocks)
- IAE runner loops (iterate over the IAE tables)
- No separation between AAA and IAE — they are merged because they specify the same functions

---

## Import Convention

All spec files import production code via `@import("lib")` (the `lib_module` in
build.zig). Individual symbols accessed as `lib.scan.*`, `lib.parse.*`, etc.

Perf data files import `@import("perf_helpers")` for `now()` and `cache_line`.

---

## IAE ID Prefixes

| Prefix | Data file | Stage |
|--------|-----------|-------|
| `SW-` | `default/input.zig` | Byte scanning (findByte) |
| `CSV-` | `default/input.zig` | CSV line parsing |
| `STA-` | `default/input.zig` | Static line parsing |
| `CIDR-` | `default/output.zig` | CIDR block computation |
| `IP-` | `default/output.zig` | IP address formatting |
| `ARG-` | `default/options.zig` | `--arg` list parsing |
| `GRP-` | `default/options.zig` | `--group` parsing |
| `FIL-` | `default/options.zig` | `--filter` parsing |
| `ERB-` | `data/nginx.zig` | Nginx RAM bytes |
| `ERM-` | `data/nginx.zig` | Nginx RAM MB |
| `PRP-` | `properties.zig` | Property tests (u32 + u128) |
| `SW-PRF-` | `data/perf_parse.zig` | Scan performance benchmarks |
| `PAR-PRF-` | `data/perf_parse.zig` | Parser performance benchmarks |
| `CIDR-PRF-` | `data/perf_output.zig` | CIDR math performance benchmarks |
| `IPF-PRF-` | `data/perf_output.zig` | Format performance benchmarks |
| `PROP-005` | `properties.zig` | u128 CIDR power-of-2 alignment |
| `PROP-006` | `properties.zig` | u128 CIDR step is power of 2 |
| `PROP-007` | `properties.zig` | u128 CIDR range containment |
| `PROP-008` | `properties.zig` | u128 formatIPv6Line newline |

---

## Module Wiring (build.zig)

```zig
const lib_module = b.createModule(.{
    .root_source_file = .{ .cwd_relative = "src/lib.zig" },
    ...
});
lib_module.addOptions("build_options.zig", options);

exe.root_module.addImport("lib", lib_module);

const spec_module = b.createModule(.{
    .root_source_file = .{ .cwd_relative = "spec/main.zig" },
    ...
});
spec_module.addImport("lib", lib_module);
spec_module.addImport("perf_helpers", perfSubModule(b, target, "spec/_perf_helpers.zig"));

const perf_module = b.createModule(.{
    .root_source_file = .{ .cwd_relative = "spec/perf.zig" },
    ...
});
perf_module.addImport("lib", lib_module);
perf_module.addImport("perf_helpers", perfSubModule(b, target, "spec/_perf_helpers.zig"));
```

---

## Makefile Targets

```makefile
test:          zig build test + run ngc-test    # AAA + IAE + scenarios + properties + regressions
perf:          zig build perf + run ngc-perf    # Perf — informational only, shows delta vs snapshot
perf-record:   zig build perf + run --record    # Record new baseline snapshot
bench:         bash test/benchmark.sh baseline   # End-to-end benchmark
check:         fmt + test + abs-paths            # Pre-commit gate
```

---

## Perf Measurement Workflow

Microbenchmarks (scan, parse, CIDR math, format) record measurements in
`spec/snapshots/perf-baselines.snap` — a git-committable text file. No
thresholds or pass/fail — the developer reviews deltas manually.

### Design decisions (2026-06-10, revision 4 — final)

- **No threshold**: `make perf` always exits 0. Developer reviews delta.
- **No auto-record**: `make perf` is read-only; `make perf-record` is explicit.
- **Informational only**: Not part of `make check`.
- **Pre-heat CPU**: 200M integer-add loop before any measurement.
- **Min is the measurement**: After T75 convergence + min-stall, the absolute
  minimum across batches is the most stable, interference-free measurement.
- **Near-min reproducibility**: `near_min >= 5` batches within 1% of running min.
- **Convergence criteria (all required)**:
  1. `stat_stall >= 10` (T75 SMA stable for 10 consecutive batches)
  2. `near_min >= 5` (5 batches within 1% of running min)
  3. `min_stall >= 10` (10 batches since last new min)
  4. `stats.count >= 20` (minimum 20 batches)
- **Budget fallback**: 1000ms max per benchmark. `[BUDGET]` flag if exceeded.

### Before making a change

```
make check
make perf-record
git add spec/snapshots/perf-baselines.snap test/*-benchmarks.log
git commit -m "chore: record baselines before change"
```

### After making a change

```
make perf           # compare current measurements vs snapshot
```

### Perf binary output

```
=== SCAN ===
  Benchmark                           Min Batches   Delta
  ------------------------------ -------- ------- -------
  SW-PRF-001                       1.51ns      44       -
  SW-PRF-002                       1.78ns      48       -
```

---

## Decision Record

- **Root is `spec/main.zig`**: All spec files import via `@import("lib")`.
- **Files organized by pipeline stage, not source module**: `default/input.zig`,
  `default/output.zig`, etc. Names describe what the system does, not how it
  implements it.
- **AAA + IAE merged**: Both test the same functions. One file per stage
  contains AAA edge cases, IAE data tables, and IAE runner loops.
- **`config.zig` retains `setupMapsInline`**: Production `setupMaps` calls it;
  keeping it in source avoids duplication.
- **`flatten` and `processStream` use AAA-only** (need allocators,
  ArrayLists, writers). Pure functions use IAE tables.
- **`options.zig` uses `ArgListError` enum** for expected errors (Zig can't
  compare types at runtime).
- **Property tests use seed 42** for reproducibility.
- **`identity_map` removed**: 128KB static array replaced by `for (0..65536)`
  loop. Binary size reduced by 128KB.
