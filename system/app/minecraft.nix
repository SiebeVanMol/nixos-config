{ config, lib, pkgs, ... }:
let
  modrinth = { id, version, filename, hash }: pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/${id}/versions/${version}/${lib.strings.escapeURL filename}";
    name = filename;
    inherit hash;
  };

  mrpack = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/Jkb29YJU/versions/4SKGla61/COBBLEVERSE%201.7.42.mrpack";
    name = "cobbleverse-1.7.42.mrpack";
    hash = "sha256-3K8BBix8OH4O0HIJqrmT4uOycRHnePWDLFJVjSi8zYg=";
  };

  cobbleverse = pkgs.stdenvNoCC.mkDerivation {
    pname = "cobbleverse";
    version = "1.7.42";
    src = mrpack;
    nativeBuildInputs = [ pkgs.jq pkgs.curl pkgs.cacert pkgs.unzip ];

    dontUnpack = true;
    dontConfigure = true;
    dontFixup = true;

    buildPhase = ''
      unzip -q "$src" -d pack-src

      find pack-src -type d -exec chmod 755 {} \;
      find pack-src -type f -exec chmod 644 {} \;

      jq -c '.files[]' pack-src/modrinth.index.json > /tmp/files.json
      while IFS= read -r file; do
        envState=$(echo "$file" | jq -r --arg side "server" '.env[$side] // "required"')
        [ "$envState" = "unsupported" ] && continue

        path=$(echo "$file" | jq -r '.path')
        url=$(echo "$file" | jq -r '.downloads[0]')
        mkdir -p "$(dirname "$path")"
        curl -L "$url" > "$path"

        expected=$(echo "$file" | jq -r '.hashes.sha512 // .hashes.sha1')
        actual=$(${pkgs.coreutils}/bin/sha512sum "$path" | cut -d' ' -f1)
        if echo "$file" | jq -e '.hashes.sha512' > /dev/null; then
          [ "$actual" != "$expected" ] && echo "Hash mismatch for $path" >&2 && exit 1
        else
          sha1actual=$(${pkgs.coreutils}/bin/sha1sum "$path" | cut -d' ' -f1)
          [ "$sha1actual" != "$expected" ] && echo "Hash mismatch for $path" >&2 && exit 1
        fi
      done < /tmp/files.json

      [ -d pack-src/overrides ] && cp -r pack-src/overrides/. .

      # Remove mods incompatible with Java 21
      rm -f mods/c2me-opts-natives-math-*
    '';

    installPhase = ''
      rm -rf pack-src env-vars
      mkdir -p "$out"
      cp -r . "$out/"
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-r9urTFPVcxkgzwFJdffzva35H5DjqvHKY4beoJgLOOs=";
  };

  extraMods = {
    # Lithostitched — library required by Tectonic, Terralith, and Regions Unexplored
    "lithostitched-1.7.13-fabric-21.1.jar" = modrinth {
      id = "XaDC71GB"; version = "JWtSqSeY";
      filename = "lithostitched-1.7.13-fabric-21.1.jar";
      hash = "sha256-IGwIZgS8/qWyhi6QBpRwNSy/S01wiLVc36jzRSvtwnA=";
    };
    # Tectonic — world generation, large-scale terrain shaping (mountains, rivers, caves)
    "tectonic-3.0.26-fabric-21.1.jar" = modrinth {
      id = "lWDHr9jE"; version = "L87Phsbl";
      filename = "tectonic-3.0.26-fabric-21.1.jar";
      hash = "sha256-ZlO+fLFXTllzzeCoysudednlWpm/c3iTfgxHl5txi2c=";
    };
    # Terralith — world generation, vanilla-style biome expansion (requires TerraBlender)
    "Terralith_1.21.x_v2.6.2.jar" = modrinth {
      id = "8oi3bsk5"; version = "eWDLFabb";
      filename = "Terralith_1.21.x_v2.6.2.jar";
      hash = "sha256-nNTUAv3g9SPltDCsj9R5zgWup6UP4MjCaQH192knIhQ=";
    };
    # Regions Unexplored — world generation, new biomes, blocks, and vegetation
    "regions-unexplored-0.6.2-fabric-21.1.jar" = modrinth {
      id = "Tkikq67H"; version = "SffwLsGY";
      filename = "regions-unexplored-0.6.2-fabric-21.1.jar";
      hash = "sha256-wMLxqDy9wfJSJVgj4zIwrOnbb1/W2gEKc59G96bTpqc=";
    };
    # YUNG's Better Dungeons — exploration, better dungeon loot and layouts (requires YUNG's API)
    "YungsBetterDungeons-1.21.1-Fabric-5.1.4.jar" = modrinth {
      id = "o1C1Dkj5"; version = "fQ7EjDPE";
      filename = "YungsBetterDungeons-1.21.1-Fabric-5.1.4.jar";
      hash = "sha256-af59k6+hgD12WN8/hhIT+CVfaNTpdtZt3OZvugjRILw=";
    };
    # YUNG's Better Mineshafts — exploration, overhauled mineshaft generation (requires YUNG's API)
    "YungsBetterMineshafts-1.21.1-Fabric-5.1.1.jar" = modrinth {
      id = "HjmxVlSr"; version = "4ybDuGhA";
      filename = "YungsBetterMineshafts-1.21.1-Fabric-5.1.1.jar";
      hash = "sha256-J5SfW64K/v9FdxGltCSCvjAbdryLETbxEg+EhIm7X6Y=";
    };
    # YUNG's Better Strongholds — exploration, overhauled stronghold generation (requires YUNG's API)
    "YungsBetterStrongholds-1.21.1-Fabric-5.1.3.jar" = modrinth {
      id = "kidLKymU"; version = "uYZShp1p";
      filename = "YungsBetterStrongholds-1.21.1-Fabric-5.1.3.jar";
      hash = "sha256-HLQSyDqg6Cc9KaESLFeZ6xWkisyPC3cO/kUcUWZH9fg=";
    };
    # YUNG's Better Ocean Monuments — exploration, overhauled ocean monument generation (requires YUNG's API)
    "YungsBetterOceanMonuments-1.21.1-Fabric-4.1.2.jar" = modrinth {
      id = "3dT9sgt4"; version = "TGK6gpeO";
      filename = "YungsBetterOceanMonuments-1.21.1-Fabric-4.1.2.jar";
      hash = "sha256-TPuyJr0dsXAyrH5zBulO0n8aji8+CftixHaI+KUnrew=";
    };
    # YUNG's Better Witch Huts — exploration, overhauled witch hut generation (requires YUNG's API)
    "YungsBetterWitchHuts-1.21.1-Fabric-4.1.1.jar" = modrinth {
      id = "t5FRdP87"; version = "bdpPtvTn";
      filename = "YungsBetterWitchHuts-1.21.1-Fabric-4.1.1.jar";
      hash = "sha256-lU/wBN4VFlLZvmngPRuEjW/RWg9fLfFcTOLnZEZ2hec=";
    };
    # YUNG's API — library, shared API required by all YUNG structure mods
    "YungsApi-1.21.1-Fabric-5.1.6.jar" = modrinth {
      id = "Ua7DFN59"; version = "9aZPNrZC";
      filename = "YungsApi-1.21.1-Fabric-5.1.6.jar";
      hash = "sha256-NvuQOh688VEXRb4tqeUUTx0kZb/3pcF77/00c5ms0bo=";
    };
    # TerraBlender — library, biome/region API required by Terralith and Regions Unexplored
    "TerraBlender-fabric-1.21.1-4.1.0.8.jar" = modrinth {
      id = "kkmrDlKT"; version = "XNtIBXyQ";
      filename = "TerraBlender-fabric-1.21.1-4.1.0.8.jar";
      hash = "sha256-+H6Up/oSJ3EcP4rqn/rHoU4Me+IS/lDd7pXSxrpyPKw=";
    };
    # ChoiceTheorem's Overhauled Village — exploration, overhauled villages with custom structures and pathing
    "ctov-3.6.3.jar" = modrinth {
      id = "fgmhI8kH"; version = "dqaObRbU";
      filename = "[Fabric]ctov-3.6.3.jar";
      hash = "sha256-5EOSXY/k0JLx85Ji+nMYLknjTcv5ylHqqlMGS7ku5lI=";
    };
    # Distant Horizons — level-of-detail rendering and server-side LOD generation
    "DistantHorizons-3.2.0-b-1.21.1-fabric-neoforge.jar" = modrinth {
      id = "uCdwusMi"; version = "ZpKb4kZp";
      filename = "DistantHorizons-3.2.0-b-1.21.1-fabric-neoforge.jar";
      hash = "sha256-1qepY/eUUBZ4ET4lRdiyXJDhI+9rkla7VxaQfQWeHvU=";
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

        package = pkgs.fabricServers.fabric-1_21_1;

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

        files = {
          "mods" = "${cobbleverse}/mods";
          "config" = "${cobbleverse}/config";
          "config/DistantHorizons.toml" = pkgs.writeText "DistantHorizons.toml" ''
            [world]
            serverLevelGeneration = true

            [common]
            threadPreset = "MINIMAL_IMPACT"
          '';
        } // lib.mapAttrs' (name: drv: lib.nameValuePair "mods/${name}" drv) extraMods;

        jvmOpts = "-Xms8G -Xmx32G -Dfml.readTimeout=120 -Dfml.connectionTimeout=120";
      };
    };
  };
}
