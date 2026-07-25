{ config, lib, pkgs, ... }:
let
  cobbleverseMrpack = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/Jkb29YJU/versions/4SKGla61/COBBLEVERSE%201.7.42.mrpack";
    name = "cobbleverse-1.7.42.mrpack";
    hash = "sha256-3K8BBix8OH4O0HIJqrmT4uOycRHnePWDLFJVjSi8zYg=";
  };

  cobbleverse = pkgs.stdenvNoCC.mkDerivation {
    pname = "cobbleverse-modpack";
    version = "1.7.42";
    src = cobbleverseMrpack;
    nativeBuildInputs = [ pkgs.jq pkgs.curl pkgs.cacert pkgs.unzip ];

    dontUnpack = true;
    dontConfigure = true;
    dontFixup = true;

    buildPhase = ''
      set -euo pipefail

      unzip -q "$src" -d pack-src 2>/dev/null || true
      if [ ! -d pack-src ]; then
        unzip -q "$src"
      fi

      # Fix permissions (zip preserves 000 on some files)
      find pack-src -type d -exec chmod 755 {} \;
      find pack-src -type f -exec chmod 644 {} \;

      index_json_path="pack-src/modrinth.index.json"

      while IFS= read -r file; do
        envState=$(echo "$file" | jq -r --arg side "server" '.env[$side] // "required"')
        if [ "$envState" = "unsupported" ]; then
          continue
        fi

        path=$(echo "$file" | jq -r '.path')
        url=$(echo "$file" | jq -r '.downloads[0]')
        mkdir -p "$(dirname "$path")"
        curl -L "$url" > "$path"

        if echo "$file" | jq -e '.hashes.sha512 != null' > /dev/null; then
          expected=$(echo "$file" | jq -r '.hashes.sha512')
          actual=$(${pkgs.coreutils}/bin/sha512sum "$path" | cut -d' ' -f1)
        elif echo "$file" | jq -e '.hashes.sha1 != null' > /dev/null; then
          expected=$(echo "$file" | jq -r '.hashes.sha1')
          actual=$(${pkgs.coreutils}/bin/sha1sum "$path" | cut -d' ' -f1)
        else
          echo "No supported hash for '$path'" >&2
          exit 1
        fi

        if [ "$actual" != "$expected" ]; then
          echo "Hash mismatch for '$path'" >&2
          echo "expected: $expected" >&2
          echo "actual:   $actual" >&2
          exit 1
        fi
      done < <(jq -c '.files[]' "$index_json_path")

      if [ -d pack-src/overrides ]; then
        cp -r pack-src/overrides/. .
      fi

      cp "$index_json_path" ./index.json
    '';

    installPhase = ''
      rm -rf env-vars pack-src
      mkdir -p "$out"
      cp -r . "$out/"
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-MeB3TLCaQYjv5tRdWbiUy1wpKbtjRtzJcvjJa2rw0a0=";
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
        };

        jvmOpts = "-Xms8G -Xmx32G -Dfml.readTimeout=120 -Dfml.connectionTimeout=120";
      };
    };
  };
}
