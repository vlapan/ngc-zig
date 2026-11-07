# Session Handoff Protocol

Updated: 2026-11-08

- Before stopping significant work, commit focused changes, push if origin exists, and update durable state (`KNOWLEDGE.md`, relevant `knowledge/*`, and today's note).
- Preserve measurement artifacts by committing benchmark/profile logs with the code change that produced them, when those logs were explicitly recorded.
- If a change is unverified or incomplete, record the blocker and next command in today's daily note.
- For performance work, leave both the baseline (via git history) and after result available for comparison.
- Do not leave modified source uncommitted when the task is complete; unpushed commits should be explicitly mentioned in the final response.