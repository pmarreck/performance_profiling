# Conformance to the cross-platform build layout

Audit date: 2026-10-23, against the fleet naming contract of the same day
(`PF` = `<OS>-<ARCH>`, OS `linux|macos|mswin`, ARCH `amd64|arm64`).

## Current state

- `./build` evaluates the Nix system, builds `.` to `.nix-out/<nix-system>/release`
  and links `bin/<os>/<arch>/performance-profile` (`bin/linux/x86_64/`,
  `bin/linux/aarch64/`, `bin/macos/aarch64/`). That nested layout is retired.
- `.nix-out/` is named by the Nix system (`x86_64-linux`), a tool-owned
  spelling; project-controlled output namespaces should use PF.
- `.gitignore` ignores `/bin/linux/`, `/bin/macos/`, `/bin/windows/`.
- `./build` takes no arguments: no explicit debug/test mode, no
  `--all-plats`/`--all`, no `--backend=direct`. There is one implementation,
  so no `CANONICAL_IMPL` or `canonize` is needed.
- Publication is `ln -sfn` after a successful `nix build`: a failed build keeps
  the previous link, but concurrent publications are not serialized.
- Tracked generic `bin/performance-profile` is the development LuaJIT script.
  It is not portable on its own (needs cjson, luv and the printable-binary map
  from the devShell), yet generic `bin/` is on automatic PATH.
- No `./run`. `./test` runs the source tree inside the devShell, not a PATH
  installation, which already satisfies "never test another PATH installation".
- Native Windows (`mswin-*`) is not supported; Linux arm64 is built by Nix but
  never executed natively (see VERIFICATION.md).

## Open decisions for BDFN

- Profile name for a LuaJIT package with no compiler profiles (`release` is the
  current name; there is no debug variant to distinguish).
- Generic `bin/performance-profile`: turn it into the optional Nix bootstrap
  fallback, or keep it as a development script outside automatic PATH.
- Whether `--all-plats` should attempt cross-system Nix builds (needs remote
  builders) or report the other platforms as unavailable.

## Rollout constraint

The dotfiles PATH change belongs to its owner. Stage `bin/<PF>/` first, keep
the old link until the owner switches PATH discovery and verifies resolution,
then retire the old directory recoverably (`mv` to `~/.Trash`).
