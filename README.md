# performance-profile

Complexity, timing and memory gates with external, inspectable measurement history.
LuaJIT handles the policy; a project's benchmark CLI performs and verifies its work.

Implemented first version: project-configured file URLs, immutable project-named
NDJSON records, two-sided percentage/SD comparisons, explicit baseline epochs,
one timing retry, isolated retry diagnostics, allocation cleanup checks, CPU and
wall samples, independent startup-to-ready timing and provenance. Linux x86_64
and Mac ARM64 have native suite/package verification. Native Windows and network
storage backends are not implemented.

## Build and try

```bash
./build
mkdir -p "$HOME/.local/state/performance-history"
export PERFORMANCE_HISTORY_URL="file://$HOME/.local/state/performance-history"
nix develop -c ./cg --seed 15
```

The first run reports UNBASELINED (exit 3) and saves the valid observation for
review. Inspect the JSON or `nix run . -- history`, then explicitly approve
the printed ID after checking the work/shape/allocator coverage:

```bash
nix run . -- accept --run '<printed-id>' --reason 'Reviewed work and scaling'
nix run . -- run --mode cg --seed 15
nix run . -- run --mode mg --seed 15
```

Each case/hardware cohort needs its own first approval. A fresh run after approval
uses the accepted epoch. Use `--run-id JOB-ID` when retrying one logical CI job:
a completed same-ID/same-source/same-seed rerun returns its original record without
running the benchmark again. Start a new ID to make a fresh observation. Changing
the inputs or hardware cohort behind an existing ID is an error. Ordinary fresh
runs are intentionally cumulative history, not a repeated business side effect.

`./build` publishes the Nix-wrapped command under `bin/<os>/<arch>/`. Host-specific
PATH selection is the intended fleet convention, but the inspected local dotfiles
still prefer portable `bin/` entries. Use `nix run . -- ...`, or the published host
path directly, until that PATH migration is applied. Merely seeing the development
script on PATH does not prove its project dependencies are present.
The wrapper pins LuaJIT, cjson, luv, coreutils and printable-binary. The bare
development script requires `nix develop -c`; a global LuaJIT alone is insufficient.

## Project configuration

See [profiling.json](profiling.json). Set `project` and `history_url` per project.
The URL must identify an existing writable directory outside its source tree.
Spaces and percent-escaped bytes in file URLs are supported. Only local `file://`
and `file://localhost/` are supported; no implicit remote mount or directory chmod.

History URL precedence is `--history-url`, `PERFORMANCE_HISTORY_URL`, then project
`history_url`. Filenames are `<project>--<kind>--<id>.ndjson`. Names are letters,
digits, underscores and hyphens, with double-hyphens reserved as separators.
Several projects can share one directory without mixing their history.

The adapter command is an argv array, never shell-evaluated. Placeholders are
`{case}`, `{sizes}` (comma-separated), and `{seed}`. Configuration lives at the
project root; commands execute there regardless of the caller's cwd.

Source identity includes tracked and unignored project files, including relevant
configuration, hidden files and fixtures. Regular files are hashed by a streaming
adapter. Only the separate dirty-code line statistics exclude non-code metadata.

Supported metrics are `operations`, `cpu_ns`, `wall_ns`, `peak_bytes`,
`allocation_count`, `total_bytes` and `startup_ns`. Growth mode compares every
adjacent input pair; `comparison: "absolute"` supports fixed-size and startup
cases. Bounds are declared independent limits in that metric's units/ratio.

Default policy uses 10% practical tolerance and 3 sample SD, taking the greater
band; minimum history is 3 and the window 20, configurable per case. These are
initial tuning choices, not confidence guarantees. Excessive sample/history CV
(default 0.3) is inconclusive. An explicitly approved one-point anchor uses
percentage bounds until SD history is sufficient; the verdict names that method.
All values/policies/reference IDs are recorded before a new observation can enter
future comparisons. Approval is explicit caller authority, not cryptographic
proof that a human personally typed the command.

## Adapter protocol

The command writes one JSON object conforming to [the protocol](docs/PROTOCOL.md).
The bundled [pilot](tests/benchmark/pilot.lua) runs a real vector sum, verifies
`n*(n+1)/2`, and measures malloc/free requests for its input vector. It does not
claim to track the Lua runtime's memory. It records five samples after three
in-process warmup cycles and releases native memory before checking residuals.

An optional `ready_marker` identifies the first complete stdout line. The runner
times spawn to receipt of that line separately from kernel timing; the remaining
stdout is the measurement JSON. `startup_ns` cases collect five independent process
starts. This includes marker delivery/scheduling latency. The pilot also records
its narrower entry-to-ready interval and explicitly states what it excludes.

Correctness, shape, leaks, malformed protocol, crash and storage errors cannot
be approved as performance changes or silently normalized by retries. A timing
deviation/noisy sweep gets exactly one full retry. Failed attempts are diagnostic
objects; only the selected pass is baseline-eligible. Both failures remain saved
with no eligible selection. High historical noise needs investigation/policy
review; it is not repaired by cherry-picking faster samples.

## Nix and CI

Add the package to the consuming devShell, initially from this local Git checkout:

```nix
inputs.performance-profiling.url = "git+file:///absolute/path/to/performance_profiling";
# In devShells.<system>.default.packages:
# performance-profiling.packages.<system>.default
```

Keep top-level `cg`/`mg` thin Bash wrappers invoking the same `performance-profile`
command with that project's configuration. The complete `./test` includes them.
Build the pinned benchmark with Nix, then execute fresh measurements outside the
build sandbox; do not put writes to shared history inside a derivation. Cached
checks are past observations. The deterministic policy/adapter tests do run in
the package's isolated Nix check.

Provision user and actual CI access to the history directory. A CI worker running
as a hardened systemd service (for example with `ProtectSystem=strict`) admits
writes only beneath its declared state directories. A directory merely writable
on the host is insufficient inside that service's mount namespace. Use the
optional [storage module](nix/history-storage.nix) or an equivalent approved
declarative provision, and verify a service-context write. No production CI
post-build runner or whole-system activation is performed by this project's build.

## Tests and limits

`nix develop -c ./test` is the complete suite. It includes injected policy/epoch
tests, baseline-contamination regression, nested-diagnostic exclusion, both drift
directions, SD arithmetic, crossover, leak and noisy cases; real process/file
adapters; and a complete real cg/mg lifecycle with approval in private temporary
history. Those test approvals are fixture operations, not production approvals.

Fresh measurement tests are bounded. Native-platform results and actual timings
are in [verification](docs/VERIFICATION.md). Whole-process RSS, GPU collection,
schema migration adapters for future versions, remote backends and production
fleet adoption remain later work. Don't claim superiority to Bencher without
comparative evidence. The useful focus here is the shared Nix/mixed-language
growth/cleanup contract and explicit retry-history separation.

See [INTENT.md](INTENT.md), [approved contract](docs/CONTRACT.md) and [PLAN.md](PLAN.md).
