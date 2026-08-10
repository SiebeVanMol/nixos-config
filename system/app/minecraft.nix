{ pkgs, lib, ... }:
let
  mcVersion = "1.21.1";
  mcVersionUnderscored = lib.replaceStrings [ "." ] [ "_" ] mcVersion;
  serverVersion = "fabric-${mcVersionUnderscored}";

  # Stock COBBLEVERSE 1.7.42 pack, fetched directly from Modrinth. When a new pack
  # version is released, bump the mrpack URL and update the hash (set a dummy hash and
  # copy the "got" value reported by `nix-instantiate --eval --strict`).
  cobbleversePack = builtins.fetchTarball {
    url = "https://cdn.modrinth.com/data/Jkb29YJU/versions/4SKGla61/COBBLEVERSE%201.7.42.mrpack";
    sha256 = "0a4zs1bmp1g3sv6f83jkpy28kpspdza03zlwqdazq68jnv2ywkfq";
  };

  # Server mods, downloaded from Modrinth/CurseForge with pinned hashes.
  # The stock Cobbleverse mod list (server-needed mods only).
  serverModsList = import ./minecraft/cobbleverse-mods.nix;

  # voxyworldgenv2 (compiled from source): the server-side LOD solution. It generates
  # vanilla chunks around players on the server and streams their voxel data straight
  # to voxyworldgenv2 clients over its own channel. voxy itself is NOT needed on the
  # server: it is only a renderer/ingest target on the client, and the client never
  # generates when connected to a dedicated server, so no Chunky pre-generation either.
  voxyMods = import ./minecraft/voxy.nix { inherit pkgs; };

  # cobblemon-battle-positions is shipped as a pack override (no standalone Modrinth/CF
  # project), so it comes from the pack's own overrides folder.
  serverMods = pkgs.runCommand "cobbleverse-mods" { } (
    "mkdir -p $out\n"
    + lib.concatStringsSep "\n" (map (m:
      "cp ${pkgs.fetchurl {
        url = m.url;
        hash = m.hash;
        name = lib.strings.sanitizeDerivationName m.file;
      }} $out/${lib.escapeShellArg m.file}"
    ) serverModsList)
    + "\ncp ${cobbleversePack}/overrides/mods/cobblemon-battle-positions-1.1.3.jar $out/cobblemon-battle-positions-1.1.3.jar"
    + "\ncp ${voxyMods}/VoxyWorldGenV2-2.2.4.jar $out/VoxyWorldGenV2-2.2.4.jar"
  );

  # Pack overrides (configs, datapacks) from the stock pack's modrinth release, plus the
  # PokeCenterPCs datapack which ships as a separate file in the pack's modrinth index.
  cobbleverseOverrides = pkgs.runCommand "cobbleverse-overrides" { } ''
    mkdir -p $out
    cp -r --no-preserve=mode ${cobbleversePack}/overrides/config $out/config
    cp -r --no-preserve=mode ${cobbleversePack}/overrides/datapacks $out/datapacks
    cp ${pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/uVBAvWbW/versions/xclC5R0W/PokeCenter_PCs_1.1.zip";
      sha512 = "28db0a9d92f2fabd3099cd57b663222f7357ac4b66fd72afd4e3c50d5714f658caa4690a402908cc19587a9475cd90ae25ffed05d9e6a71a20ab9212b441783e";
    }} $out/datapacks/PokeCenterPCs-DP.zip
  '';

  serverIcon = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/Jkb29YJU/581ecf54530972afb18a04660afd820f2f24f6c7.png";
    sha512 = "88798ae8e6765c83ff9333299c22fec8695a94e9c8c1b5db574424645a5b409e120dc3755096030d2c9798b9fb645d566e129b3308f5d13ef9004ecf24dd6089";
  };

  # voxyworldgenv2 server-side generation config: generate LOD chunks out to a 256
  # chunk radius around each player, heavily throttled so it never starves the tick.
  # The client-side equivalent lives in the modpack instance, not here.
  voxyworldgenv2Config = pkgs.writeText "voxyworldgenv2.json" (builtins.toJSON {
    enabled = true;
    showF3MenuStats = true;
    generationRadius = 256;
    update_interval = 20;
    maxQueueSize = 20000;
    maxActiveTasks = 20;
  });

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
        gamerule keepInventory true
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

      package = pkgs.fabricServers.${serverVersion}.override {
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
        players-sleeping-percentage = 1;
      };

      symlinks = {
        "server-icon.png" = serverIcon;
      };

      files = {
        "mods" = serverMods;
        "config" = "${cobbleverseOverrides}/config";
        "config/voxyworldgenv2.json" = voxyworldgenv2Config;
        "datapacks" = "${cobbleverseOverrides}/datapacks";
        "world/datapacks/gamerules" = gameRulesDatapack;
      };

      jvmOpts = "-Xms4G -Xmx12G -XX:+UseZGC -XX:+DisableExplicitGC -XX:+PerfDisableSharedMem";
    };
  };
}
