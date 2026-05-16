# Knowledge Index
Updated: 2026-05-13


## Rules
- **Conventional Commits:** All commit messages MUST strictly adhere to the Conventional Commits specification. See `knowledge/commit-conventions.md`.
- Pure Zig 0.16.0, NO C interop
- No `-lc` link flag
- Read changelogs from `ZIG-CHANGELOG-*.md`
- Use real test data from `test/geo-whois-asn-country-ipv4-num.csv` and `test/geo-whois-asn-country-ipv6-num.csv`
- Always verify output changes (`git diff test/output.txt`) to track expected vs unexpected changes before committing code
- **Validate Before Implementing:** Before starting work on an item from `knowledge/tasks.md` (especially specific code optimizations), quickly `grep` or `cat` the relevant source code to verify the targeted logic still exists in the assumed state. Code evolves, and backlog plans can become obsolete or conceptually flawed over time.
- **Mechanical Sympathy Pre-Check:** Before implementing any performance optimization that swaps a standard algorithm (e.g., `std.mem.sort`) for a theoretically "faster" Big-O algorithm (e.g., Radix Sort), you MUST perform a back-of-the-napkin hardware calculation in your reasoning. Calculate the exact struct byte sizes, the number of elements, the required allocations, and the number of memory passes. If the new algorithm requires dropping out of in-place `O(N log N)` into out-of-place memory allocations that exceed typical L2/L3 cache sizes (~8-12MB), you must reject the task without implementing it. Big-O notation is subservient to memory bandwidth and cache locality.
- Keep state files updated frequently
- Commit incrementally
- Write state frequently for session survival
- **Atomic Commits:** Each commit MUST contain exactly one logical change. Never bundle unrelated changes together. Split code changes, state updates (tasks.md, notes), and benchmark logs into separate commits. Example: a code optimization gets its own `perf(...)` commit, task validation gets a `docs(tasks)` commit, and benchmark logs get committed alongside their corresponding code change.
- **Explicit Review Gates:** User constraints always override kernel defaults. If the user requests a review, uses phrases like "report before commit", or asks to "see it first", you MUST halt execution, present the benchmark/stats results, and enter a "Review Gate". Do NOT execute `git commit` or `make tag` until the user explicitly approves the reported changes. **CRITICAL: NEVER print the actual code diffs (`git diff`) in the chat. The user will review the diffs themselves in their editor.**
- **Holistic Benchmark Reporting:** Never cherry-pick positive metrics. When comparing `make bench` runs, you must actively scan for and explicitly report **regressions** (e.g., increased Max RSS, higher Context Switches) just as prominently as improvements. Every trade-off must be explicitly acknowledged.
- **Anomaly Pre-Commit Verification:** Before running `git commit`, you must verify that no unintended side-effects were introduced. This explicitly includes checking the binary size (`ls -lh zig-out/bin/ngc`) and reviewing the `make bench` output specifically for bloated executable sizes, memory leaks, or missing output phases.
- **Explicit Release Authorization:** Never execute deployment or release scripts (e.g., `make tag`) autonomously. Modifying and committing code is permitted, but cutting a new semantic version tag requires explicit, unambiguous authorization from the user.
- **Coupled Artifact Integrity:** Never split coupled state across tracked and untracked git boundaries. If a dataset (e.g., CSV) is tracked in git, its associated cache metadata (e.g., `.etag`) MUST also be tracked alongside it.
- **Knowledge Discovery Protocol:** When a new quirk, API change, or useful insight is discovered through trial and error (e.g., searching source code), you must IMMEDIATELY append it to today's daily note under a `### 🧠 KNOWLEDGE_DISCOVERY` header. This ensures the insight survives context compaction. Before moving to a new major task or ending the session, you must process these tagged blocks and migrate them into the appropriate permanent reference files (e.g., `knowledge/zig-api.md`).
- **Task Table Generation:** Whenever the user explicitly asks to print a "task table" (or variations thereof), the table must include a "Score" column. The score should be calculated based on an estimation of three metrics: lines of code changed (impact on codebase), implementation difficulty, and expected improvement/performance impact. The table must display these metrics alongside the calculated score (e.g., Score = Improvement / (Difficulty * LOC)).
- **Telemetry Validity**: Always ensure that console outputs and tracking metrics (`Stats`) accurately reflect the current physical architecture. If a major pipeline refactor happens (e.g. moving from Trie-based collision resolution to Sweep-Line pre-flattening), the CLI output *must* be updated to track the new distinct phases of the pipeline so the user understands exactly what the machine is doing.



## Files
- `knowledge/tasks.md` - The single source of truth for the project roadmap, open tasks, backlog, and feature ideas. **Must be read at the start of every session.**
- `knowledge/release-process.md` - The strict, step-by-step checklist required for tagging and deploying new versions.
- `knowledge/zig-api.md` - Zig 0.16.0 API patterns and gotchas
- `knowledge/architecture.md` - Core system design and CIDR generation pipeline
- `knowledge/data-analysis.md` - Protocol for analyzing dirty upstream data and overlaps
- `notes/` - Daily session logs with progress. These are strictly append-only historical narratives showing *what was done*. Do NOT trap open tasks or future backlogs in daily notes. Conversely, do NOT put detailed task specifications in `tasks.md`. `knowledge/tasks.md` must be strictly limited to a concise 1-line checklist. ALL rationale, examples, and detailed specifications MUST go into the daily `notes/YYYY-MM-DD.md` file, which is then linked at the end of the 1-line task (e.g., `(Details: notes/2026-05-14.md)`).
- **Benchmarking & Profiling Rules**:
  - Whenever performance optimizations are made, you must use the `make bench` command.
  - `make bench` will automatically compile a clean release binary, run a Cold Run (to capture I/O overhead), 3 Hot Runs (to capture CPU efficiency), format the output into a clean table, and verify via `git diff` that `test/output.txt` was not corrupted.
  - The output of `make bench` is automatically appended to `benchmarks.log`.
  - Do NOT manually run `/usr/bin/time -al` and paste walls of raw output into notes or chat. Always use `make bench` for performance proofs.
  - When committing an optimization, ensure you commit the changes to `benchmarks.log` alongside your source code to permanently document the performance improvement.
