# Knowledge Index
Updated: 2026-05-13


## Rules
- Pure Zig 0.16.0, NO C interop
- No `-lc` link flag
- Read changelogs from `ZIG-CHANGELOG-*.md`
- Use real test data from `test/geo-whois-asn-country-ipv4-num.csv` and `test/geo-whois-asn-country-ipv6-num.csv`
- Always verify output changes (`git diff test/output.txt`) to track expected vs unexpected changes before committing code
- **Validate Before Implementing:** Before starting work on an item from `knowledge/tasks.md` (especially specific code optimizations), quickly `grep` or `cat` the relevant source code to verify the targeted logic still exists in the assumed state. Code evolves, and backlog plans can become obsolete or conceptually flawed over time.
- Keep state files updated frequently
- Commit incrementally
- Write state frequently for session survival
- **Telemetry Validity**: Always ensure that console outputs and tracking metrics (`Stats`) accurately reflect the current physical architecture. If a major pipeline refactor happens (e.g. moving from Trie-based collision resolution to Sweep-Line pre-flattening), the CLI output *must* be updated to track the new distinct phases of the pipeline so the user understands exactly what the machine is doing.


## Files
- `knowledge/tasks.md` - The single source of truth for the project roadmap, open tasks, backlog, and feature ideas. **Must be read at the start of every session.**
- `knowledge/release-process.md` - The strict, step-by-step checklist required for tagging and deploying new versions.
- `knowledge/zig-api.md` - Zig 0.16.0 API patterns and gotchas
- `knowledge/architecture.md` - Core system design and radix trie behavior
- `knowledge/data-analysis.md` - Protocol for analyzing dirty upstream data and overlaps
- `notes/` - Daily session logs with progress. These are strictly append-only historical narratives showing *what was done*. Do NOT trap open tasks or future backlogs in daily notes. Conversely, do NOT put detailed task specifications in `tasks.md`. `knowledge/tasks.md` must be strictly limited to a concise 1-line checklist. ALL rationale, examples, and detailed specifications MUST go into the daily `notes/YYYY-MM-DD.md` file, which is then linked at the end of the 1-line task (e.g., `(Details: notes/2026-05-14.md)`).
- **Benchmarking & Profiling Rules**:
  - Whenever performance optimizations are made, you must use the `make bench` command.
  - `make bench` will automatically compile a clean release binary, run a Cold Run (to capture I/O overhead), 3 Hot Runs (to capture CPU efficiency), format the output into a clean table, and verify via `git diff` that `test/output.txt` was not corrupted.
  - The output of `make bench` is automatically appended to `benchmarks.log`.
  - Do NOT manually run `/usr/bin/time -al` and paste walls of raw output into notes or chat. Always use `make bench` for performance proofs.
  - When committing an optimization, ensure you commit the changes to `benchmarks.log` alongside your source code to permanently document the performance improvement.
