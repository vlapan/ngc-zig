# Commit Conventions
Updated: 2026-06-12

All commits must follow Conventional Commits format: `type(scope): description`

## Types
- `feat` — new feature
- `fix` — bug fix
- `docs` — documentation only
- `chore` — maintenance, config, tooling
- `refactor` — code change that neither fixes nor adds features
- `test` — adding or fixing tests
- `perf` — performance improvements
- `ci` — CI/CD workflow changes

## Scope
Optional but recommended. Use the module or area affected:
- `parse`, `config`, `cidr`, `flatten`, `ip`, `scan`, `nginx`, `main`
- `ci`, `makefile`, `benchmarks`, `tests`
- `docs`, `knowledge`, `notes`

## Examples
- `feat(cidr): add iterative rangeToCidrs for IPv6`
- `fix(parse): reject non-digit characters in parseInt`
- `docs: update RAM heuristic to 97B/CIDR`
- `chore: remove dead code from ip.zig`
- `perf(scan): replace indexOfScalar with findByte`
- `test(flatten): add sweep-line merge edge cases`

## Rules
- No emoji in commit messages
- Description is imperative mood ("add" not "added")
- Keep description under 72 characters
- Body is optional, use for explaining "why" not "what"
- No co-author lines

## Benchmark Convention
- `test/baseline-benchmarks.log` must be updated and committed with every change that affects performance
- Run `make bench` after each code change to append a new entry
- Do NOT restore to HEAD — the file is a historical performance log
- Each commit should reflect the actual benchmark state at that point. Never commit benchmark logs or output files generated from dirty/uncommitted code ahead of the code changes themselves — see "Coupling Rule" below.
- If a change has no performance impact, still commit the updated log to maintain continuity
- Use `chore(benchmarks): update baseline after <change>` as commit message
- **Output File Integrity Check**: After any benchmark run, verify `wc -l test/output*.txt` matches the reported `Total:` CIDR count. A mismatch indicates a truncated/corrupted output file.

## Coupling Rule: Code + Outputs + Benchmarks
Code changes, their resulting benchmark logs, and their resulting output files must be committed TOGETHER in a single commit. Never commit one without the others. If review requires seeing outputs separately, stage them together but defer the commit. Rationale: a future checkout of the commit must reproduce the same results.
