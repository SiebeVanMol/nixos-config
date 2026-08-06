{ pkgs, lib, ... }:
let
  mcVersion = "1.21.1";
  forgeVersion = "21.1.248";
  mcVersionUnderscored = lib.replaceStrings [ "." ] [ "_" ] mcVersion;
  forgeVersionUnderscored = lib.replaceStrings [ "." ] [ "_" ] forgeVersion;
  serverVersion = "neoforge-${mcVersionUnderscored}-${forgeVersionUnderscored}";

  atmonsServerPack = pkgs.fetchzip {
    url = "https://mediafilez.forgecdn.net/files/8572/602/ServerFiles-1.2.0.zip";
    stripRoot = false;
    sha256 = "sha256-TaNQCmeA6TlY0xlxp7S8CFzYpm7rAicwV8f5wZNeoMY=";
  };

  modsWithoutBCC = pkgs.runCommand "mods-no-bcc" { } ''
    cp -r --no-preserve=mode ${atmonsServerPack}/mods $out
    rm -f $out/better-compatability-checker-neoforge-21.1.8.jar
  '';

  gameRulesDatapack = pkgs.linkFarm "gamerules-datapack" [
    {
      name = "pack.mcmeta";
      path = pkgs.writeText "pack.mcmeta" (builtins.toJSON {
        pack = {
          pack_format = 48;
          description = "Custom gamerules";
        };
      });
    }
    {
      name = "data/gamerules/function/load.mcfunction";
      path = pkgs.writeText "load.mcfunction" ''
        gamerule mobGriefing false
      '';
    }
    {
      name = "data/minecraft/tags/function/load.json";
      path = pkgs.writeText "load.json" (builtins.toJSON {
        values = [ "gamerules:load" ];
      });
    }
  ];
in
{
  users.users.minecraft.extraGroups = [ "users" ];
  services.minecraft-servers = {
    enable = true;
    eula = true;

    dataDir = "/Vault/minecraft";
    
    servers.violet-town = {
      enable = true;
      openFirewall = true;

      package = pkgs.neoforgeServers.${serverVersion}.override {
        jre_headless = pkgs.jdk21_headless;
      };

      serverProperties = {
        difficulty = 3;
        gamemode = "survival";
        motd = "violet town";
        allow-cheats = true;
        allow-flight = true;
        max-tick-time = 180000;
        simulation-distance = 5;
        view-distance = 8;
        pause-when-empty-seconds = 60;
        players-sleeping-percentage = 0;
      };

      symlinks = {
        "datapacks" = "${atmonsServerPack}/datapacks";
        "user_jvm_args.txt" = "${atmonsServerPack}/user_jvm_args.txt";
        "server-icon.png" = "${atmonsServerPack}/server-icon.png";
      };

      files = {
        "mods" = "${modsWithoutBCC}";
        "config" = "${atmonsServerPack}/config";
        "kubejs" = "${atmonsServerPack}/kubejs";
        "world/datapacks/atmons" = "${atmonsServerPack}/datapacks";
        "world/datapacks/gamerules" = gameRulesDatapack;
        "config/connectivity-server.toml" = pkgs.writeText "connectivity-server.toml" ''
          [timeouts]
          readTimeout = 120
          connectionTimeout = 60
        '';
      };

      jvmOpts = "-Xms10G -Xmx20G -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 -Dfml.readTimeout=120 -Dfml.connectionTimeout=60";
    };
  };
}
