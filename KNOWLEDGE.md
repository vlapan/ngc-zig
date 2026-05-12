# Knowledge Index
Updated: 2026-05-12


## Rules
- Pure Zig 0.16.0, NO C interop
- No `-lc` link flag
- Read changelogs from `ZIG-CHANGELOG-*.md`
- Use real test data from `test/geo-whois-asn-country-ipv4-num.csv` and `test/geo-whois-asn-country-ipv6-num.csv`
- Always verify output changes (`git diff test/output.txt`) to track expected vs unexpected changes before committing code
- Keep state files updated frequently
- Commit incrementally
- Write state frequently for session survival


## Files
- `knowledge/zig-api.md` - Zig 0.16.0 API patterns and gotchas
- `knowledge/architecture.md` - Core system design and radix trie behavior
- `notes/` - daily session logs with progress
- **Benchmarking & Profiling Rules**:
  - Whenever performance optimizations are made, you must compare and record the difference in detail.
  - Do not just compare CPU/User time. Also track: `maximum resident set size`, `peak memory footprint`, `instructions retired`, `cycles elapsed`, `voluntary context switches`, and `involuntary context switches` (from `/usr/bin/time -al`).
  - Be mindful of filesystem caching: A fresh build triggers a "cold run" with high I/O overhead. Subsequent runs are "hot runs". Always compare *cold runs with cold runs* and *hot runs with hot runs*.
