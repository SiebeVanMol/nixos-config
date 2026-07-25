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
    # Tectonic — world generation, large-scale terrain shaping
    "tectonic-3.0.26-neoforge-21.1.jar" = modrinth {
      id = "lWDHr9jE"; version = "vNrkxC3z";
      filename = "tectonic-3.0.26-neoforge-21.1.jar";
      hash = "sha256-NqqbSow5nJlDRgp6WNkUArbWccEKsRsJnC7h11ryMuo=";
    };
    # Terralith — vanilla-style biome expansion (requires TerraBlender)
    "Terralith_1.21.1_v2.6.2_Neoforge.jar" = modrinth {
      id = "8oi3bsk5"; version = "IY93YaEe";
      filename = "Terralith_1.21.1_v2.6.2_Neoforge.jar";
      hash = "sha256-04vTBIl3MbQvbAE83AfggudEEegMdKq87jhSUb6ztUY=";
    };
    # Regions Unexplored — new biomes, blocks, and vegetation
    "regions-unexplored-0.6.2-neoforge-21.1.jar" = modrinth {
      id = "Tkikq67H"; version = "5A8LFnXX";
      filename = "regions-unexplored-0.6.2-neoforge-21.1.jar";
      hash = "sha256-zPMu1xTyck9UQGueAqjW+U2H3FxyOXvDmz1u2PMkEuo=";
    };
    # YUNG's API — library for YUNG structure mods
    "YungsApi-1.21.1-NeoForge-5.1.6.jar" = modrinth {
      id = "Ua7DFN59"; version = "ZB22DE9q";
      filename = "YungsApi-1.21.1-NeoForge-5.1.6.jar";
      hash = "sha256-COHSFpDTITpMYt5rbPefNSevsucuDK0OGEjUbrj2gso=";
    };
    # YUNG's Better Dungeons — better dungeon loot and layouts
    "YungsBetterDungeons-1.21.1-NeoForge-5.1.4.jar" = modrinth {
      id = "o1C1Dkj5"; version = "D6aZn0Em";
      filename = "YungsBetterDungeons-1.21.1-NeoForge-5.1.4.jar";
      hash = "sha256-YYFsO3ydksa0T5Pc6HzrCiKCfyAoXV2cTRDVGdc03gQ=";
    };
    # YUNG's Better Mineshafts — overhauled mineshaft generation
    "YungsBetterMineshafts-1.21.1-NeoForge-5.1.1.jar" = modrinth {
      id = "HjmxVlSr"; version = "Go3nbneL";
      filename = "YungsBetterMineshafts-1.21.1-NeoForge-5.1.1.jar";
      hash = "sha256-ViWTDfsyQIINbk7PVf/ww59wzngvrRF6TUGCURhMe+A=";
    };
    # YUNG's Better Strongholds — overhauled stronghold generation
    "YungsBetterStrongholds-1.21.1-NeoForge-5.1.3.jar" = modrinth {
      id = "kidLKymU"; version = "8U0dIfSM";
      filename = "YungsBetterStrongholds-1.21.1-NeoForge-5.1.3.jar";
      hash = "sha256-qcqy/AFTg2iGI2VpH30hUwmAGu0LOQNRaBtrYKHbe1g=";
    };
    # YUNG's Better Ocean Monuments — overhauled ocean monument generation
    "YungsBetterOceanMonuments-1.21.1-NeoForge-4.1.2.jar" = modrinth {
      id = "3dT9sgt4"; version = "yFjEcj2g";
      filename = "YungsBetterOceanMonuments-1.21.1-NeoForge-4.1.2.jar";
      hash = "sha256-zc+P4OCMdSYQSNQ8btSJiXLSPglt0EolJME28GQWqwI=";
    };
    # YUNG's Better Witch Huts — overhauled witch hut generation
    "YungsBetterWitchHuts-1.21.1-NeoForge-4.1.1.jar" = modrinth {
      id = "t5FRdP87"; version = "AvedwcIe";
      filename = "YungsBetterWitchHuts-1.21.1-NeoForge-4.1.1.jar";
      hash = "sha256-iIsebRraIZgqdav7SvsEDJvCzGh3fsX80Rmbl449T40=";
    };
    # TerraBlender — biome/region API (needed by Terralith and Regions Unexplored)
    "TerraBlender-neoforge-1.21.1-4.1.0.8.jar" = modrinth {
      id = "kkmrDlKT"; version = "6e8GCrLb";
      filename = "TerraBlender-neoforge-1.21.1-4.1.0.8.jar";
      hash = "sha256-DEm170R6fwkQDpohCIinNH+9oKp1MiBjmR9gY7Jf4/k=";
    };
    # ChoiceTheorem's Overhauled Village — overhauled villages
    "ctov-3.6.3.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/fgmhI8kH/versions/ztzRUnQ7/%5BNeoforge%5Dctov-3.6.3.jar";
      name = "ctov-3.6.3.jar";
      hash = "sha256-SBWxm4NUHwnLpVbiImErxd3MMffEuiGY9LTWN2zKiy4=";
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
