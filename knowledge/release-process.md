# Project Release & Deployment Protocol
Updated: 2026-05-14

Before tagging a new release, always execute this strict verification pipeline to ensure artifacts and baseline states are perfectly synchronized:

1. `make fmt` (Format all Zig code).
2. `make test` (Ensure all edge cases and unit tests pass).
3. `make bench` (Compile the `-Dstamp=true` release artifact, run cold/hot benchmarks, and verify output consistency).
4. `git status` (Verify that step 3 did NOT report an unexpected `[NOTICE]` modifying `test/output.txt`).
5. `git add benchmarks.log` (Stage the new benchmark baseline if performance changed).
6. Update `build.zig.zon` version string.
7. Commit the version bump: `git commit -am "chore: release vX.Y.Z"`
8. Review the commit history since the last release: `git log $(git describe --tags --abbrev=0)..HEAD --oneline`
9. Create an **annotated tag** containing bullet points of the main features and optimizations implemented since the last tag. Example:
   `git tag -a vX.Y.Z -m "Release vX.Y.Z" -m "- perf: lightweight index sorting" -m "- perf: branchless IPv6 formatting"`
10. Push the commit and the new annotated tag: `git push origin master --follow-tags`
