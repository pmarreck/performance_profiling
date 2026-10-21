# PLAN

Approved contract: docs/CONTRACT.md. One complete entry point: ./test.

## Owner handoff 2026-10-20 (priority order)

- [x] Refresh flake pins (nixpkgs-unstable head, printable_binary cdefa95, pin dotfiles 20184a1), pass ./test and Nix checks, push yolo, reply to jpegz and corruption_reader with the SHA. (done 2026-10-20 21:58 EDT; 01ae85b)
- [x] Upstream per-case `timeout_ms` from random's repo-local patch, test-first, without mutating validated config (keeps existing source digests); record the effective deadline per observation. (done 2026-10-20 22:05 EDT)
- [x] Feedback-latency pilot for Validate: agree a phase-record contract, then a pure core for interval-union phases, budget verdicts and debounced summaries, plus a CLI that stores latency records apart from cg/mg baselines (context: docs/plan_context/feedback_latency.md). (done 2026-10-20 22:20 EDT)
- [x] Measure the latency instrumentation's own overhead (snapshot hashing, history write) and report it with the tested revision. (done 2026-10-20 22:20 EDT; docs/VERIFICATION.md)
- [x] Validate adoption: pin this engine, wrap ./test phases, report the first instrumented full gate (done 2026-10-21 14:13 EDT; Validate 674e1ee1a, 3625 s total, OVER_BUDGET, 0.6 ms per span)
- [x] Span `--skip-exit CODE` so a declared skip (exit 77) reads INCOMPLETE instead of FAIL, keeping the real exit status (done 2026-10-21 14:30 EDT)
- [ ] Reassess per-span startup cost if a sub-second suite adopts the latency recorder.
	- [x] Propose to Validate a split of its Zig unit-test phase: build test binaries without running them (`./build --test`, compile span), then run them outside Nix (execute span), so execution time stops being mixed/UNMEASURED (context: docs/plan_context/feedback_latency.md). (done 2026-10-21 13:40 EDT; adopted by Validate, lands after its adoption commit)
- [x] Mechatron Prime CI onboarding: choose existing flake attributes, commit .mechatron-prime/targets, converge the webhook and verify the exact pushed commit. (done 2026-10-20 22:26 EDT; af38b15 success, badge PASSING)
- [x] Root entry points re-enter `nix develop` themselves when started outside it, announcing it on stderr; no-op inside a devShell or Nix build. (done 2026-10-21 13:50 EDT)
- [ ] Agree hook placement for latency summaries with Turing before touching any agent-global configuration.

## Next adoption

- [ ] Integrate one real decoder benchmark through the shared CLI and its complete ./test, preserving owner-approved baseline initialization.
- [ ] Coordinate declarative shared-history access and fresh outside-sandbox execution with the CI owner; verify an actual service-context write before claiming CI integration.
- [ ] Add bounded process-tree/output handling for adapters that detach descendants; presently require benchmark commands to close their inherited pipes on exit.
- [ ] Execute Linux ARM64 natively before claiming runtime support; assess native Windows and GPU adapters only with an approved consuming use case.

## First implementation

- [ ] macOS: no affinity API; multicore counts there are unenforced. Look at thread-policy hints if Mac cohorts need it.
- [x] (2026-10-02 22:20 EDT) Optional per-case odd `processes`: median fresh process gates, all kept.
