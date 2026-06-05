# Flow Review: TDD, Testability & Separation of Concerns

Updated: 2026-06-05

## Principle

Every commit must produce testable code. "Testable" means the new logic can be verified
without real files, network, or external state — just in-memory structs and pure functions.

## Taxonomy

Every public function falls into one of three categories:

### 1. Pure function
No I/O, no writer, no allocator (or allocator only for test-predictable operations).
Already unit-testable with zero infrastructure. Goal: keep it that way.

Examples: `isPrivateIPv4`, `fastParseInt`, `parseCsvLine`, `filterSegments`, `swar.findByte`

### 2. I/O function with extractable pure core
File ops, writer calls, mmap — but contains a block of transform logic that is
independent of the I/O. The pure core must be extracted into a standalone function
WITH its own unit tests before the I/O wrapper is committed.

Required extraction pattern:
```
I/O wrapper:  open, mmap, iterate, call pure function, write results
Pure core:    transform([]const u8 input) ?Result   — test this
```

### 3. I/O function where extraction is not beneficial
The function's purpose IS the I/O (main, processStream orchestration), or the writer
pattern already allows complete testing through AllocatingWriter.

## Workflow

### Before commit
1. `git diff --stat` — review every changed file
2. For each changed function: check its taxonomy
3. If Category 2 and pure core NOT yet extracted → STOP, extract first
4. Write tests BEFORE the extraction (TDD: see the failure, then make it pass)
5. Verify: `zig build test` passes

### After commit (when reviewing the diff)
1. Same taxonomy check on the commit diff
2. Look for untested branches in the diff (if-else, switch, early returns)
3. Check that test names exercise: normal path, edge case, error path
4. No I/O in unit tests — if the test creates files, it's an integration test

## When extraction adds zero value

- Writer is the ONLY consumer and writer-allocator testing already provides coverage
- The "pure" part is a trivial field access or arithmetic
- Performance: extracted form would require O(N) allocation where writer avoids it

## State of this project (2026-06-05)

After the initial extraction pass, all Category-2b functions have been addressed:

| File | Function | Extracted pure core | Tests |
|------|----------|-------------------|-------|
| `parser.zig` | `parseFile` | `parseCsvLine` | 8 |
| `parser.zig` | `appendStaticFile` | `parseStaticLine` | 5 |
| `pipeline.zig` | `processStream` | `filterSegments` | 4 |
| `ip.zig` | `formatIPv4`/`formatIPv6` | `formatIPv4Line`/`formatIPv6Line` | 5 |
| `cidr.zig` | `rangeToCidrs` | `computeCidrBlock` | 5 |

No Category-2b functions remain. New code must not introduce new ones.
