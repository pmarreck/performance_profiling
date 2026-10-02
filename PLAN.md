# PLAN

Approved contract: docs/CONTRACT.md. One complete entry point: ./test.

## Next adoption

- [ ] Integrate one real decoder benchmark through the shared CLI and its complete ./test, preserving owner-approved baseline initialization.
- [ ] Coordinate declarative shared-history access and fresh outside-sandbox execution with Mechatron's owner; verify an actual service-context write before claiming CI integration.
- [ ] Add bounded process-tree/output handling for adapters that detach descendants; presently require benchmark commands to close their inherited pipes on exit.
- [ ] Execute Linux ARM64 natively before claiming runtime support; assess native Windows and GPU adapters only with an approved consuming use case.

## First implementation

- [x] Prove baseline selection, two-sided bounds and retry isolation; add explicit epochs, malformed-history rejection and unchanged source/cohort job identities (done 2026-10-02 13:59 EDT).
- [x] Implement atomic project-named file:// records with concurrent-write and immutable identity checks (done 2026-10-02 13:59 EDT).
- [x] Add CLI, injected adapters, complete real cg/mg lifecycle, skipped-work oracle witness and distinct code-statistics/source identity (done 2026-10-02 13:59 EDT).
- [x] Add pinned Nix packaging and native Linux/Mac checks; record measured suite budget and platform/deployment limits in docs/VERIFICATION.md (done 2026-10-02 13:59 EDT).
- [x] Create the shared performance-profiling skill and consolidate active guidance after recoverable backups (done 2026-10-02 13:59 EDT).
