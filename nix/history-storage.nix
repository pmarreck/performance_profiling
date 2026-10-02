# Optional NixOS provisioning; importing does nothing until explicitly enabled.
{ config, lib, ... }:
let
	cfg = config.services.performance-profile-history;
in {
	options.services.performance-profile-history = {
		enable = lib.mkEnableOption "shared external performance measurement history";
		directory = lib.mkOption { type = lib.types.str; default = "/var/lib/performance-profiling"; };
		members = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; description = "Existing human and CI users allowed to read/write history"; };
		runnerUnits = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; description = "System services requiring a writable history namespace"; };
	};
	config = lib.mkIf cfg.enable {
		assertions = [{ assertion = builtins.match "/var/lib/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*" cfg.directory != null; message = "Performance history directory must be a simple absolute /var/lib path"; }];
		users.groups.performance-profiling.members = cfg.members;
		systemd.tmpfiles.rules = [ "d ${cfg.directory} 2770 root performance-profiling -" ];
		systemd.services = lib.genAttrs cfg.runnerUnits (_: {
			serviceConfig.ReadWritePaths = [ cfg.directory ];
			serviceConfig.SupplementaryGroups = [ "performance-profiling" ];
			serviceConfig.UMask = "0007";
		});
	};
}
