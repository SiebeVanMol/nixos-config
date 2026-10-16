"""Write Soularr's config.ini from its upstream template, injecting the two API
keys the activation script read out of Lidarr and slskd.

The template ships in the Soularr package and carries sensible defaults for
everything except credentials and paths, so it is copied and patched rather than
reproduced here - the upstream defaults stay in one place.

The two keys arrive through the environment rather than as arguments: a command
line is readable by every local user out of /proc/<pid>/cmdline, while the
environment of a root process is readable only by root.

Kept as a real file (not an inline heredoc in the Nix string) because Python is
indentation-sensitive and Nix's indentation stripping is exactly the wrong tool
for that: this can be read, run and linted like any other script.
"""

import configparser
import os
import sys


def main():
    if len(sys.argv) != 6:
        sys.exit(
            f"usage: {sys.argv[0]} <template> <out> <lidarr_url> <slskd_url> <download_dir> "
            "(with LIDARR_API_KEY and SLSKD_API_KEY in the environment)"
        )

    template, out, lidarr_url, slskd_url, download_dir = sys.argv[1:]

    lidarr_key = os.environ.get("LIDARR_API_KEY")
    slskd_key = os.environ.get("SLSKD_API_KEY")
    if not lidarr_key or not slskd_key:
        sys.exit("LIDARR_API_KEY and SLSKD_API_KEY must both be set in the environment")

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
