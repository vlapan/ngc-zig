# Naming Conventions

Updated: 2026-11-08

- Modules: lowercase `snake_case` file/module names (`parse.zig`, `config.zig`).
- Functions: lowercase `camelCase` (`parseArgs`, `formatIPv4Line`).
- Types: PascalCase (`Config`, `StreamResult`, `CidrStats`).
- Constants: `SCREAMING_SNAKE_CASE` only when they are true compile-time constants (`MAX_FILE_SIZE` not currently used); otherwise lowerCamel.
- Booleans: use positive capability/state names (`quiet`, `dry_run`, `has_filters`).
- Test IDs use `MODULE-NNN` uppercase prefixes in IAE tables (`CSV-001`, `PAR-002`).
- Commit scopes follow Conventional Commits and use changed module/function names (`feat(parse):`, `docs(knowledge):`).