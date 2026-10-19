# The weekly check for overlay pins that are behind upstream.
#
# `overlays/` pins four packages nixpkgs does not carry, each by a version and a
# hash. Nothing was watching either: seerrng sat forty-eight releases behind and
# the only place that showed was its own UI. `nix run .#update-overlays --
# --check` answers "is anything behind" - this runs it on a timer and, when the
# answer is not "nothing", posts the report to the same Discord webhook as the
# daily health check and the weekly disk report.
#
# Check-only on purpose. Updating means nix-update rewriting a file in a git
# checkout and a build deciding whether the new pin is good; that is a person's
# call about their own tree, not a timer's. The timer's job is to stop anyone
# having to remember to ask.
#
# The checkout path and its owner are options rather than constants: a service
# cannot guess where a repository lives, and the check evaluates
# `.#packages...`, which needs the git tree's owner - run as root, git refuses
# "dubious ownership" and the evaluation returns nothing.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.device.maintenance.overlays;

  updateOverlays = import ../../lib/overlay-updater.nix {inherit pkgs;};
  alertWebhook = import ../../lib/alert-webhook.nix {inherit pkgs;};

  # The check is the updater with `--check`, wrapped so a failure reaches the
  # webhook. Nushell rather than a shell pipeline: the report is already a
  # value there, and a pipeline would have to carry its own copy of the 1800
  # character truncation alert-webhook exists to own. Exit stays the gate: 0
  # when every pin is current, 1 when it is not, so the unit's state and the
  # message agree.
  check = pkgs.writers.writeNuBin "overlay-pin-check" ''
    let result = (^${lib.getExe updateOverlays} --check | complete)
    print $result.stdout
    if $result.exit_code == 0 { return }
    let report = ([$result.stdout $result.stderr] | str join (char nl))
    $report | ^${lib.getExe alertWebhook} "overlay pins behind upstream"
    exit 1
  '';
in {
  options.device.maintenance.overlays = {
    enable = lib.mkEnableOption "the weekly check for overlay pins behind upstream";

    repository = lib.mkOption {
      type = lib.types.str;
      default = "/home/snowyrenard/nixos-config";
      description = "Checkout of this flake that the updater runs in.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "snowyrenard";
      description = "Owner of that checkout, and the account the check runs as.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.overlay-pins = {
      description = "Report overlay packages pinned behind upstream";
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        WorkingDirectory = cfg.repository;
        # Optional, as for the other maintenance jobs: without a webhook the
        # report stays in the journal.
        EnvironmentFile = "-/etc/nixos-alerts/webhook.env";
        ExecStart = lib.getExe check;
      };
    };

    systemd.timers.overlay-pins = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "weekly";
        # A machine that was off on the scheduled day still gets one run.
        Persistent = true;
        # GitHub's API answers unauthenticated requests at sixty an hour per
        # address; the delay keeps four requests away from anything else on the
        # hour.
        RandomizedDelaySec = "1h";
      };
    };
  };
}
