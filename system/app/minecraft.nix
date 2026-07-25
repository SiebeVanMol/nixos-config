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
