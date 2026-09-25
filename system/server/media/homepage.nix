# Homepage itself, and the API-key collector that feeds its widgets.
#
# This file owns the application: the unit, its environment file, and the
# helper that reads each service's key at runtime. The tiles are built from the
# registry in dashboard.nix, so adding a service does not touch this file.
#
# Secrets: Homepage's widget configuration wants an API key per application, and
# its config lives in the world-readable Nix store. So the generated YAML
# contains only {{HOMEPAGE_VAR_*}} placeholders, and homepage-env.sh reads the
# real keys out of each application's own configuration at runtime into a
# root-only environment file. Losing that file costs nothing but a warning in
# the journal; it is regenerated on every start of the unit.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # The shared *arr key reader; homepage-env.sh calls it instead of keeping its
  # own copy of the config.xml search.
  arrKey = import ../../../lib/arr-api-key.nix {inherit pkgs;};

  envScript = pkgs.writeShellApplication {
    name = "homepage-env";
    runtimeInputs = [pkgs.coreutils pkgs.python3 arrKey];
    text = builtins.readFile ./homepage-env.sh;
  };

  envFile = "/run/homepage-dashboard/env";
in {
  config = lib.mkIf config.device.media.enabled {
    # The dashboard is a service like any other, so it registers itself and
    # gets a home.lan vhost from proxy.nix. It has no tile on itself.
    device.media.services.home = {
      port = 8082;
      dashboard = null;
    };

    services.homepage-dashboard = {
      enable = true;
      listenPort = 8082;

      # Homepage refuses requests whose Host header it does not recognise, and
      # behind Caddy that header is the *.lan name rather than the port.
      allowedHosts = "home.lan,127.0.0.1:8082,localhost:8082";

      # The keys, read at runtime by homepage-env.service below.
      environmentFiles = [envFile];

      settings.title = "Rat Nest";
    };

    # The unit fails outright when EnvironmentFile is missing, so this must run
    # first - and systemd's tmpfiles pre-creates the file for the case where the
    # script itself cannot (the dashboard then starts with widgets reporting
    # missing keys rather than not starting at all).
    systemd.tmpfiles.rules = [
      "d /run/homepage-dashboard 0700 root root -"
      "f /run/homepage-dashboard/env 0600 root root -"
    ];

    # systemd reads EnvironmentFile once, at start: a dashboard that is already
    # running never notices regenerated keys. Rather than have one unit restart
    # another (which deadlocks - see the note on homepage-env above), the unit
    # definition itself is made to depend on the collector: this variable holds
    # the collector's store path, so whenever that script changes, the
    # dashboard's unit changes with it and the switch restarts the dashboard
    # for us. That covers exactly the case that caused the stale Prowlarr key.
    systemd.services.homepage-dashboard.environment.HOMEPAGE_ENV_REV = "${envScript}";

    systemd.services.homepage-env = {
      description = "Collect API keys for the Homepage dashboard";
      before = ["homepage-dashboard.service"];
      wantedBy = ["homepage-dashboard.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        ExecStart = lib.getExe envScript;
        # A oneshot's default start timeout is INFINITE, so anything that hangs
        # in this unit hangs `nixos-rebuild switch` with it - which is precisely
        # how the deadlock above presented. The collector is a few file reads
        # and one write; if it cannot finish in a minute something is wrong, and
        # a bounded failure is far better than a rebuild that never returns.
        TimeoutStartSec = "60s";
      };

      # NOTE: this unit must never restart homepage-dashboard itself. That was
      # tried, and it deadlocks the whole switch: this unit is ordered Before
      # the dashboard, so the dashboard's start job waits for this unit to
      # finish, while an ExecStartPost here doing `systemctl try-restart
      # homepage-dashboard` waits for that very job. A oneshot has no start
      # timeout, so both hang until something external intervenes.
      #
      # Freshness is handled the other way round instead - see the
      # HOMEPAGE_ENV_REV environment variable on the dashboard above.
    };
  };
}
