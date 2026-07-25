{ config, lib, pkgs, ... }:
let
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

          "mods/tectonic-3.0.26-fabric-21.1.jar" = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/lWDHr9jE/versions/L87Phsbl/tectonic-3.0.26-fabric-21.1.jar";
            hash = "sha256-ZlO+fLFXTllzzeCoysudednlWpm/c3iTfgxHl5txi2c=";
          };
          "mods/Terralith_1.21.x_v2.6.2.jar" = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/8oi3bsk5/versions/eWDLFabb/Terralith_1.21.x_v2.6.2.jar";
            hash = "sha256-nNTUAv3g9SPltDCsj9R5zgWup6UP4MjCaQH192knIhQ=";
          };
          "mods/regions-unexplored-0.6.2-fabric-21.1.jar" = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/Tkikq67H/versions/SffwLsGY/regions-unexplored-0.6.2-fabric-21.1.jar";
            hash = "sha256-wMLxqDy9wfJSJVgj4zIwrOnbb1/W2gEKc59G96bTpqc=";
          };
          "mods/YungsBetterDungeons-1.21.1-Fabric-5.1.4.jar" = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/o1C1Dkj5/versions/fQ7EjDPE/YungsBetterDungeons-1.21.1-Fabric-5.1.4.jar";
            hash = "sha256-af59k6+hgD12WN8/hhIT+CVfaNTpdtZt3OZvugjRILw=";
          };
          "mods/YungsBetterMineshafts-1.21.1-Fabric-5.1.1.jar" = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/HjmxVlSr/versions/4ybDuGhA/YungsBetterMineshafts-1.21.1-Fabric-5.1.1.jar";
            hash = "sha256-J5SfW64K/v9FdxGltCSCvjAbdryLETbxEg+EhIm7X6Y=";
          };
          "mods/YungsBetterStrongholds-1.21.1-Fabric-5.1.3.jar" = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/kidLKymU/versions/uYZShp1p/YungsBetterStrongholds-1.21.1-Fabric-5.1.3.jar";
            hash = "sha256-HLQSyDqg6Cc9KaESLFeZ6xWkisyPC3cO/kUcUWZH9fg=";
          };
          "mods/YungsBetterOceanMonuments-1.21.1-Fabric-4.1.2.jar" = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/3dT9sgt4/versions/TGK6gpeO/YungsBetterOceanMonuments-1.21.1-Fabric-4.1.2.jar";
            hash = "sha256-TPuyJr0dsXAyrH5zBulO0n8aji8+CftixHaI+KUnrew=";
          };
          "mods/YungsBetterWitchHuts-1.21.1-Fabric-4.1.1.jar" = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/t5FRdP87/versions/bdpPtvTn/YungsBetterWitchHuts-1.21.1-Fabric-4.1.1.jar";
            hash = "sha256-lU/wBN4VFlLZvmngPRuEjW/RWg9fLfFcTOLnZEZ2hec=";
          };
          "mods/YungsApi-1.21.1-Fabric-5.1.6.jar" = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/Ua7DFN59/versions/9aZPNrZC/YungsApi-1.21.1-Fabric-5.1.6.jar";
            hash = "sha256-NvuQOh688VEXRb4tqeUUTx0kZb/3pcF77/00c5ms0bo=";
          };
          "mods/TerraBlender-fabric-1.21.1-4.1.0.8.jar" = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/kkmrDlKT/versions/XNtIBXyQ/TerraBlender-fabric-1.21.1-4.1.0.8.jar";
            hash = "sha256-+H6Up/oSJ3EcP4rqn/rHoU4Me+IS/lDd7pXSxrpyPKw=";
          };
          "mods/ctov-3.6.3.jar" = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/fgmhI8kH/versions/dqaObRbU/%5BFabric%5Dctov-3.6.3.jar";
            hash = "sha256-5EOSXY/k0JLx85Ji+nMYLknjTcv5ylHqqlMGS7ku5lI=";
          };
        };

        jvmOpts = "-Xms8G -Xmx32G -Dfml.readTimeout=120 -Dfml.connectionTimeout=120";
      };
    };
  };
}
