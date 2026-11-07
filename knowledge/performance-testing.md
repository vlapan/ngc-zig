# Performance Testing

Updated: 2026-11-08

- Use measured, repeatable comparisons before claiming performance changes.
- Run `make bench` for end-to-end baseline/release behavior and `make perf` for micro-level snapshot comparisons.
- Always compare before/after using git-preserved snapshots or `git diff`, and report regressions (instructions, cycles, RSS, context switches, I/O phase times) as prominently as improvements.
- Benchmark output generation, parse paths, CIDR generation, allocate behavior, and writer flushing separately when the changed code spans multiple phases.
- Use release builds with debug symbols for representative profiling; debug builds are useful for attribution but not performance conclusions.
- Keep the required pre-change baseline, one logical change, post-change measurement, and documented comparison order.