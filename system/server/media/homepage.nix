# Homepage itself, and the API-key collector that feeds its widgets.
#
# This file owns the application (unit, environment file, key reader); the tiles
# come from the registry in dashboard.nix. Widget keys are read at runtime from
# each application's own config into a root-only environment file, so the
# world-readable store YAML holds only {{HOMEPAGE_VAR_*}} placeholders.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # The shared *arr key reader; homepage-env.sh calls it instead of keeping its
  # own copy of the config.xml search.
  arrKey = import ../../../lib/arr-api-key.nix {inherit pkgs;};

  # Which applications to collect keys for, from the live registry: the ports and
  # state directories are options, so the script must not name them again. A
  # literal list there meant a fifth application would quietly get no key.
  arrApps = import ../../../lib/arr-apps.nix {inherit lib;};
  arrAppsJSON = pkgs.writeText "homepage-arr-apps.json" (
    builtins.toJSON (arrApps.withPorts config.device.media.services)
  );

  envScript = pkgs.writeShellApplication {
    name = "homepage-env";
    runtimeInputs = [pkgs.coreutils pkgs.python3 pkgs.jq arrKey];
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
    # first; tmpfiles pre-creates it for the case where the script itself cannot
    # (the dashboard then starts with widgets reporting missing keys).
    systemd.tmpfiles.rules = [
      "d /run/homepage-dashboard 0700 root root -"
      "f /run/homepage-dashboard/env 0600 root root -"
    ];

    # systemd reads EnvironmentFile once at start, so a running dashboard never
    # notices regenerated keys. Rather than have one unit restart another (which
    # deadlocks - see the note on homepage-env below), the unit definition is made
    # to depend on the collector: this variable holds its store path, so when the
    # script changes the dashboard's unit changes and the switch restarts it.
    systemd.services.homepage-dashboard.environment.HOMEPAGE_ENV_REV = "${envScript}";

    systemd.services.homepage-env = {
      description = "Collect API keys for the Homepage dashboard";
      before = ["homepage-dashboard.service"];
      wantedBy = ["homepage-dashboard.service"];
      # Which applications to read keys for: the registry's list, so adding one
      # needs no edit to the collector. Top-level `environment`, as the dashboard
      # unit above uses: inside serviceConfig this key is not the NixOS option.
      environment.HOMEPAGE_ARR_APPS = "${arrAppsJSON}";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        ExecStart = lib.getExe envScript;
        # A oneshot's default start timeout is INFINITE, so anything that hangs
        # here hangs `nixos-rebuild switch` with it. The collector is a few file
        # reads and one write; a bounded failure beats a rebuild that never returns.
        TimeoutStartSec = "60s";
      };

      # Do NOT restart homepage-dashboard from here: this unit is ordered Before
      # the dashboard, so an ExecStartPost try-restart deadlocks the switch (the
      # dashboard's start job waits on this unit, which waits on that job).
      # Freshness is handled by HOMEPAGE_ENV_REV on the dashboard instead.
    };
  };
}
