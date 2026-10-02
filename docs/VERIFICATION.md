# Verification, October 2, 2026

## Executed evidence

- Linux x86_64: complete `nix develop -c ./test`, Nix package check/build and
  host-specific executable publication.
- Mac ARM64: complete native suite and native Nix package check/build on `m4max`.
- The complete Linux suite averaged 576.1 ms with sample SD 12.5 ms over five
  Hyperfine runs after one warmup (range 562.3–588.1 ms). Command:
  `nix develop -c hyperfine --shell=none --warmup 1 --runs 5 ./test`.
  This is suite duration, not a production application's benchmark result.
- Shared skill: frontmatter/name validation, complete installer suite and the
  isolated Linux Nix check passed. Both agent discovery roots resolve to the
  same physical skill files.

The earlier eight-group suite passed on both native machines. Later additions
include simultaneous writers, startup validation, malformed baseline rejection,
source/configuration identity and a skipped-kernel mutation witness. The final
commands below rerun the complete expanded suite and package before commit.

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
