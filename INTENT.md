# Performance profiling

Provide reusable, language-neutral performance controls for developers and CI.
Measure correct work, detect changes in runtime and memory growth in either
direction, and keep an inspectable history without modifying the measured repo.

The first backend stores immutable, project-named NDJSON records in a directory
selected by each project's file:// URL. Local and CI callers use the same engine
outside the Nix build sandbox. A passing retry contributes only its selected
measurement; earlier attempts remain diagnostics. Explicit approval establishes
an epoch. Rerunning a job never approves a baseline.

Initial scope includes a LuaJIT CLI, dependency-injected evaluation, statistical
and declared-shape checks, memory cleanup checks, atomic history and a real pilot.
It excludes a hosted database, dashboard, automatic fleet migration and claims
that finite timing measurements prove Big-O. Native Windows adapters and other
storage protocols are later work, not claimed supported by the initial release.

Success requires the complete ./test suite, an optimized reproducible benchmark
adapter, independent work checks, reproducible failures and safe history retries.
Detailed decisions are in [the contract](docs/CONTRACT.md).
