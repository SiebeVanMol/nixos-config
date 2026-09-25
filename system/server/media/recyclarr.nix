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
# config templates:
#
#   Radarr "HD Bluray + WEB"   radarr/templates/hd-bluray-web.yml
#   Radarr "UHD Bluray + WEB"  radarr/templates/uhd-bluray-web.yml
#
# Both are the guides' NON-REMUX variants. The previous pair ("Remux + WEB")
# allowed the Remux tier, which sits at the very top of Radarr's quality order -
# so a 58 GiB remux was the ceiling of the profile and NOTHING smaller could
# ever be accepted as an upgrade. That is why the library is full of 40-90 Mbps
# files that no search will ever replace. Dropping the tier is what makes a
# well-encoded HEVC/AV1 release count as an improvement.
#
# To change profile, take the ids from the matching template in
# https://github.com/recyclarr/config-templates (each is a few lines), or run
# `recyclarr config create -t <template>` to see a full config for it. Note
# that Recyclarr supports Sonarr and Radarr only - Lidarr is not covered by the
# guides, and its profiles stay as they are.
#
# THIS DOES NOT REASSIGN ANYTHING. Recyclarr adds and updates profiles; which
# profile a film uses is per-film data, set in Radarr's own UI. An existing
# remux keeps its old profile until it is moved to one of these, and while it
# keeps it, deleting its file just downloads another remux.
{
  config,
  lib,
  pkgs,
  ...
}: let
  arrKey = import ../../../lib/arr-api-key.nix {inherit pkgs;};

  credentialDir = "/etc/recyclarr";

  sonarrProfiles = [
    {
      # "WEB-1080p". Note there is no Sonarr equivalent of Radarr's "HD Bluray +
      # WEB": the guides go straight from "Remux + WEB" to WEB-only for TV, so
      # dropping the Remux tier means dropping the Bluray tier with it. That is
      # why the reassignment is scoped to series still sitting on a Remux
      # profile - the anime series belong on their own "Anime" profile, where
      # BD sourcing still matters, and they are left alone.
      trash_id = "72dae194fc92bf828f32cde7744e51a1";
      reset_unmatched_scores.enabled = true;
    }
  ];

  radarrProfiles = [
    {
      # "HD Bluray + WEB" - the default target for new movies, and the
      # replacement for "Remux + WEB 1080p": Bluray and WEB-DL encodes, no
      # remux tier.
      trash_id = "d1d67249d3890e49bc12e275d989a7e9";
      reset_unmatched_scores.enabled = true;
    }
    {
      # "UHD Bluray + WEB" - the 2160p equivalent, also without the remux tier,
      # kept for the films that justify 4K. Still 2160p; it just stops ranking
      # a full-bitrate remux above a good encode.
      trash_id = "64fb5f9858489bdac2af690e27c8c42f";
      reset_unmatched_scores.enabled = true;
    }
  ];
in {
  config = lib.mkIf config.device.app.jellyfin.enable {
    system.activationScripts.recyclarr-api-keys.text = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 ${credentialDir}
      for app in sonarr radarr; do
        if key="$(${arrKey}/bin/arr-api-key "/var/lib/$app")"; then
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
      # sync is a handful of API calls.
      schedule = "weekly";
      configuration = {
        sonarr.series = {
          base_url = "http://127.0.0.1:${toString config.device.media.services.sonarr.port}";
          api_key._secret = "${credentialDir}/sonarr-api_key";
          quality_profiles = sonarrProfiles;
          media_management.propers_and_repacks = "do_not_prefer";

          # Prefer the modern codecs over H.264. The Golden Rule group scores
          # x265 positively for this profile; AV1 ships parked in TRaSH's
          # "Unwanted Formats" group, so it is pulled out of there below and
          # scored on its own instead.
          custom_formats = [
            {
              trash_ids = ["15a05bc7c1a36e2b57fd628f8977e2fc"]; # AV1
              assign_scores_to = [
                {
                  name = "WEB-1080p";
                  score = 100;
                }
              ];
            }
            {
              # Language: Not Original, DISALLOWED rather than merely penalised.
              # In the SONARR guide this format is a DEFAULT member of the
              # Language Profiles group, so it has to be excluded from that group
              # below for this score to be the one that applies - otherwise the
              # group would set it and this entry would be a duplicate.
              #
              # -10000 puts the release far below every TRaSH profile's minimum
              # custom format score, so a release advertising a dub is rejected
              # outright rather than merely losing to a better-scoring one. The
              # language formats match markers in the release title, so this is
              # best-effort.
              trash_ids = ["ae575f95ab639ba5d15f663bf019e3e8"];
              assign_scores_to = [
                {
                  name = "WEB-1080p";
                  score = -10000;
                }
              ];
            }
          ];
          custom_format_groups.add = [
            {
              # [Optional] Golden Rule HD - x265 scores positively
              trash_id = "158188097a58d7687dee647e04af0da3";
              assign_scores_to = [{name = "WEB-1080p";}];
            }
            {
              # [Optional] Language Profiles, with "Language: Not Original"
              # excluded. That format is a default member of this group in the
              # Sonarr guide (unlike the Radarr one, where it is optional), and
              # it is scored explicitly above so the disallow value is visible in
              # this file rather than inherited.
              trash_id = "74aff4168620ed49dcc67e92b2c2a5b4";
              assign_scores_to = [{name = "WEB-1080p";}];
              exclude = ["ae575f95ab639ba5d15f663bf019e3e8"]; # Language: Not Original
            }
            {
              # [Unwanted] Unwanted Formats - penalises x264, but AV1 is wanted
              # here, so it is excluded and scored above instead.
              trash_id = "59c3af66780d08332fdc64e68297098f";
              exclude = ["15a05bc7c1a36e2b57fd628f8977e2fc"];
            }
          ];
        };
        radarr.movies = {
          base_url = "http://127.0.0.1:${toString config.device.media.services.radarr.port}";
          api_key._secret = "${credentialDir}/radarr-api_key";
          quality_profiles = radarrProfiles;
          media_management.propers_and_repacks = "do_not_prefer";

          # As for Sonarr: prefer AV1 and x265 over H.264. AV1 gets its own
          # score; x265 comes through the Golden Rule groups below; and
          # "Language: Not Original" is scored explicitly so its disallow value
          # is visible here rather than inherited from a group default.
          custom_formats = [
            {
              trash_ids = ["cae4ca30163749b891686f95532519bd"]; # AV1
              assign_scores_to = [
                {
                  name = "HD Bluray + WEB";
                  score = 100;
                }
                {
                  name = "UHD Bluray + WEB";
                  score = 100;
                }
              ];
            }
            {
              # Language: Not Original, DISALLOWED rather than merely penalised.
              #
              # Every TRaSH profile is grabbed against a minimum custom format
              # score, and -10000 is the magnitude the guides use for "unwanted":
              # the release lands far below that floor, so it is rejected
              # outright instead of merely losing to a better-scoring release.
              # The language formats match markers in the release title, so this
              # is best-effort - it stops releases that ADVERTISE a dub, not one
              # that carries a dub silently.
              #
              # Scored here rather than by selecting it in the Language Profiles
              # group below, so the value that does the disallowing is in this
              # file and cannot be replaced by a group default.
              trash_ids = ["d6e9318c875905d6cfb5bee961afcea9"];
              assign_scores_to = [
                {
                  name = "HD Bluray + WEB";
                  score = -10000;
                }
                {
                  name = "UHD Bluray + WEB";
                  score = -10000;
                }
              ];
            }
          ];
          custom_format_groups.add = [
            {
              # [Optional] Golden Rule HD - the 1080p default's x265 score
              trash_id = "f8bf8eab4617f12dfdbd16303d8da245";
              assign_scores_to = [{name = "HD Bluray + WEB";}];
            }
            {
              # [Optional] Golden Rule UHD - x265 for the 4K exception profile
              trash_id = "ff204bbcecdd487d1cefcefdbf0c278d";
              assign_scores_to = [{name = "UHD Bluray + WEB";}];
            }
            {
              # [Optional] Language Profiles. "Language: Not Original" is
              # deliberately NOT selected: it is scored explicitly above, so its
              # disallow score is visible in this file rather than inherited
              # from whatever the group's default happens to be.
              trash_id = "13856622cf7a6c9925d3a83f8812d679";
              assign_scores_to = [
                {name = "HD Bluray + WEB";}
                {name = "UHD Bluray + WEB";}
              ];
            }
            {
              # [Unwanted] Unwanted Formats - penalises x264, but AV1 is wanted
              # here, so it is excluded and scored above instead.
              trash_id = "a3ac6af01d78e4f21fcb75f601ac96df";
              exclude = ["cae4ca30163749b891686f95532519bd"];
            }
          ];
        };
      };
    };

    # The upstream module drives Recyclarr ONLY from its weekly timer, so a
    # change to the profiles above stays invisible for up to seven days after a
    # switch. That is not hypothetical: removing the Remux tier left Radarr
    # ranking remuxes at the top of the profile, and because the new profiles
    # did not exist yet the reassignment could not run either - so the searches
    # simply re-acquired the remuxes that had just been deleted.
    #
    # Pulling the unit in by multi-user.target makes it also sync at boot and
    # whenever its definition changes, which is what "I changed the profile and
    # rebuilt" ought to mean. Ordered after the applications because it talks to
    # their APIs; if it does lose a boot race, the weekly timer still catches up.
    systemd.services.recyclarr = {
      wantedBy = ["multi-user.target"];
      wants = ["sonarr.service" "radarr.service" "network-online.target"];
      after = ["sonarr.service" "radarr.service" "network-online.target"];
    };
  };
}
