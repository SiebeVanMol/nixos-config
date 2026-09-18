# hipfire: ROCm-accelerated LLM inference daemon, run as a per-user systemd
# service for the host's desktop user (see device.app.hipfire in options.nix).
#
# Upstream only ships a NixOS-level `services.hipfire`; in `userService` mode it
# installs system-wide user units, so they are pinned to `cfg.user` with
# ConditionUser instead of starting a second daemon for every user that logs in.
# modelDir therefore lives under that user's home: the module default
# /var/lib/hipfire/models is not writable by an unprivileged user unit.
{
  config,
  lib,
  ...
}: let
  cfg = config.device.app.hipfire;
  modelDir = "${config.users.users.${cfg.user}.home}/.hipfire/models";
in {
  config = lib.mkIf cfg.enable {
    services.hipfire = {
      enable = true;
      userService = true;
      inherit (cfg) gpuTargets;
      inherit modelDir;

      # `hipfire serve` has no authentication or TLS and listens on 0.0.0.0 by
      # default, so keep it on loopback. openFirewall stays off, so the port is
      # never exposed even if the host firewall is disabled.
      extraSettings.host = "127.0.0.1";
    };

    systemd.user.services.hipfire-setup.unitConfig.ConditionUser = cfg.user;
    systemd.user.services.hipfire.unitConfig.ConditionUser = cfg.user;
  };
}
