{ lib }:
let
	base = { ... }: {
		options = {
			assertions = lib.mkOption { type = lib.types.listOf lib.types.attrs; default = []; };
			users.groups = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; default = {}; };
			systemd.tmpfiles.rules = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
			systemd.services = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; default = {}; };
		};
	};
	evaluate = settings: (lib.evalModules {
		modules = [ base ../../nix/history-storage.nix { services.performance-profile-history = settings; } ];
	}).config;
	disabled = evaluate {};
	enabled = evaluate { enable = true; members = [ "human" "ci" ]; runnerUnits = [ "worker" ]; };
	valid = path: lib.all (a: a.assertion) (evaluate { enable = true; directory = path; }).assertions;
in
assert disabled.systemd.tmpfiles.rules == [];
assert disabled.systemd.services == {};
assert enabled.users.groups.performance-profiling.members == [ "human" "ci" ];
assert enabled.systemd.tmpfiles.rules == [ "d /var/lib/performance-profiling 2770 root performance-profiling -" ];
assert enabled.systemd.services.worker.serviceConfig.ReadWritePaths == [ "/var/lib/performance-profiling" ];
assert enabled.systemd.services.worker.serviceConfig.SupplementaryGroups == [ "performance-profiling" ];
assert enabled.systemd.services.worker.serviceConfig.UMask == "0007";
assert valid "/var/lib/profile/history";
assert lib.all (path: !(valid path)) [ "/home/history" "/var/lib/../etc" "/var/lib/with space" "/var/lib/a\nb" "/var/lib/a\tb" "/var/lib/" ];
true
