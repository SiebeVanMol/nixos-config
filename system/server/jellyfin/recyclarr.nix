# TRaSH Guides quality profiles, applied by Recyclarr.
#
# Without this, "quality profile" means whatever the applications defaulted to
# when they were first set up, and the only feedback loop is noticing that a
# 1080p film arrived as an 80 GB remux. Recyclarr keeps the profiles, custom
# formats and per-quality size limits in sync with the TRaSH Guides, which is
# what makes grabs predictable instead of a source of manual searching.
#
# The nixpkgs module does the hard part: the configuration below lives in the
# Nix store with `_secret` placeholders, and the real API keys are injected at
# service start through systemd credentials loaded from /etc/recyclarr. Nothing
# secret is ever written to the store.
#
# Those credential files are regenerated from each application's own config.xml
# on every activation (not only when missing): an application that regenerates
# its key would otherwise leave Recyclarr authenticating with a stale one.
#
# WHAT IT CHANGES, and why this configuration is deliberately conservative:
#
#   * Quality profiles are *added*, not assigned. A new profile named exactly
#     as TRaSH names it appears in Sonarr/Radarr; whether your existing series
#     and films use it is your decision, made one dropdown at a time. Nothing
#     already in the library is rewritten by this  module.
#   * Custom format scores DO apply immediately to future grabs, which is what
#     makes release selection predictable.
#   * media_management sets propers_and_repacks to do_not_prefer, which is what
#     the guides ask for: repack/proper handling then follows the custom format
#     scores instead of an unconditional "prefer and upgrade".
#
#   * media_naming is deliberately absent, and this is NOT a preference: Recyclarr
#     8.7.1 rejects every naming format with "Invalid ... naming format", including
#     the guides' own recommended strings copied verbatim out of
#     docs/json/sonarr/naming/sonarr-naming.json - even a plain "{Series Title} -
#     S{season:00}E{episode:00}" is refused. Shipping it would put an ERR line in
#     the journal on every run for no benefit. Naming therefore stays as it is in
#     both applications; change it in their UIs, or converge it directly through
#     Sonarr/Radarr's own /api/v3/config/naming endpoint if it ever needs to be
#     reproducible.
#   * The app-wide per-quality SIZE LIMITS (`quality_definition`) are
#     deliberately NOT synced. This Sonarr already carries a curated TRaSH
#     setup of its own - 25 custom formats including the Anime BD tiers, and an
#     "Anime" profile - and a Recyclarr preview reported every single quality
#     definition as different, i.e. it would have overwritten those limits
#     across the whole application. Add a `quality_definition` block below if
#     you want the guides to own them as well.
#
# The ids below are the stable TRaSH identifiers, copied from the official
# config templates for these two profiles:
#
#   Radarr "Remux + WEB 2160p"  radarr/templates/remux-web-2160p.yml
#   Sonarr "Remux + WEB 1080p"  sonarr/templates/remux-web-1080p.yml
#
# To change profile, take the ids from the matching template in
# https://github.com/recyclarr/config-templates (each is a few lines), or run
# `recyclarr config create -t <template>` to see a full config for it. Note
# that Recyclarr supports Sonarr and Radarr only - Lidarr and Readarr are not
# covered by the guides, and their profiles stay as they are.
{
  config,
  lib,
  pkgs,
  ...
}: let
  credentialDir = "/etc/recyclarr";

  sonarrProfiles = [
    {
      # "Remux + WEB 1080p"
      trash_id = "fe9470e577c300a5ad9a3274f6d1cdf2";
      reset_unmatched_scores.enabled = true;
    }
  ];

  radarrProfiles = [
    {
      # "Remux + WEB 2160p" - the profile that matches the library's existing
      # taste for full-quality remuxes rather than changing it.
      trash_id = "fd161a61e3ab826d3a22d53f935696dd";
      reset_unmatched_scores.enabled = true;
    }
  ];
in {
  config = lib.mkIf config.device.app.jellyfin.enable {
    system.activationScripts.recyclarr-api-keys.text = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 ${credentialDir}
      for app in sonarr radarr; do
        key=""
        for candidate in "/var/lib/$app/config.xml" /var/lib/$app/.config/*/config.xml; do
          [ -f "$candidate" ] || continue
          key="$(${pkgs.gnused}/bin/sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$candidate" | ${pkgs.coreutils}/bin/head -n 1)"
          [ -n "$key" ] && break
        done
        if [ -n "$key" ]; then
          tmp="$(${pkgs.coreutils}/bin/mktemp)"
          printf '%s' "$key" > "$tmp"
          ${pkgs.coreutils}/bin/install -m 0600 "$tmp" "${credentialDir}/$app-api_key"
          ${pkgs.coreutils}/bin/rm -f "$tmp"
        else
          # Not an error on a host where the service has never started: the
          # application writes config.xml (and therefore its key) on first run.
          echo "recyclarr: no API key found for $app yet; skipping" >&2
        fi
      done
    '';

    services.recyclarr = {
      enable = true;
      # Weekly is the guide's own cadence; the profiles change rarely and a
      # sync is a handful of API calls. `systemctl start recyclarr` runs it on
      # demand after a profile change.
      schedule = "weekly";
      configuration = {
        sonarr.series = {
          base_url = "http://127.0.0.1:8989";
          api_key._secret = "${credentialDir}/sonarr-api_key";
          quality_profiles = sonarrProfiles;
          media_management.propers_and_repacks = "do_not_prefer";
          custom_format_groups.add = [
            {
              # [Optional] Golden Rule HD
              trash_id = "158188097a58d7687dee647e04af0da3";
            }
            {
              # [Optional] Language Profiles
              trash_id = "74aff4168620ed49dcc67e92b2c2a5b4";
            }
          ];
        };
        radarr.movies = {
          base_url = "http://127.0.0.1:7878";
          api_key._secret = "${credentialDir}/radarr-api_key";
          quality_profiles = radarrProfiles;
          media_management.propers_and_repacks = "do_not_prefer";
          custom_format_groups.add = [
            {
              # [Optional] Golden Rule UHD
              trash_id = "ff204bbcecdd487d1cefcefdbf0c278d";
            }
            {
              # [Unwanted] Unwanted Formats
              trash_id = "a3ac6af01d78e4f21fcb75f601ac96df";
            }
          ];
        };
      };
    };
  };
}
