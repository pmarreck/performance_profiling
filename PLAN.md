# PLAN

Approved contract: docs/CONTRACT.md. One complete entry point: ./test.

## Owner handoff 2026-10-20 (priority order)

- [x] Refresh flake pins (nixpkgs-unstable head, printable_binary cdefa95, pin dotfiles 20184a1), pass ./test and Nix checks, push yolo, reply to jpegz and corruption_reader with the SHA. (done 2026-10-20 21:58 EDT; 01ae85b)
- [x] Upstream per-case `timeout_ms` from random's repo-local patch, test-first, without mutating validated config (keeps existing source digests); record the effective deadline per observation. (done 2026-10-20 22:05 EDT)
- [ ] Feedback-latency pilot for Validate: agree a phase-record contract, then a pure core for interval-union phases, budget verdicts and debounced summaries, plus a CLI that stores latency records apart from cg/mg baselines (context: docs/plan_context/feedback_latency.md).
- [ ] Measure the latency instrumentation's own overhead (snapshot hashing, history write) and report it with the tested revision.
- [ ] Mechatron Prime CI onboarding: choose existing flake attributes, commit .mechatron-prime/targets, converge the webhook and verify the exact pushed commit.
- [ ] Agree hook placement for latency summaries with Turing before touching any agent-global configuration.

## Next adoption

- [ ] Integrate one real decoder benchmark through the shared CLI and its complete ./test, preserving owner-approved baseline initialization.
- [ ] Coordinate declarative shared-history access and fresh outside-sandbox execution with the CI owner; verify an actual service-context write before claiming CI integration.
- [ ] Add bounded process-tree/output handling for adapters that detach descendants; presently require benchmark commands to close their inherited pipes on exit.
- [ ] Execute Linux ARM64 natively before claiming runtime support; assess native Windows and GPU adapters only with an approved consuming use case.

## First implementation

- [x] Implement atomic project-named file:// records with concurrent-write and immutable identity checks (done 2026-10-02 14:04 EDT; 0101c3e).
- [x] Add CLI, injected adapters, complete real cg/mg lifecycle, skipped-work oracle witness and distinct code-statistics/source identity (done 2026-10-02 14:04 EDT; 0101c3e).
- [x] Add pinned Nix packaging and native Linux/Mac checks; record measured suite budget and platform/deployment limits in docs/VERIFICATION.md (done 2026-10-02 14:04 EDT; 0101c3e).
- [x] Create the shared performance-profiling skill and consolidate active guidance after recoverable backups (done 2026-10-02 14:04 EDT; llm_skills 5068df8).
- [x] (2026-10-02 19:40 EDT) Noisy timing sweeps are INCONCLUSIVE (retryable) before declared-shape checks; found when a load spike turned a linear sweep into a final SHAPE_FAIL.
- [x] (2026-10-02 19:45 EDT) Per-case `cores` (required), taskset pinning on Linux, `PERFORMANCE_CPUS` override, `PERFORMANCE_CORES` to the command, cores and affinity method in the cohort, exact CPU list in each record.
- [ ] macOS: no affinity API; multicore counts there are unenforced. Look at thread-policy hints if Mac cohorts need it.
- [x] (2026-10-02 22:20 EDT) Source snapshot once per run (before the first case, after the last); records written after the check.
- [x] (2026-10-02 22:20 EDT) Optional per-case odd `processes`: median fresh process gates, all kept.
