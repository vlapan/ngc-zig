# Commit Conventions
Updated: 2026-05-16

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
- `parser`, `config`, `cidr`, `flatten`, `ip`, `swar`, `nginx`, `main`
- `ci`, `makefile`, `benchmarks`, `tests`
- `docs`, `knowledge`, `notes`

## Examples
- `feat(cidr): add iterative rangeToCidrs for IPv6`
- `fix(parser): reject non-digit characters in fastParseInt`
- `docs: update RAM heuristic to 97B/CIDR`
- `chore: remove dead code from ip.zig`
- `perf(swarm): replace indexOfScalar with findByte`
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
- Each commit should reflect the actual benchmark state at that point
- If a change has no performance impact, still commit the updated log to maintain continuity
- Use `chore(benchmarks): update baseline after <change>` as commit message
