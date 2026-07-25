{ config, lib, pkgs, ... }:
let
  mcVersion = "1.21.1";
  forgeVersion = "21.1.234";
  forgeVersionUnderscored = lib.replaceStrings [ "." ] [ "_" ] forgeVersion;
  serverVersion = "neoforge-${lib.replaceStrings [ "." ] [ "_" ] mcVersion}-${forgeVersionUnderscored}";

  modrinth = { id, version, filename, hash }: pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/${id}/versions/${version}/${filename}";
    name = filename;
    inherit hash;
  };

  mods = {
    # Cobblemon — Pokémon mod
    "Cobblemon-neoforge-1.7.3+1.21.1.jar" = modrinth {
      id = "MdwFAVRL"; version = "S1TrAn8c";
      filename = "Cobblemon-neoforge-1.7.3%2B1.21.1.jar";
      hash = "sha256-li1130+2SdlIY6en0TDU0rPeTamzyuTESxzpDzfsDtU=";
    };
    # Create — mechanical engineering and automation
    "create-1.21.1-6.0.10.jar" = modrinth {
      id = "LNytGWDc"; version = "UjX6dr61";
      filename = "create-1.21.1-6.0.10.jar";
      hash = "sha256-74f+Vwnxuh9bi7IKKSW1r7RmnheP1ti/EMFndZ7v43o=";
    };
    # Create: Enchantment Industry — Create addon for automation
    "create-enchantment-industry-2.5.0-preview-alpha1.jar" = modrinth {
      id = "JWGBpFUP"; version = "8XedJhwv";
      filename = "create-enchantment-industry-2.5.0-preview-alpha1.jar";
      hash = "sha256-slzFdpbmom/vFkN9iPP+WiaQCQ5vlyi2xyyj6UXLB+s=";
    };
    # Ars Nouveau — spellcasting and magic
    "ars_nouveau-1.21.1-5.12.1.jar" = modrinth {
      id = "TKB6INcv"; version = "7IK2KsiH";
      filename = "ars_nouveau-1.21.1-5.12.1.jar";
      hash = "sha256-skQSrM5zA7r1xGv0EwumrdXDSQR6bfxEXhrdDNhSj6I=";
    };
    # Ars Creo — Ars Nouveau and Create compatibility
    "ars_creo-1.21.1-5.4.0.jar" = modrinth {
      id = "fZ324GMc"; version = "LqOllHms";
      filename = "ars_creo-1.21.1-5.4.0.jar";
      hash = "sha256-UPD+XF+FUVHBSCwXcuqUwuqtwrDIXJY7ua60IfyAHk8=";
    };
    # Ars Additions — addon for Ars Nouveau
    "ars_additions-1.21.1-21.3.0.jar" = modrinth {
      id = "GYK6Gk8R"; version = "aQ0r5GD2";
      filename = "ars_additions-1.21.1-21.3.0.jar";
      hash = "sha256-5jSj8MOc04AHYIzOGXSnybutfYICv7bHXxfCkB82LJs=";
    };
    # Ars Elemancy — elemental spells and foci for Ars Nouveau
    "ars_elemancy-1.21.1-1.17.jar" = modrinth {
      id = "mR4yp7HM"; version = "LMOUcsOQ";
      filename = "ars_elemancy-1.21.1-1.17.jar";
      hash = "sha256-wJv6rQAXREQOde3W1J6770WC1Wt73SOgYywIxR1pFnQ=";
    };
  };
in
{
  config = lib.mkIf config.device.app.minecraft.enable {
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
          level-name = "cobbleverse-world";
          difficulty = 3;
          gamemode = "survival";
          motd = "Cobbleverse";
          allow-cheats = true;
          allow-flight = true;
          pause-when-empty-seconds = 60;
          players-sleeping-percentage = 0;
        };

        files = lib.mapAttrs' (name: drv: lib.nameValuePair "mods/${name}" drv) mods;

        jvmOpts = "-Xms8G -Xmx32G -Dfml.readTimeout=120 -Dfml.connectionTimeout=120";
      };
    };
  };
}
