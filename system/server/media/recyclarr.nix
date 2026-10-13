# TRaSH Guides quality profiles, applied by Recyclarr. Profiles are added, never
# assigned: which profile a film uses stays a per-film choice in Radarr's UI.
#
# Keys live in /etc/recyclarr, regenerated from each app's config.xml on every
# activation and injected as systemd credentials - nothing secret in the store.
#
# Deliberately NOT synced: media_naming (Recyclarr 8.7.1 rejects every naming
# format, including the guides' own, and would only add an ERR line per run) and
# quality_definition (it would overwrite Sonarr's curated per-quality size limits
# application-wide). The ids below are the guides' non-remux variants: the Remux
# tier was the ceiling of the old profiles, which is why nothing smaller was ever
# accepted as an upgrade. Ids come from
# https://github.com/recyclarr/config-templates; Sonarr and Radarr only.
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
      # "WEB-1080p". The guides have no Sonarr "HD Bluray + WEB", so dropping the
      # remux tier drops Bluray with it; anime keeps its own profile.
      trash_id = "72dae194fc92bf828f32cde7744e51a1";
      reset_unmatched_scores.enabled = true;
    }
  ];

  radarrProfiles = [
    {
      # "HD Bluray + WEB": Bluray and WEB-DL encodes, no remux tier.
      trash_id = "d1d67249d3890e49bc12e275d989a7e9";
      reset_unmatched_scores.enabled = true;
    }
    {
      # "UHD Bluray + WEB": the 2160p equivalent, also without the remux tier.
      trash_id = "64fb5f9858489bdac2af690e27c8f42f";
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
          # Not an error when the service has never started: config.xml (and the
          # key) appears on first run.
          echo "recyclarr: no API key found for $app yet; skipping" >&2
        fi
      done
    '';

    services.recyclarr = {
      enable = true;
      # Weekly matches the guides' own cadence.
      schedule = "weekly";
      configuration = {
        sonarr.series = {
          base_url = "http://127.0.0.1:${toString config.device.media.services.sonarr.port}";
          api_key._secret = "${credentialDir}/sonarr-api_key";
          quality_profiles = sonarrProfiles;
          media_management.propers_and_repacks = "do_not_prefer";

          # Prefer modern codecs: x265 scores via the Golden Rule group below,
          # and AV1 is pulled out of "Unwanted Formats" and scored on its own.
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
              # "Language: Not Original" DISALLOWED (-10000). Excluded from the
              # Language Profiles group below so this score is the one that
              # applies. It matches title markers, so it is best-effort.
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

          # As for Sonarr: prefer AV1 and x265. AV1 gets its own score, x265 comes
          # through the Golden Rule groups, and "Language: Not Original" is scored
          # explicitly so the disallow value is visible here.
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
              # "Language: Not Original" DISALLOWED (-10000). Scored here rather
              # than by the Language Profiles group below, so the disallowing
              # value cannot be replaced by a group default. It matches markers in
              # the release title, so it stops releases that ADVERTISE a dub, not
              # one carrying a dub silently.
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
              # [Unwanted] Unwanted Formats: penalises x264, but AV1 is wanted.
              trash_id = "a3ac6af01d78e4f21fcb75f601ac96df";
              exclude = ["cae4ca30163749b891686f95532519bd"];
            }
          ];
        };
      };
    };

    # The upstream module runs Recyclarr ONLY from its weekly timer, so a profile
    # change would stay invisible for up to seven days - once enough to re-grab
    # the remuxes that had just been deleted. Wanted by multi-user.target so it
    # also syncs at boot and whenever this unit changes; ordered after the apps
    # because it talks to their APIs.
    systemd.services.recyclarr = {
      wantedBy = ["multi-user.target"];
      wants = ["sonarr.service" "radarr.service" "network-online.target"];
      after = ["sonarr.service" "radarr.service" "network-online.target"];
    };
  };
}
