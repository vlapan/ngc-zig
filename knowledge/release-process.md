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
