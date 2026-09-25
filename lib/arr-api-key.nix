# Reads the API key an *arr application keeps in its own config.xml.
#
# The key is a full admin credential, so it is never copied into the Nix store;
# the three places that need one (the Homepage widget collector, Recyclarr's
# credential files and Soularr's config) all shell out to this instead of each
# re-implementing the same sed.
#
# WHERE config.xml lives depends on how the service is started: Prowlarr is
# launched with -data=/var/lib/prowlarr and keeps it directly there, while
# Sonarr, Radarr and Lidarr nest it under .config/<Project>. Both are tried, so
# callers only pass the state directory.
#
# Prints the key (no trailing newline) and exits 0 when found, exits 1 when not:
# a host where the application has never started simply has no key yet.
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
