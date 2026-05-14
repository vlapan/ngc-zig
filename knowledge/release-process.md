# Project Release & Deployment Protocol
Updated: 2026-05-14

Before tagging a new release, always execute this strict verification pipeline to ensure artifacts and baseline states are perfectly synchronized:

1. `make fmt` (Format all Zig code).
2. `make test` (Ensure all edge cases and unit tests pass).
3. `make bench` (Compile the `-Dstamp=true` release artifact, run cold/hot benchmarks, and verify output consistency).
4. `git status` (Verify that step 3 did NOT report an unexpected `[NOTICE]` modifying `test/output.txt`).
5. `git add benchmarks.log` (Stage the new benchmark baseline if performance changed).
6. Update `build.zig.zon` version string.
7. `git commit`, `git tag vX.Y.Z`, and `git push origin master --tags`.
