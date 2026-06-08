# Testing Architecture
Updated: 2026-06-06

## Overview

Five-tier testing architecture. Each tier answers a distinct question and catches
what the others miss. Tiers are ordered by stability — spec tests change only
when requirements change, IAE tables grow with every edge case discovered.

```
TIER 1  Spec (SDD/ATDD/BDD/FDD/DDD)      — what must work, per feature
TIER 2  IAE (KDT/TDD)                     — edge cases, table-driven
TIER 3  Scenario (STDD)                   — multi-step realistic workflows
TIER 4  Property (PDD/MDD)                — mathematical invariants
TIER 5  Regression                         — bug history, cross-referenced
```

### Run order and gating

Tier 1 failures invalidate lower tiers (wrong behavior). Tiers run in order.
Makefile targets enforce this:

```
make test            Tier 1 + 2 + 3  (default, <200ms)
make test-all        All 5 tiers      (includes fuzz, <5s)
make test-t{1,2,3,4} Single tier      (for focused work)
```

---

## Tier 1: Spec (SDD/ATDD/BDD/FDD/DDD)

**Question:** Does the system do what it must do?

**Methodologies:** Spec-Driven, Acceptance Test-Driven, Behavior-Driven,
Feature-Driven, Domain-Driven.

**Structure:** One spec test per core behavior. Imperative Arrange-Act-Assert
style using the most direct public API (never CLI — that's Tier 3).

**Files:** `test/spec/*.zig`

```zig
// test/spec/collision_resolution.zig
test "SPEC-001: overlapping ranges resolve with smallest-size priority" {
    var env = TestEnv.init();
    defer env.deinit();

    const ranges = [_]ip_mod.IPv4Range{
        .{ .start = 0, .end = 511, .country = us, .size = 512 },   // /23 US
        .{ .start = 0, .end = 255, .country = ca, .size = 256 },   // /24 CA
    };

    var segments = std.ArrayList(flatten_mod.Segment(u32)).empty;
    defer segments.deinit(testing.allocator);
    _ = try flatten_mod.flatten(u32, testing.allocator, &ranges, &segments);

    try testing.expectEqual(@as(usize, 2), segments.items.len);
    try testing.expectEqual(ca, segments.items[0].country);  // CA wins 0-255
    try testing.expectEqual(us, segments.items[1].country);  // US gets 256-511
}
```

**When to add a spec test:**
- A new feature is added (e.g., country grouping)
- An existing behavior needs explicit documentation
- A bug reveals the spec was incomplete or wrong

**Count target:** ~20 tests for the current feature set.

---

## Tier 2: IAE (KDT/TDD)

**Question:** Does each function handle all edge cases correctly?

**Methodologies:** Keyword-Driven, Test-Driven.

**Structure:** Table-driven Input-Action-Expectation. Pure functions only
(no I/O, no allocators). Every row is a self-contained test case with a
unique ID.

**Files:** `test/data/*.zig` (IAE tables), `test/*_spec.zig` (runners)

### IAE row format

```zig
// test/data/csv_parsing.zig
pub const CsvRow = struct {
    id: []const u8,
    given: []const u8,
    input: []const u8,
    expected: ?struct { start: u64, end: u64, country: u16 },
};

pub const csv_rows = [_]CsvRow{
    .{ .id = "CSV-001",
       .given = "well-formed line with start, end, 2-char country",
       .input = "16777216,16777471,AU",
       .expected = .{ .start = 16777216, .end = 16777471, .country = 0x4155 } },
    .{ .id = "CSV-007",
       .given = "line with \\r suffix strips carriage return from country",
       .input = "16777216,16777471,AU\r",
       .expected = .{ .start = 16777216, .end = 16777471, .country = 0x4155 } },
};
```

### IAE runner format

```zig
// test/csv_parsing_spec.zig
const parser = @import("../src/parser.zig");
const data = @import("data/csv_parsing.zig");
const helpers = @import("_helpers.zig");

test "csv parsing: all edge cases pass" {
    for (&data.csv_rows) |row| {
        const result = parser.parseCsvLine(u32, row.input, &helpers.identity_map);
        if (row.expected) |exp| {
            const r = result orelse {
                std.debug.print("FAIL {s}: expected Some, got null\n", .{row.id});
                return error.TestFailed;
            };
            try testing.expectEqual(exp.start, r.start);
            try testing.expectEqual(exp.end, r.end);
            try testing.expectEqual(exp.country, r.country);
        } else {
            try testing.expect(result == null);
        }
    }
}
```

### ID prefix convention

| Prefix | Data file |
|--------|-----------|
| `CSV-` | `test/data/csv_parsing.zig` |
| `STA-` | `test/data/static_parsing.zig` |
| `CIDR-` | `test/data/cidr_gen.zig` |
| `IP-` | `test/data/ip_format.zig` |
| `FLT-` | `test/data/flatten.zig` |
| `PL-` | `test/data/pipeline.zig` |
| `ARG-` | `test/data/config.zig` (arg parsing) |
| `GRP-` | `test/data/config.zig` (group parsing) |
| `FIL-` | `test/data/config.zig` (filter parsing) |
| `SW-` | `test/data/swar.zig` |
| `RAM-` | `test/data/nginx.zig` |
| `PRP-` | `test/properties.zig` |

**When to add an IAE row:**
- A new code path is added to a function
- A bug is found (add row FIRST, then fix — TDD loop)
- An edge case is identified during code review

**Count target:** ~90 rows total (all existing 119 tests migrate to IAE rows).

---

## Tier 3: Scenario (STDD)

**Question:** Do the components work together in realistic multi-step workflows?

**Methodology:** Scenario-Driven.

**Structure:** Sequential Arrange-Act-Assert across pipeline stages. Each
scenario tests a complete workflow (parse → flatten → filter → group →
CIDR gen). Uses `TestEnv` and calls `processStream`.

```zig
// test/scenario/basic_pipeline.zig
test "SCENARIO-001: CSV + static + group produces correct output" {
    var env = TestEnv.init();
    defer env.deinit();

    // Step 1: Parse groups
    try config_mod.parseGroupLine("EU:FR,DE", &env.country_map);
    try config_mod.parseGroupLine("NA:US,CA", &env.country_map);

    // Step 2: Run pipeline with filter=NA only
    const filter_na = [_]bool{false} ** 65536;
    filter_na[(@as(u16, 'U') << 8) | @as(u16, 'S')] = true;
    filter_na[(@as(u16, 'C') << 8) | @as(u16, 'A')] = true;

    const result = try pipeline_mod.processStream(
        u32, std.testing.io, "test/geo-whois-asn-country-ipv4-num.csv",
        &.{}, &env.seen_countries, &env.aw.writer,
        testing.allocator, &env.country_map, &filter_na,
    );

    // Step 3: Verify output
    const output = env.aw.writer.buffered();
    try testing.expect(output.len > 0);
    // Every line should be NA or RFC1918
}
```

**When to add a scenario test:**
- A new feature interacts with existing features
- A cross-feature integration bug is found
- A spec test covers the happy path, but the scenario covers the real-world path

**Count target:** ~8 scenarios for the current feature combinations.

---

## Tier 4: Property (PDD/MDD)

**Question:** Do the mathematical invariants hold for all inputs?

**Methodologies:** Property-Driven, Model-Driven.

**Structure:** Generate random inputs, assert invariants on output. Uses
`std.testing.random` or seeded deterministic generation.

```zig
// test/properties.zig
test "PROP-001: CIDR blocks are power-of-2 aligned" {
    var rng = std.Random.DefaultPrng.init(42);
    const rand = rng.random();

    for (0..1000) |_| {
        const start = rand.int(u32);
        const end = start + rand.int(u32) % 65536;
        const result = cidr_mod.computeCidrBlock(u32, start, end);
        try testing.expect(result.addr & (result.step - 1) == 0);
    }
}

test "PROP-002: CIDR output covers exactly the input address span" {
    // sum(CIDR sizes) == input span
}

test "PROP-003: no two output CIDRs overlap" {
    // pairwise intersection check
}
```

**When to add a property test:**
- An algorithm has mathematical guarantees (CIDR generation, sweep-line)
- A bug was caused by an invariant violation
- The function is performance-sensitive and might be optimized later

**Count target:** ~6 property checks.

---

## Tier 5: Regression

**Question:** Has a previously fixed bug reappeared?

**Structure:** Not executable tests. A documentation file that maps IAE row
IDs to bug descriptions. Ensures that when an IAE row fails, the engineer
can immediately understand what real-world issue it protects.

```zig
// test/regressions.zig
/// Regression registry.
///
/// Each entry links a past bug to the IAE rows that protect against it.
/// When an IAE row fails, look up its ID here to understand the context.

pub const Entry = struct {
    id: []const u8,
    date: []const u8,       // YYYY-MM-DD
    description: []const u8,
    cause: []const u8,
    fix_commit: ?[]const u8,
    protected_by: []const []const u8,  // IAE row IDs
};

pub const entries = [_]Entry{
    .{
        .id = "REG-2026-06-05-01",
        .date = "2026-06-05",
        .description = "CR character not stripped from country code in CSV line",
        .cause = "parseCsvLine checked for \\r on the full line but country extraction happened after trim",
        .fix_commit = null,  // filled in when the fix is committed
        .protected_by = &.{"CSV-007"},
    },
    .{
        .id = "REG-2026-06-05-02",
        .date = "2026-06-05",
        .description = "Short country code (<2 chars) yields c_val=0 instead of skipping",
        .cause = "country.len < 2 check was missing, 0-initialized field used as-is",
        .fix_commit = null,
        .protected_by = &.{"CSV-003"},
    },
};
```

**When to add a regression entry:**
- A bug is fixed and IAE rows are added to protect against it
- A customer or CI reports a reoccurrence

**Count target:** One entry per fixed bug, growing over time.

---

## File Structure (complete)

```
test/
  tests.zig                       Root — imports all spec/runner files
  _helpers.zig                    TestEnv, setupMapsInline, identity_map, allocator helpers
  regressions.zig                 Tier 5 — bug registry

  TIER 1 — SPEC
  spec/
    csv_parsing.zig               CSV → IPRange acceptance
    static_parsing.zig            Static file → StaticCidr acceptance
    flatten.zig                   Collision/merge acceptance
    cidr_gen.zig                  CIDR generation acceptance
    ip_format.zig                 IPv4/v6 formatting acceptance
    config.zig                    Arg parsing + group/filter acceptance
    pipeline.zig                  Full pipeline acceptance
    swar.zig                      SWAR acceptance
    nginx.zig                     RAM estimation acceptance

  TIER 2 — IAE TABLES
  data/
    csv_parsing.zig               IAE rows: parseCsvLine (10)
    static_parsing.zig            IAE rows: parseStaticLine (10)
    cidr_gen.zig                  IAE rows: rangeToCidrs + computeCidrBlock (16)
    ip_format.zig                 IAE rows: formatIPv4/6Line + isPrivateIPv4 (8)
    flatten.zig                   IAE rows: flatten output (4)
    pipeline.zig                  IAE rows: filterSegments (6)
    config.zig                    IAE rows: parseArgList + group/filter (29)
    swar.zig                      IAE rows: findByte + findTwoBytes (22)
    nginx.zig                     IAE rows: estimateRamBytes + estimateRamMB (9)

  TIER 2 — RUNNERS (one per data file, pairs with spec)
  csv_parsing_spec.zig            Runner: loops csv_parsing rows
  static_parsing_spec.zig         Runner: loops static_parsing rows
  cidr_gen_spec.zig               Runner: loops cidr_gen rows
  ip_format_spec.zig              Runner: loops ip_format rows
  flatten_spec.zig                Runner: loops flatten rows
  pipeline_spec.zig               Runner: loops pipeline rows
  config_spec.zig                 Runner: loops config rows
  swar_spec.zig                   Runner: loops swar rows
  nginx_spec.zig                  Runner: loops nginx rows

  TIER 3 — SCENARIOS
  scenario/
    basic_pipeline.zig            CSV → Nginx output
    filtered_pipeline.zig         CSV + filter → filtered output
    grouped_pipeline.zig          CSV + group → grouped output
    filter_then_group.zig         Filter after group remap (bug regression)
    static_override.zig           CSV + static HOLE → correct gaps

  TIER 4 — PROPERTIES
  properties.zig                  Invariant checks (CIDR alignment, no-overlap, coverage)
```

Total: ~38 files (including helpers, root, and all tiers).

---

## Visibility Changes Required in `src/`

| File | Change | Reason |
|---|---|---|
| `config.zig:225` | `fn parseArgList` → `pub fn parseArgList` | Tested via IAE tables from external files. Legitimate public API. |
| `config.zig:191` | Move `setupMapsInline` to `test/_helpers.zig` | Pure test helper, zero production callers. |
| `pipeline.zig:119` | Move `TestEnv` to `test/_helpers.zig` as `pub` | Test infrastructure, not production code. |
| `config.zig:213` | Move `SliceIter` with `parseArgList` | Internal helper for parseArgList. |

No other source files change. `cliPrint` stays in config.zig (production
detail, detected by `builtin.is_test`).

---

## build.zig Changes

```zig
const test_exe = b.addTest(.{
    .name = "ngc-test",
    .root_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "test/tests.zig" },
        .target = target,
        .optimize = optimize,
    }),
});
test_exe.root_module.addOptions("build_options.zig", options);
```

Relative `@import("../src/parser.zig")` paths in test files resolve
correctly because Zig deduplicates module instances by canonical path.

---

## Makefile Targets

```makefile
# Current:
test:    build test          # will run all tiers

# Add:
test-t1:                     # Tier 1 only (spec) — fastest feedback
test-t2:                     # Tier 2 only (IAE) — TDD cycle
test-all:  test              # all 5 tiers including properties
```

---

## Workflow Rules

### For AI agents (add to AGENTS.md)

1. **Property-first optimization**: Before optimizing any function, run
   Tier 2 (IAE) to verify basic correctness. After optimizing, run Tier 4
   (properties) with `--fuzz-runs 10000` to verify invariants were
   preserved.

2. **Regression-aware changes**: When modifying a function, check
   `test/regressions.zig` for entries whose `protected_by` includes IAE
   rows referencing that function. Ensure those rows still pass.

3. **TDD loop for bugs**: When a bug is found, add the IAE row FIRST,
   run Tier 2 to confirm it fails, fix the code, run Tier 2 to confirm
   it passes. Then add the regression entry.

### For humans

4. **Spec-first for new features**: Start with the Tier 1 spec test that
   defines the behavior. Then implement. Then add IAE rows for edge cases.

5. **Scenario test before release**: Tag a new version. Run Tier 3 scenarios
   to confirm no cross-feature regression.

---

## Migration Order

| Step | Action | Files changed | Tests pass |
|---|---|---|---|
| 1 | Create `test/tests.zig` + `test/_helpers.zig` + `test/regressions.zig` | 3 new | 119 (in src) |
| 2 | Move `TestEnv`, `setupMapsInline`, `SliceIter` to `_helpers.zig` | `src/pipeline.zig`, `src/config.zig`, `test/_helpers.zig` | 119 (in src) |
| 3 | Make `parseArgList` `pub` | `src/config.zig` | 119 (in src) |
| 4 | Create all `test/data/*.zig` with IAE tables from existing tests | 9 new | 119 (in src) |
| 5 | Create all `test/*_spec.zig` runners + `test/spec/*.zig` specs | ~20 new | 119 (+ new passing) |
| 6 | Point `build.zig` at `test/tests.zig` | `build.zig`, `test/tests.zig` | 119 (all migrated) |
| 7 | Remove `test {}` blocks from `src/*.zig` | 8 files | 119 (in test/) |
| 8 | Run `make check` | — | All tiers pass |
| 9 | Add `test/scenario/*.zig` (create Tier 3) | 5 new | All tiers pass |
| 10 | Add `test/properties.zig` (create Tier 4) | 1 new | All tiers pass |
| 11 | Update `AGENTS.md` with workflow rules | 1 file | — |
| 12 | Final `make test-all` + commit | — | All 5 tiers, all pass |

---

## Adding a New Test (by tier)

1. **Spec**: Add a test block to `test/spec/<module>.zig`. Use AAA.
2. **IAE**: Add a row to `test/data/<module>.zig`. Runner already loops over all rows.
3. **Scenario**: Add a file to `test/scenario/`. Import in `test/tests.zig`.
4. **Property**: Add a test block to `test/properties.zig`.
5. **Regression**: Add an entry to `test/regressions.zig`.

---

## Decision Record

- **IAE over AAA for pure functions**: IAE is declarative (what), AAA is
  imperative (how). Pure functions only need what.
- **AAA retained for flatten + processStream**: These need allocators,
  ArrayLists, writers — imperative setup required.
- **Properties as separate tier (not mixed into specs)**: Invariant checks
  are conceptually different from acceptance criteria. Different failure
  modes, different audience.
- **Spec tests call APIs directly (not CLI)**: Keeps them fast (ms not s),
  no build step. CLI testing is Tier 3 (scenarios).
- **IAE tables in separate `_data.zig` files (not inline in runners)**:
  Separates specification data from test execution logic. Data can be
  reused by property tests or alternative runners.
- **Relative `@import("../src/...")` paths over build.zig module aliases**:
  Build.zig stays simple (no per-module imports needed). Zig deduplicates
  module instances by canonical path, so reimports don't create type
  mismatches.
- **Regressions as doc-only file (not executable)**: A data table is
  self-documenting and machine-searchable. No runtime overhead.
- **Five tiers not three**: The original 3-tier plan (Spec/IAE/Property)
  missed scenario (STDD) and regression tracking. Five covers all nine
  methodologies with no overlap.
