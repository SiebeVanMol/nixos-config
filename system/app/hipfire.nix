# hipfire: ROCm-accelerated LLM inference daemon, run as a per-user systemd
# service for the host's desktop user (see device.app.hipfire in options.nix).
#
# Upstream only ships a NixOS-level `services.hipfire`; in `userService` mode it
# installs system-wide user units, so they are pinned to `cfg.user` with
# ConditionUser instead of starting a second daemon for every user that logs in.
# modelDir therefore lives under that user's home: the module default
# /var/lib/hipfire/models is not writable by an unprivileged user unit.
#
# We deliberately never pre-warm: upstream only appends `--no-prewarm` when its
# own defaultModel is empty, so that option is forced empty here and the tag the
# operator picked is written as serve.default_model through extraSettings
# instead. The daemon then loads on the first request and evicts the model again
# after idleTimeout, so VRAM is only held while the model is actually in use.
#
# The weights themselves are not fetched by this module. Pull the tag once per
# user, e.g. `hipfire pull qwen3.8:27b-mq3-xt`.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.device.app.hipfire;
  modelDir = "${config.users.users.${cfg.user}.home}/.hipfire/models";
in {
  config = lib.mkIf cfg.enable {
    services.hipfire = {
      enable = true;
      userService = true;
      inherit (cfg) gpuTargets maxSeq kvCache idleTimeout dflashMode perModelSettings;
      inherit modelDir;

      # Force the lazy-load path in ExecStart; the real default tag is set below.
      defaultModel = "";

      # `hipfire serve` has no authentication or TLS and listens on 0.0.0.0 by
      # default, so keep it on loopback. openFirewall stays off, so the port is
      # never exposed even if the host firewall is disabled.
      #
      # MTP has no typed option upstream, so pin speculation.mtp through
      # extraSettings (merged last, and canonicalized as-is). DFlash and MTP are
      # a first-match cascade in the loader, not a combination; see the option
      # descriptions in options.nix.
      #
      # hipcc_extra_flags must be here and not in the unit environment: the JIT
      # compiler reads it through the CLI's serialized ProcessConfig
      # (FeatureFlags::from_process_config -> config.legacy_value), so an env
      # var set on the daemon is not seen and kernel compiles fail with
      # "cannot find ROCm device library".
      extraSettings =
        {
          host = "127.0.0.1";
          "speculation.mtp" = cfg.mtpMode;
          "diagnostic.compiler.hipcc_extra_flags" = "--rocm-device-lib-path=${pkgs.rocmPackages.rocm-device-libs}/amdgcn/bitcode";
        }
        // lib.optionalAttrs (cfg.defaultModel != "") {
          "serve.default_model" = cfg.defaultModel;
        }
        // lib.optionalAttrs (cfg.gpuLayerBudget != null) {
          "memory.gpu_layer_budget" = cfg.gpuLayerBudget;
          "memory.offload_exec" = cfg.offloadExec;
        };
    };

    systemd.user.services.hipfire-setup.unitConfig.ConditionUser = cfg.user;
    systemd.user.services.hipfire.unitConfig.ConditionUser = cfg.user;
  };
}
