# Initial profiling contract

Peter approved implementation on October 2, 2026 after discussion of baseline
contamination, ephemeral CI, hardware variation and retries. The earlier audit
is retained in the orchestrator's docs/plan_context directory.

## Commands and project configuration

One engine serves ./cg (complexity), ./mg (memory) and ./bm (thorough timing).
The complete ./test reaches bounded required gates. Long investigations can use
./bm without imposing an arbitrary subsecond limit on reliable measurements.

Each project owns a JSON configuration including its stable name, history_url,
benchmark commands as argv arrays, sizes, seed, metrics, build/runtime identity,
declared shape bounds and statistical policy. Explicit --history-url overrides
PERFORMANCE_HISTORY_URL, which overrides the project's URL. No global forced
history destination. file:// URLs designate absolute existing writable directories;
the adapter does not create or chmod shared directories implicitly.

Filenames contain the project name, record kind and unique run ID. Restrict names
to letters, numbers, hyphens and underscores; reject unsafe names, never sanitize
two names into the same namespace. Records use real JSON serialization. Space-
preserving printable-binary encodes byte-exact paths and argv where available,
with its map/version recorded. This does not replace a JSON encoder.

## Measurement and comparability

Use N, 2N, 4N, 8N and preserve every adjacent ratio. Hold other dimensions fixed;
multi-input cases need independent sweeps. Collect raw per-size samples, process
CPU and monotonic wall time, startup-to-ready separately, iterations and work
validation. Prepare and warm up inside the benchmark process before timing.
Record the actual optimized build/runtime; Debug is refused. No guessed startup
subtraction, zero-on-clock-error, silent required skip or smaller-work speedup.

Use deterministic operation/allocation counts when appropriate. CPU frequency,
caches, backend and scheduling still affect time ratios. Hardware-qualified
cohorts include CPU/features, OS/architecture, runtime/compiler, optimization,
concurrency, measurement method and benchmark definition. Source revision is
provenance, not a new cohort on every edit. Include GPU identity only for GPU work.
Store transient conditions separately. An unknown cohort is unbaselined, not a
historical pass. Declared shape can still be checked.

Default historical bounds are two-sided and use the greater of the practical
relative tolerance (initially 10%) and the configured standard-deviation band
(initially 3 SD). These are configurable starting policies, not validated
universal thresholds. Require enough historical observations and reject excessive
noise as inconclusive. Freeze the eligible accepted-epoch history before measuring
or persisting the current run. Record exact reference IDs, count, mean, SD, bounds,
policy and epoch in the verdict. Zero baselines need a declared absolute floor.
Evaluate declared shape/resource limits separately; never let noisy history
excuse an intrinsically invalid workload. Finite sweeps do not prove Big-O.

Peter added on October 2, 2026: every case declares its core count, and
workloads are measured both single-core and multicore (12 cores) as separate
cases, with the count noted in the record and the cohort. Linux pins with
taskset; platforms without an affinity API record the count as unenforced.
A timing sweep whose samples exceed the noise policy is inconclusive and
retryable before any declared-shape judgment; only a deterministic metric or
a clean timing sweep can fail its declared shape.

## Retry and approval

An otherwise valid timing deviation or noisy timing sweep gets exactly one
complete retry with unchanged executable, source, input, seed, baseline and policy.
No retry for correctness, crash, leaks, malformed protocol or storage failure.

First pass is PASS. Failed first attempt followed by a pass is PASS_ON_RETRY.
Two failures are FAIL (or INCONCLUSIVE for unresolved measurement quality).
Only the selected passing measurement can be a baseline-eligible observation.
Nested failed attempts are diagnostics and must never enter the baseline reader,
even if they contain fields that resemble valid observation rows. Both failures
are preserved in one non-eligible event. Retry evidence is inspectable and does
not introduce an additional automatic flakiness gate.

Manual accept refers to an exact valid run and records a reason in an immutable
approval event. That creates a new epoch anchored to that observation. A normal
rerun, including CI retry, cannot approve or overwrite an epoch. Genuine leaks,
correctness failures and declared-shape violations are not accepted as performance
changes. New cohorts need explicit initialization.

## Memory

Report requested live/peak bytes, allocation count and residual live bytes after
repeated complete lifecycle cycles. State the allocator coverage; do not label
partial language counters whole-process memory. FFI/native allocation tracking
requires its own adapter. Bounded retained caches need an explicit allowance.
Unexpected growth and reduction are checked; unowned residual allocations fail
independently of historical averages. RSS is supplemental because freed objects
can leave retained allocator pages. Sanitized timings are a different cohort.

## History and provenance

Version each observation and approval. Unsupported schema or malformed required
history fails clearly. Older formats need an explicit lossless adapter or migration;
never silently discard them. V1 need not invent migrations for formats not yet made.

Write unique temporary files, check writes, fsync, publish without overwriting an
existing record, and sync the directory. Same ID and content is a no-op; conflicting
content is an error. Concurrent unique records coexist. Project/ID symlinks must
not redirect writes. A partial temp file is never baseline input. Different
concurrent approvals from the same parent epoch are a conflict, not last-writer-wins.

Capture UTC ISO timestamps with milliseconds, uname, hardware, toolchain/profile,
HEAD, dirty code paths and Git added/deleted counts, exact argv, fixture/seed and
source/benchmark identity. Exclude dot-prefixed path components and .ndjson, .toml,
.txt and .md from dirty-code stats only. Configuration can still affect reproducibility.
Git has no uniquely defined changed-line count; keep its exact added/deleted counts.
Untracked source needs counts; binary line stats are unavailable, not invented.
Check source identity before/after the measurement; changing sources invalidate it.
Do not log secrets embedded in argv; benchmark commands must use non-secret refs.

Nix builds the pinned executable and dependencies, while fresh measurements and
external history writes run outside the build sandbox. A cached check is prior
evidence, not a measurement of today's host. CI and local use the same pipeline.
Do not world-write history or grant all users access; provision the actual runner.

## Evidence and adoption

Tests inject measurement samples, clocks, processes and storage. Real-adapter tests
cover permissions, unusual paths, malformed files, interruption and concurrency.
Test linear/quadratic/crossover work, skipped work, leaks and bounded caches.
Native platform execution must be reported separately from flake evaluation.
V1 uses only file://; network databases and broad fleet adoption require later work.

Measurement background: [Google Benchmark variance guide](https://google.github.io/benchmark/reducing_variance.html),
[user guide](https://google.github.io/benchmark/user_guide.html), and
[Hyperfine shell calibration](https://github.com/sharkdp/hyperfine#shell-startup-time).
