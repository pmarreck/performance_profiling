# PLAN

Approved contract: docs/CONTRACT.md. One complete entry point: ./test.

## Next adoption

- [ ] Integrate one real decoder benchmark through the shared CLI and its complete ./test, preserving owner-approved baseline initialization.
- [ ] Coordinate declarative shared-history access and fresh outside-sandbox execution with the CI owner; verify an actual service-context write before claiming CI integration.
- [ ] Add bounded process-tree/output handling for adapters that detach descendants; presently require benchmark commands to close their inherited pipes on exit.
- [ ] Execute Linux ARM64 natively before claiming runtime support; assess native Windows and GPU adapters only with an approved consuming use case.

## First implementation

- [x] Prove baseline selection, two-sided bounds and retry isolation; add explicit epochs, malformed-history rejection and unchanged source/cohort job identities (done 2026-10-02 14:04 EDT; 0101c3e).
- [x] Implement atomic project-named file:// records with concurrent-write and immutable identity checks (done 2026-10-02 14:04 EDT; 0101c3e).
- [x] Add CLI, injected adapters, complete real cg/mg lifecycle, skipped-work oracle witness and distinct code-statistics/source identity (done 2026-10-02 14:04 EDT; 0101c3e).
- [x] Add pinned Nix packaging and native Linux/Mac checks; record measured suite budget and platform/deployment limits in docs/VERIFICATION.md (done 2026-10-02 14:04 EDT; 0101c3e).
- [x] Create the shared performance-profiling skill and consolidate active guidance after recoverable backups (done 2026-10-02 14:04 EDT; llm_skills 5068df8).
- [x] (2026-10-02 19:40 EDT) Noisy timing sweeps are INCONCLUSIVE (retryable) before declared-shape checks; found when a load spike turned a linear sweep into a final SHAPE_FAIL.
- [x] (2026-10-02 19:45 EDT) Per-case `cores` (required), taskset pinning on Linux, `PERFORMANCE_CPUS` override, `PERFORMANCE_CORES` to the command, cores and affinity method in the cohort, exact CPU list in each record.
- [ ] macOS: no affinity API; multicore counts there are unenforced. Look at thread-policy hints if Mac cohorts need it.
