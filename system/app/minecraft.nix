# Neoforge Minecraft server (violet-town) with Atmons modpack and custom gamerules datapack.
{ config, lib, pkgs, ... }:
let
  mcVersion = "1.21.1";
  forgeVersion = "21.1.234";
  mcVersionUnderscored = lib.replaceStrings [ "." ] [ "_" ] mcVersion;
  forgeVersionUnderscored = lib.replaceStrings [ "." ] [ "_" ] forgeVersion;
  serverVersion = "neoforge-${mcVersionUnderscored}-${forgeVersionUnderscored}";

  atmonsServerPack = pkgs.fetchzip {
    url = "https://mediafilez.forgecdn.net/files/8431/25/ServerFiles-1.1.1.zip";
    stripRoot = false;
    sha256 = "sha256-KpOoctVm2tTNKu/dUNHTfj+Xyh/1iC5fNnRA7t/3K1o=";
  };

  modsWithoutBCC = pkgs.runCommand "mods-no-bcc" { } ''
    cp -r --no-preserve=mode ${atmonsServerPack}/mods $out
    rm -f $out/better-compatability-checker-neoforge-21.1.8.jar
  '';

  # Datapack that disables mobGriefing on world load.
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
  config = lib.mkIf config.device.app.minecraft.enable {
    users.users.minecraft.extraGroups = [ "users" ];
    services.minecraft-servers = {
      enable = true;
      eula = true;

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

        jvmOpts = "-Xms8G -Xmx32G -Dfml.readTimeout=120 -Dfml.connectionTimeout=60";
      };
    };
  };
}

