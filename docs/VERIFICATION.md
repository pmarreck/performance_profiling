# Verification, October 2, 2026

## Executed evidence

- Linux x86_64: complete `nix develop -c ./test`, Nix package check/build and
  host-specific executable publication.
- Mac ARM64: complete native suite and native Nix package check/build on an Apple Silicon Mac.
- The complete Linux suite averaged 576.1 ms with sample SD 12.5 ms over five
  Hyperfine runs after one warmup (range 562.3–588.1 ms). Command:
  `nix develop -c hyperfine --shell=none --warmup 1 --runs 5 ./test`.
  This is suite duration, not a production application's benchmark result.
- After adding the startup-schema rejection regression, the same five-run
  command measured 640.6 ms with sample SD 16.2 ms (range 627.1–665.1 ms).
- Shared skill: frontmatter/name validation, complete installer suite and the
  isolated Linux Nix check passed. Both agent discovery roots resolve to the
  same physical skill files.

The final eleven groups, including the Nix module evaluation contract, passed
on both native machines before implementation commit `0101c3e`. The shared skill
and guidance consolidation is commit `5068df8` in `llm_skills`.
The startup-schema regression and its repair were then verified through both
native suites and Nix package builds. Host-specific wrappers launched on Linux
and Mac. The README records the still-pending dotfiles PATH migration rather than
assuming the published wrapper already wins PATH lookup.

## Falsified failures

Focused tests failed before fixes for cross-hardware reuse of a logical job ID,
zero concurrency, unequal historical sweep lengths and relevant TOML files being
excluded from source identity. They pass with those repairs. The real pilot's
closed-form sum oracle rejects an altered kernel that performs no summation.

Functional cases retain the earlier append-before-compare regression, both drift
directions, retry selection/exclusion, noisy timing, leak refusal, unbaselined
hardware and explicit epochs. File tests cover malformed records, denied writes,
symlinks, namespaces, idempotency, conflicting identities and concurrent writers.
Printable-binary tests exhaust all 256 source bytes, check uniqueness and both
round trips, and retain the pinned mapping hash.

The Nix history module is evaluated against a small option fixture at flake
evaluation. Disabled state, group/mode, service writable paths and unsafe path
rejection are asserted. `./test` requires the successful evaluation marker supplied
by the package/devShell. This does not prove production service access.

## Reproduce

```bash
nix develop -c ./test
nix build --no-link
./build
bin/linux/x86_64/performance-profile --about
```

On Mac, the published command is `bin/macos/aarch64/performance-profile`.
The package check reconstructs a private Git fixture because Nix sources omit
`.git`. Real pilot history and approvals use private temporary directories.
Expected process errors are captured and asserted rather than printed as warnings.

## Latency instrumentation overhead, October 20, 2026

Measured on the x86_64 Linux development host, three runs of a fixture job of
20 wrapped `luajit -e ""` spans against 20 bare spawns (41-42 ms):

| Cost | Measured |
| --- | --- |
| `latency begin` (tree identity + scratch file) | 17-21 ms |
| 20 wrapped spans | 131-156 ms, so 4.5-5.7 ms per span over a bare spawn |
| `latency finish` (identity, history read, evaluation, write) | 26-28 ms |
| history record write | 7.4-8.1 ms |
| tree identity on a 2,681-file consuming checkout | 23-36 ms |

Most per-span cost is LuaJIT startup before the wrapper's first timestamp; it is
reported as unattributed time. Loading the printable-binary encoding map cost
4.9 ms per span until the span path stopped loading it.

## Per-case deadline in a consuming project, October 21, 2026

The per-case `timeout_ms` option (2d48eab) came from a consuming project's
local patch. That project's committed control,
[`tests/performance_budget_test.mjs`](https://github.com/pmarreck/random/blob/c5bf5d56f2d745db502bb80ee52ef6ec7125fdfb/tests/performance_budget_test.mjs),
runs a 50 ms child with default, 5 ms and 5000 ms limits. It checks the
persisted effective budgets and refuses `0`, `-1`, `1.5`, the string `"1000"`
and `3600001`. Against an engine without the option it fails (the short case
does not time out: 3 completed cases where 1 was expected). Against the patched
engine it passes. The project's campaign adapters do not read `timeout_ms` from
older observations, so earlier records keep their engine identity. Adopting
this engine starts a new measurement identity and approves no baseline.
Process-tree cleanup is outside that control.

## Boundaries

No production baseline was automatically approved. No whole-fleet integration,
privileged history provision, NixOS activation or outside-sandbox CI runner has
been deployed. The default shared `/var/lib` history directory must be explicitly
provisioned, or overridden with an existing writable directory.

Linux ARM64 is declared but has not been executed natively. Native Windows,
GPU collectors, whole-runtime allocation accounting and network backends are not
implemented. The allocator pilot covers its malloc/free vector only.

The process adapter times out a live direct child after 30 seconds. Benchmark
commands must not detach descendants or leave inherited output pipes open after
the direct child exits; process-tree containment remains future work. Very large
source path lists may exceed the OS argv limit. Adapter diagnostic output must
be UTF-8; paths and configured argv use printable-binary encoding.

Finite growth sweeps do not prove asymptotic complexity, and the initial 10%/3-SD
policy is not an experimentally established confidence interval. No comparative
claim against Bencher has been demonstrated.
