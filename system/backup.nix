# Restic backups of the state on this host that cannot be re-downloaded.
#
# The media itself is deliberately NOT backed up: 3.6 TiB of films and shows
# are re-acquirable, while the databases and configuration that describe them
# are months of clicking. What is captured instead:
#
#   * every SQLite database under the service state directories, dumped with
#     `sqlite3 .backup` - never copied live. A live copy of a WAL database can
#     be torn and restore as corrupt, where `.backup` uses SQLite's own online
#     backup API and is safe while the service keeps running.
#   * the small configuration each service needs to come back: the *arr
#     config.xml files, Jellyfin's config directory, Kavita's appsettings.json,
#     SeerrNG's settings.json, Caddy's certificates (re-issuing those hits
#     Let's Encrypt rate limits) and Transmission's resume data.
#   * the *arr apps' own scheduled backup archives are deliberately NOT copied:
#     the database dumps above already cover those apps, and their compressed
#     zips would deduplicate badly against each other run after run.
#   * the root-only secrets in /etc that a rebuild would otherwise have to
#     recreate by hand: the WireGuard config, Shelfmark's Prowlarr API key and
#     Kavita's TokenKey.
#
# The repository sits on /home, a DIFFERENT physical disk from both /Vault and
# /, so it survives failure of the vault disk. It does NOT survive losing the
# machine: point `repository` at an offsite target (rclone/B2/S3, or a NAS) for
# that, and keep the restic password in a password manager either way - without
# it the repository is unreadable, so it is deliberately NOT stored inside the
# repository it protects.
#
# Restoring, roughly:
#   restic-media-state snapshots            # generated on PATH by the module
#   restic restore latest --target /tmp/restore
#   systemctl stop <service>; copy the database/config back; systemctl start
# A snapshot holds a curated staging tree rather than the original paths, and
# each snapshot's MANIFEST.txt lists exactly what was captured.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Staging lives on /home because sqlite dumps of large *arr databases run to
  # a few hundred MiB and / only has ~14 GiB free.
  stageDir = "/home/.backups/staging";
  repoDir = "/home/.backups/restic-state";
  passwordFile = "/etc/nixos-backup/restic-password";

  # Trees scanned recursively for SQLite databases. Extend this when a new
  # stateful service arrives; a path that does not exist is skipped.
  sqliteRoots = [
    "/var/lib/jellyfin"
    "/var/lib/sonarr"
    "/var/lib/radarr"
    "/var/lib/lidarr"
    "/var/lib/readarr"
    "/var/lib/prowlarr"
    "/var/lib/bazarr"
    "/var/lib/kapowarr"
    "/var/lib/kavita"
    "/var/lib/seerr"
    "/var/lib/shelfmark"
  ];

  # Copied verbatim (file or directory) when present.
  statePaths = [
    "/var/lib/jellyfin/config"
    "/var/lib/sonarr/config.xml"
    "/var/lib/radarr/config.xml"
    "/var/lib/lidarr/config.xml"
    "/var/lib/readarr/config.xml"
    "/var/lib/prowlarr/config.xml"
    "/var/lib/kavita/config/appsettings.json"
    "/var/lib/seerr/settings.json"
    # Bazarr's settings. 1.6 moved them from config.ini to config.yaml, and the
    # API key the dashboard uses lives in whichever one is current.
    "/var/lib/bazarr/config"
    # Caddy's ACME account and issued certificates.
    "/var/lib/caddy"
    # Transmission's resume/torrent state ONLY. The daemon's home also holds
    # .incomplete and Downloads, which currently carry ~3.9 GiB of partial
    # torrent payload - copying that would dwarf everything else here for no
    # restore value whatsoever.
    "/var/lib/transmission/.config/transmission-daemon"
    # Secrets. This file is intentionally absent: see the header.
    "/etc/wireguard"
    "/etc/shelfmark"
    "/etc/kavita"
  ];

  # Flattens an absolute path into one safe filename, so the staging tree needs
  # no directory structure of its own and a restore is a flat copy.
  flatten = p: lib.replaceStrings ["/"] ["_"] (lib.removePrefix "/" p);

  # These two blocks are generated per path IN NIX rather than looped over in
  # shell: the shell loop variable cannot be interpolated by Nix, and mixing
  # the two is how you end up with `$root_` silently expanding to nothing.
  sqliteBlocks =
    lib.concatMapStrings (root: ''
      if [ -d ${lib.escapeShellArg root} ]; then
        while IFS= read -r db; do
          head -c 16 "$db" 2>/dev/null | grep -q "SQLite format 3" || continue
          out="$stage/sqlite/$(printf '%s' "''${db#/}" | tr '/ ' '__')"
          if "$sqlite" "$db" ".timeout 10000" ".backup '$out'" >/dev/null 2>&1 \
            || "$sqlite" "$db" ".timeout 30000" ".backup '$out'" >/dev/null 2>&1; then
            echo "  dumped $db"
          else
            # sqlite3 creates the destination before it fails, and a 0-byte
            # file would restore as a plausible-looking but empty database.
            rm -f "$out"
            echo "  WARNING: could not dump $db" >&2
          fi
        done < <(find ${lib.escapeShellArg root} -maxdepth 4 -type f \
                   \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) \
                   -not -path '*/cache/*' -not -path '*/logs/*' \
                   -not -path '*/transcodes/*' 2>/dev/null)
      fi
    '')
    sqliteRoots;

  stateBlocks =
    lib.concatMapStrings (p: ''
      if [ -e ${lib.escapeShellArg p} ]; then
        # Copied to a temporary name and moved into place only on success, so a
        # half-finished copy is never captured as if it were complete.
        if cp -a ${lib.escapeShellArg p} "$stage/config/${flatten p}.part" 2>/dev/null; then
          mv "$stage/config/${flatten p}.part" "$stage/config/${flatten p}"
          echo "  copied ${p}"
        else
          rm -rf "$stage/config/${flatten p}.part"
          echo "  WARNING: could not copy ${p}" >&2
        fi
      fi
    '')
    statePaths;

  prepareScript = ''
    set -uo pipefail

    stage=${lib.escapeShellArg stageDir}
    sqlite=${pkgs.sqlite}/bin/sqlite3

    rm -rf "$stage"
    mkdir -p "$stage/sqlite" "$stage/config"
    chmod 700 "$stage"

    # 1. SQLite databases, through the online backup API.
    ${sqliteBlocks}
    # 2. Configuration trees, copied as-is.
    ${stateBlocks}
    # 3. A manifest, so a restore never has to guess what a snapshot holds.
    {
      echo "staged:   $(date -Is)"
      echo "host:     $(cat /etc/hostname)"
      echo
      echo "databases:"
      ls -lh "$stage/sqlite" | tail -n +2
      echo
      echo "config:"
      ls -lh "$stage/config" | tail -n +2
    } > "$stage/MANIFEST.txt"

    size="$(du -sm "$stage" | cut -f1)"
    echo "staged $(find "$stage" -type f | wc -l) files, ''${size} MiB"

    # A guard against a future edit silently dragging payload into the snapshot:
    # this state set should stay in the hundreds of MiB. The *arr apps' own
    # scheduled backup archives are deliberately NOT copied - the .backup dumps
    # above already cover the same databases, and their multi-hundred-MiB zips
    # would deduplicate badly against each other.
    if [ "$size" -gt 2048 ]; then
      echo "WARNING: staging is ''${size} MiB; something large is being captured - check the paths above" >&2
    fi
  '';
in {
  config = lib.mkIf config.device.app.jellyfin.enable {
    # The same trick as Kavita's TokenKey: the password cannot live in the
    # world-readable Nix store, and the restic unit fails outright when the file
    # is missing, so generate it once at activation time. The `-s` test keeps it
    # across rebuilds - regenerating it would orphan the existing repository.
    system.activationScripts.restic-password.text = ''
      if [ ! -s ${passwordFile} ]; then
        ${pkgs.coreutils}/bin/install -d -m 0700 $(dirname ${passwordFile})
        tmp="$(${pkgs.coreutils}/bin/mktemp)"
        ${pkgs.coreutils}/bin/head -c 48 /dev/urandom | ${pkgs.coreutils}/bin/base64 --wrap=0 > "$tmp"
        ${pkgs.coreutils}/bin/install -m 0600 "$tmp" ${passwordFile}
        ${pkgs.coreutils}/bin/rm -f "$tmp"
      fi
    '';

    # Root-owned, 0700: the staging tree and the repository both hold secrets
    # (WireGuard keys, API keys, the ACME account key).
    systemd.tmpfiles.rules = [
      "d /home/.backups 0700 root root -"
    ];

    services.restic.backups.media-state = {
      initialize = true;
      repository = "local:${repoDir}";
      passwordFile = passwordFile;

      # The prepare command builds the staging tree; the cleanup command drops
      # it again so nothing stale survives into the next run.
      backupPrepareCommand = prepareScript;
      backupCleanupCommand = ''
        rm -rf ${stageDir}
      '';
      paths = [stageDir];

      # Daily with jitter, so it does not collide with the *arr housekeeping
      # jobs. Persistent means a run missed while the machine was off happens
      # after the next boot.
      timerConfig = {
        OnCalendar = "03:30";
        RandomizedDelaySec = "45m";
        Persistent = true;
      };

      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 6"
      ];

      # Reads a slice of the repository data on every run, not just the
      # metadata: silent bitrot on the backup disk is otherwise invisible until
      # the day a restore is needed.
      checkOpts = ["--read-data-subset=5%"];
    };
  };
}
