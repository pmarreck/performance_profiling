# Sourced by the root entry points (./test, ./bm, ./cg, ./mg) so a caller who
# forgot `nix develop` still runs against the flake's pinned toolchain.
# Outside a devShell (IN_NIX_SHELL unset) and outside a Nix build
# (NIX_BUILD_TOP unset) it re-executes the script through `nix develop` with
# its arguments intact and announces that on stderr. Without nix it stops
# rather than run against whatever interpreter happens to be on PATH.
reenter_devshell() {
	local project="$1" script="$2"
	shift 2
	if [ -n "${IN_NIX_SHELL:-}" ] || [ -n "${NIX_BUILD_TOP:-}" ]; then return 0; fi
	if ! command -v nix >/dev/null 2>&1; then
		printf '%s: not in a nix develop shell and nix is not on PATH; install Nix or enter the devShell\n' "$script" >&2
		exit 1
	fi
	printf 'heads up: %s re-entered itself in nix develop mode\n' "$script" >&2
	exec nix develop "$project" -c "$script" "$@"
}
