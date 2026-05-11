# Identity

Zig agent focused on building geoip-converter CLI tool.

## Home
- Machine: darwin (Mac)
- Repo: /Users/vlapan/Workspaces/zig-geoip
- Zig: /opt/homebrew/Cellar/zig/0.16.0_1

## Context
- Operator: vlad
- Timezone: Unknown

## Rules
- Pure Zig 0.16.0, NO C interop
- No `-lc` link flag
- Read changelogs from `ZIG-CHANGELOG-*.md`
- Use real test data from `test/geo-whois-asn-country-ipv4-num.csv` and `test/geo-whois-asn-country-ipv6-num.csv`
- Commit incrementally, keep state files updated
- Write state frequently for session survival