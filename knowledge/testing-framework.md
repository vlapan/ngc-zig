# Five-Tier Testing Framework
Updated: 2026-06-12

A reusable testing architecture for projects that want systematic, maintainable
test coverage. Each tier answers a distinct question and catches what the others
miss. Tiers are ordered by stability — spec tests change only when requirements
change, IAE tables grow with every edge case discovered.

```
TIER 1  Spec (SDD/ATDD/BDD/FDD/DDD)   — what must work, per feature
TIER 2  IAE (KDT/TDD)                  — edge cases, table-driven
TIER 3  Scenario (STDD)                — multi-step realistic workflows
TIER 4  Property (PDD/MDD)             — mathematical invariants
TIER 5  Regression                      — bug history, cross-referenced
```

Tier 1 failures invalidate lower tiers (wrong behavior). Tiers should run in
order. The framework is language-agnostic — examples use pseudocode.

---

## Tier 1: Spec (SDD/ATDD/BDD/FDD/DDD)

**Question:** Does the system do what it must do?

**Methodologies:** Spec-Driven, Acceptance Test-Driven, Behavior-Driven,
Feature-Driven, Domain-Driven.

**Structure:** One spec test per core behavior. Imperative Arrange-Act-Assert
style using the most direct public API (never CLI — that's Tier 3).

**When to add a spec test:**
- A new feature is added
- An existing behavior needs explicit documentation
- A bug reveals the spec was incomplete or wrong

**Location:** `spec/<stage>.zig` (e.g. `spec/default/input.zig`)

**Count guideline:** ~1-3 per stage, covering each distinct behavior.

---

## Tier 2: IAE (KDT/TDD)

**Question:** Does each function handle all edge cases correctly?

**Methodologies:** Keyword-Driven, Test-Driven.

**Structure:** Table-driven Input-Action-Expectation. Pure functions only
(no I/O, no allocators). Every row is a self-contained test case with a
unique ID. Runner loops over rows — one test entry per table, not per row.

```zig
// spec/default/input.zig  (IAE data inline, runner inline — merged per stage)
const IAE = struct {
    id: []const u8,
    given: []const u8,
    input: []const u8,
    expected: ?ParsedValue,
};

const iae_rows = [_]IAE{
    .{ .id = "SCN-001",
       .given = "well-formed key=value",
       .input = "key=value",
       .expected = .{ .key = "key", .value = "value" } },
    .{ .id = "SCN-002",
       .given = "empty value after equals",
       .input = "key=",
       .expected = .{ .key = "key", .value = "" } },
};

test "IAE: input stage edge cases" {
    for (&iae_rows) |row| {
        const result = parse(row.input);
        if (row.expected) |exp| {
            try expectEqual(exp.key, result.key);
            try expectEqual(exp.value, result.value);
        } else {
            try expect(result == null);
        }
    }
}
```

### ID prefix convention

| Prefix | Data file | Module |
|--------|-----------|--------|
| `SCN-` | `spec/default/input.zig` | Byte scanning / input parsing |
| `RSV-` | `spec/default/resolve.zig` | Conflict resolution (flatten) |
| `OUT-` | `spec/default/output.zig` | CIDR block generation / formatting |
| `RUN-` | `spec/default/run.zig` | Pipeline orchestration |
| `OPT-` | `spec/default/options.zig` | CLI argument / map setup |
| `PRP-` | `spec/properties.zig` | Property tests |

**When to add an IAE row:**
- A new code path is added to a function
- A bug is found (add row FIRST, then fix — TDD loop)
- An edge case is identified during code review

**Location:** `spec/<stage>.zig` (tables + runner merged per stage)

**Count guideline:** One row per code path + edge case. ~10-20 rows per module.

---

## Tier 3: Scenario (STDD)

**Question:** Do the components work together in realistic multi-step workflows?

**Methodology:** Scenario-Driven.

**Structure:** Sequential Arrange-Act-Assert across multiple components. Each
scenario tests a complete workflow from input to output, exercising real
pipeline stages. Requires test infrastructure (fixtures, mock I/O, shared
state).

```zig
// spec/scenario/scenario_001.zig
test "SCENARIO-001: parse then format roundtrip" {
    var env = TestEnv.init();
    defer env.deinit();

    const input = "hello=world";
    const parsed = try parse(input);
    try env.buffer.append(parsed);

    const output = try format(env.buffer);
    try expectEqual("hello -> world\n", output);
}
```

**When to add a scenario test:**
- A new feature interacts with existing features
- A cross-feature integration bug is found
- A spec test covers the happy path, but the scenario covers the real-world path

**Location:** `spec/scenario/<workflow>.zig`

**Count guideline:** ~1-2 per supported workflow combination.

---

## Tier 4: Property (PDD/MDD)

**Question:** Do the mathematical invariants hold for all inputs?

**Methodologies:** Property-Driven, Model-Driven.

**Structure:** Generate random inputs, assert invariants on output. Uses
seeded deterministic generation for reproducibility.

```zig
// spec/properties.zig
test "PROP-001: sort output is always ordered" {
    var rng = Rng.seeded(42);
    for (0..1000) |_| {
        var items = generateRandomArray(rng);
        sort(&items);
        for (items, items[1..]) |a, b| {
            try expect(a <= b);
        }
    }
}

test "PROP-002: sort preserves element count" {
    var rng = Rng.seeded(42);
    for (0..1000) |_| {
        const items = generateRandomArray(rng);
        const count = items.len;
        sort(items);
        try expectEqual(count, items.len);
    }
}
```

**When to add a property test:**
- An algorithm has mathematical guarantees (ordering, alignment, idempotence)
- A bug was caused by an invariant violation
- The function is performance-sensitive and might be optimized later

**Location:** `spec/properties.zig`

**Count guideline:** ~1-5 per module with algorithmic guarantees.

---

## Tier 5: Regression

**Question:** Has a previously fixed bug reappeared?

**Structure:** Not executable tests. A documentation file that maps IAE row
IDs to bug descriptions. Ensures that when an IAE row fails, the engineer
can immediately understand what real-world issue it protects.

```zig
// spec/regressions.zig
pub const Entry = struct {
    id: []const u8,
    date: []const u8,
    description: []const u8,
    cause: []const u8,
    fix_commit: ?[]const u8,
    protected_by: []const []const u8,
};

pub const entries = [_]Entry{
    .{
        .id = "REG-2026-01-15-01",
        .date = "2026-01-15",
        .description = "Empty input causes index out of bounds",
        .cause = "input.len check was missing before indexing",
        .fix_commit = "abc123",
        .protected_by = &.{"PAR-002"},
    },
};
```

**When to add a regression entry:**
- A bug is fixed and IAE rows are added to protect against it
- A customer or CI reports a reoccurrence

**Location:** `spec/regressions.zig`

**Count guideline:** One entry per fixed bug, growing over time.

---

## Directory Structure

```
spec/main.zig [ROOT]              Test runner entry point

  TIER 1+2 — SPEC + IAE (merged per stage)
  default/                        AAA + IAE tables + runner inline per pipeline stage
    input.zig                     Byte scanning, integer parsing, CSV/static line parsing
    resolve.zig                   Conflict resolution (flatten, filterSegments)
    output.zig                    CIDR block generation, formatting, private filtering
    run.zig                       Pipeline orchestration (processStream)
    options.zig                   CLI argument parsing, map setup

  TIER 3 — SCENARIOS
  scenario/                       Multi-step end-to-end workflow tests
    scenario_001.zig
    ...

  TIER 4 — PROPERTIES
  properties.zig                  Random-input invariant checks (u32 + u128)

  TIER 5 — REGRESSION
  regressions.zig                 Bug registry

  TIER 0 — FIXTURES
  fixtures/                       CSV data files used by scenario tests
    ipv4.csv
    ipv6.csv
    ...

  TIER 0 — PERF BENCHMARKS
  perf.zig                        Benchmark runner entry point
  data/
    perf_parse.zig                Scan + parseInt benchmarks (input stage)
    perf_output.zig               Block math + format benchmarks (output stage)
  snapshots/
    perf-baselines.snap           Committed baseline deltas
```

---

## Workflow Rules

### For AI agents

1. Run the full test suite before and after any change.
2. **Property-first optimization**: Before optimizing any function, run
   Tier 1+2 to verify correctness. After optimizing, run Tier 4 properties
   to verify invariants were preserved.
3. **Regression-aware changes**: When modifying a function, check
   `spec/regressions.zig` for entries whose `protected_by` includes IAE
   rows referencing that function. Ensure those rows still pass.
4. **IAE-first bug fixes**: When a bug is found, add the IAE row FIRST
   to the stage's merged file (e.g. `spec/default/input.zig`), run tests
   to confirm it fails, fix the code, run tests to confirm it passes.
   Then add a regression entry.

### For humans

5. **Spec-first for new features**: Start with a spec test in
   the stage's merged file (e.g. `spec/default/input.zig`). Then
   implement. Then add IAE rows for edge cases in the same file.
6. **Scenario test before release**: Tag a new version. Run Tier 3
   scenarios to confirm no cross-feature regression.

---

## Decision Record

- **IAE over AAA for pure functions**: IAE is declarative (what), AAA is
  imperative (how). Pure functions only need what.
- **AAA retained for allocation-heavy / I/O functions**: Functions that
  need allocators, file I/O, or writers need imperative Arrange-Act-Assert.
- **Properties as separate tier (not mixed into specs)**: Invariant checks
  are conceptually different from acceptance criteria. Different failure
  modes, different audience.
- **Spec tests call APIs directly (not CLI)**: Keeps them fast (ms not s),
  no build step. CLI testing is Tier 3 (scenarios).
- **IAE tables in separate data files (not inline in runners)**: Separates
  specification data from test execution logic. Data can be reused by
  property tests or alternative runners.
- **Regressions as doc-only file (not executable)**: A data table is
  self-documenting and machine-searchable. No runtime overhead.
- **Five tiers not three**: The 3-tier plan (Spec/IAE/Property) misses
  scenario (STDD) and regression tracking. Five covers all nine
  methodologies with no overlap.
- **Stage-level test runner**: Place the test runner at `spec/main.zig`
  to keep all testing code under `spec/` while avoiding module
  sandboxing issues with relative imports.

---

## Adding a New Test (by tier)

1. **Spec + IAE** (Tiers 1+2): Add AAA tests and IAE rows to the
   stage's merged file (e.g. `spec/default/input.zig`). Runners are
   inline — no separate file needed.
2. **Scenario** (Tier 3): Add a file to `spec/scenario/`. Register in
   `spec/main.zig`.
3. **Property** (Tier 4): Add a test block to `spec/properties.zig`.
4. **Regression** (Tier 5): Add an entry to `spec/regressions.zig`.
