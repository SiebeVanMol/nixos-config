# Reads the API key an *arr application keeps in its own config.xml.
#
# The key is a full admin credential, so it is never copied into the store; the
# Homepage collector, Recyclarr's credentials and Soularr's config all shell out
# to this rather than re-implementing the same sed. config.xml's location depends
# on how the service starts: Prowlarr is launched with -data=/var/lib/prowlarr
# and keeps it there, while Sonarr/Radarr/Lidarr nest it under .config/<Project>.
# Both are tried. Prints the key (no trailing newline), exit 0 found / 1 not.
{pkgs}:
pkgs.writeShellApplication {
  name = "arr-api-key";
  runtimeInputs = [pkgs.coreutils pkgs.gnused];
  text = ''
    dir="''${1:?usage: arr-api-key <state-dir>}"

    for file in "$dir/config.xml" "$dir"/.config/*/config.xml; do
      [ -f "$file" ] || continue
      key="$(sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$file" | head -n 1)"
      if [ -n "$key" ]; then
        printf '%s' "$key"
        exit 0
      fi
    done

    exit 1
  '';
}
