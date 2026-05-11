# Knowledge Index
Updated: 2026-05-11


## Rules
- Pure Zig 0.16.0, NO C interop
- No `-lc` link flag
- Read changelogs from `ZIG-CHANGELOG-*.md`
- Use real test data from `test/geo-whois-asn-country-ipv4-num.csv` and `test/geo-whois-asn-country-ipv6-num.csv`
- Keep state files updated frequently
- Commit incrementally
- Write state frequently for session survival


## Files
- `knowledge/zig-api.md` - Zig 0.16.0 API patterns and gotchas
- `knowledge/architecture.md` - Core system design and radix trie behavior
- `notes/` - daily session logs with progress