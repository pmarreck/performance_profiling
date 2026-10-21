# Feedback-latency pilot

Requirements brief (owner-approved 2026-10-20) lives outside the repository in
the coordinator's fleet-followup state. Policy summary: test execution targets 1 s
with a 5 s budget on declared hardware; compilation is excluded from that budget
and recorded separately, together with total time-to-feedback. Over budget is a
warning during the pilot, never a kill deadline.

## Contract draft v0 (sent to Validate 2026-10-20)

- Primary capture: `performance-profile latency span --job JOB --name NAME --kind KIND -- CMD...`
  passes CMD's exit status and output through and appends one monotonic span to a
  per-job scratch file under `$TMPDIR`; `latency finish --job JOB --correctness ...`
  evaluates, prints a one-line summary to stderr and JSON to stdout, and writes one
  `latency-observation` record to the project's external history.
- Alternative: the consumer emits a `feedback-latency/v1` JSON record directly.
- Kinds: queue, setup, dependency, nix_eval, compile, execute, mixed, deliver, other.
  An untimeable span is `status: unknown`, reported as unknown, never zero.
- Per-kind elapsed is the interval union; summed span time is a separate resource
  figure; uncovered time is `unattributed`.
- Latency verdict independent of correctness: WITHIN_TARGET, WITHIN_BUDGET,
  OVER_BUDGET, or UNMEASURED (execution only in mixed spans, cached, or unknown).
- Latency records are never read as cg/mg baseline observations.

## Validate's answers (2026-10-20)

- Accepts the span wrapper. Every top-level ./test phase is stampable today.
- Measured whole suite 3643-3750 s over three runs: Zig unit tests inside
  `nix build` (mixed) about 1360 s, release build about 283 s, CLI devShell
  evaluation about 287 s, 165-script CLI loop 1700-1776 s. Expect OVER_BUDGET by
  two to three orders of magnitude at first.
- Zig test execution can leave `nix build` after a build.zig change on Validate's
  side; until then that phase is mixed/UNMEASURED.
- Wants per-script spans for all 165 CLI scripts; summary shows totals plus N slowest.
- Never store argv or environment. Script basenames as span names are fine.
