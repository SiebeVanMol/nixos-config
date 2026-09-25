"""Write Soularr's config.ini from its upstream template, injecting the two API
keys the activation script read out of Lidarr and slskd.

The template ships in the Soularr package and carries sensible defaults for
everything except credentials and paths, so it is copied and patched rather than
reproduced here - the upstream defaults stay in one place.

Kept as a real file (not an inline heredoc in the Nix string) because Python is
indentation-sensitive and Nix's indentation stripping is exactly the wrong tool
for that: this can be read, run and linted like any other script.
"""

import configparser
import sys


def main():
    if len(sys.argv) != 8:
        sys.exit(f"usage: {sys.argv[0]} <template> <out> <lidarr_url> <slskd_url> <download_dir> <lidarr_key> <slskd_key>")

    template, out, lidarr_url, slskd_url, download_dir, lidarr_key, slskd_key = sys.argv[1:]

    config = configparser.ConfigParser()
    if not config.read(template):
        sys.exit(f"could not read the Soularr config template at {template}")

    config["Lidarr"]["api_key"] = lidarr_key
    config["Lidarr"]["host_url"] = lidarr_url
    config["Lidarr"]["download_dir"] = download_dir
    config["Lidarr"]["disable_sync"] = "False"

    config["Slskd"]["api_key"] = slskd_key
    config["Slskd"]["host_url"] = slskd_url
    config["Slskd"]["url_base"] = "/"
    config["Slskd"]["download_dir"] = download_dir

    with open(out, "w", encoding="utf-8") as handle:
        config.write(handle)


if __name__ == "__main__":
    main()
