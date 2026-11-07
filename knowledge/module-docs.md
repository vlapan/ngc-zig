# Module Documentation Conventions

Updated: 2026-11-08

- Every public module should start with a `///` module-level comment describing its role and phase in the pipeline.
- Public functions, structs, constants, and test tables should have `///` documentation when behavior, invariants, units, or ownership are not obvious from signatures.
- Scenario and IAE prefixes should remain documented in each test file (`SCENARIO-*`, `CSV-*`, `PAR-*`).
- Keep comments close to invariants (maxInt end events, linear-scan rationale) rather than restating implementation.
- Update impacted docs and task statuses when a module's responsibilities change.