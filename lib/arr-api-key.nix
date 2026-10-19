# Reads the API key an *arr application keeps in its own config.xml.
#
# The key is a full admin credential, so it is never copied into the store; the
# Homepage collector, Recyclarr's credentials and Soularr's config all shell out
# to this rather than re-implementing the same extraction. config.xml's location
# depends on how the service starts: Prowlarr is launched with
# -data=/var/lib/prowlarr and keeps it there, while Sonarr/Radarr/Lidarr nest it
# under .config/<Project>. Both are tried, in that order.
#
# Prints the key with no trailing newline: exit 0 found, 1 not found. In nushell
# the XML scan is `parse --regex` and the file test is `path exists`, so the
# script carries no sed, coreutils or shell-array handling.
{pkgs}:
pkgs.writers.writeNuBin "arr-api-key" ''
  def main [dir: string] {
    let candidates = ([$"($dir)/config.xml"] | append (glob $"($dir)/.config/*/config.xml"))

    for file in $candidates {
      if not ($file | path exists) { continue }
      let found = (open --raw $file | parse --regex '<ApiKey>(?<key>[^<]+)</ApiKey>')
      if ($found | is-not-empty) {
        print -n ($found | first | get key)
        exit 0
      }
    }

    exit 1
  }
''
