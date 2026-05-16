# Project Release & Deployment Protocol
Updated: 2026-05-14

The entire release process has been fully automated to ensure maximum safety, mathematical correctness, and detailed tracking.

When you are ready to cut a new release, simply ensure your working directory is clean (all optimizations and features committed) and run:

```bash
make tag
```

### What `make tag` does automatically:
1. **Safety Check:** Enforces a perfectly clean git working directory.
2. **Version Bump:** Prompts for the next semantic version and updates `build.zig.zon`.
3. **Format & Test:** Runs `make fmt` and `make test`.
4. **Benchmark Verification:** Runs `make bench` to compile the `-Dstamp=true` release artifact and perform cold/hot benchmarks.
5. **Logic Validation:** Runs `git diff test/output.txt`. If the output mathematically changed, it flags it as a `[NOTICE]` and pauses to ask you for explicit confirmation.
6. **Annotation Extraction:** Automatically parses `git log` since the last tag to generate a bulleted list of all features, perf, and chore commits.
7. **Commit & Tag:** Commits the version bump and `benchmarks.log`, creates the **annotated tag** with the embedded changelog, and pushes `origin master --follow-tags` to deploy it.

### CHANGELOG.md Update
After a successful tag release, update `CHANGELOG.md` at the project root with a human-readable summary of what changed and why. This is for humans, not a commit log.

Format:
```markdown
## [v1.0.14] - 2026-05-16

### Performance
- Eliminated the recursive Trie entirely, replacing it with a direct CIDR generation from the sweep-line algorithm. This cut instructions by 52% and reduced memory usage by 34%, bringing total runtime from 80ms down to 16ms for the flatten phase.
- Replaced linear comma scanning with SWAR bit-manipulation, finding delimiters 8 bytes at a time. Saved 2.7% total instructions in the parsing phase.

### Reliability
- Added input validation to reject malformed CSV lines instead of silently producing incorrect output.
- Fixed CLI argument parsing to fail on unrecognized flags instead of ignoring them and producing confusing downstream errors.

### Features
- Added country filtering (`--filter`) to allowlist specific countries before processing.
- Added country grouping (`--group`) to aggregate multiple countries into regional blocks (e.g., `EU`).

### Maintenance
- Removed ~250 lines of dead code from abandoned Trie implementation.
- Updated Nginx RAM footprint heuristic from 64B to 97B per CIDR based on actual profiling measurements.
```

Rules:
- Write for humans: explain **what changed** and **why it matters**, not what commits were made
- Group by impact area: Performance, Reliability, Features, Maintenance
- Include concrete numbers where available (percentages, millisecond improvements, lines removed)
- Place new version at the top, below the header
- Commit the updated `CHANGELOG.md` **before** cutting the tag, so it is included in the release
