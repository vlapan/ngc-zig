# Error Handling Conventions

Updated: 2026-11-08

- Parse helpers return Zig error sets for invalid operational input (e.g. `error.InvalidCharacter`, `error.FileTooLarge`). Callers decide policy: `csvFile` lets parse failures increment `lines_skipped`, while `parseInt` propagates.
- CLI flag parsing uses dedicated semantic errors (`MissingValue`, `UnknownArgument`, `InvalidArgs`, `HelpRequested`, `VersionRequested`) plus allocator errors.
- Configuration file parse errors are propagated with file/line context via `cliPrint`.
- `@branchHint(.unlikely)` may mark exceptional error paths, but it does not establish correctness and must not hide error handling.
- Silent skip metrics are telemetry. Anything considered fatal must propagate with `try`, not be counted.
- Prefer explicit error unions for recoverable failures; use `catch unreachable` only where proven by preceding validation.