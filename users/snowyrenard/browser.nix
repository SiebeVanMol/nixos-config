# Zen Browser (Firefox fork): multi-container workspaces, extensions, custom search engines, bookmarks.
{
  pkgs,
  config,
  nur,
  zen-browser,
  ...
}: let
  # nur is applied to this user's package set rather than to the host's: the
  # add-ons are the only thing taken from it, and a host-level overlay would
  # evaluate the whole NUR tree for every machine.
  firefox-addons = (nur.overlays.default pkgs pkgs).nur.repos.rycee.firefox-addons;
in {
  imports = [zen-browser.homeModules.default];
  home.sessionVariables.BROWSER = "zen-beta";

  programs.zen-browser = {
    enable = true;

    policies = {
      DisableAppUpdate = true;
      DisableFirefoxStudies = true;
      DisablePocket = true;
      DisableTelemetry = true;
      OfferToSaveLogins = true;
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
      };
      Preferences = {
        "widget.use-xdg-desktop-portal.mime-handler" = {
          Value = 0;
          Status = "locked";
        };
        "widget.use-xdg-desktop-portal.file-picker" = {
          Value = 0;
          Status = "locked";
        };
        "gfx.color_management.mode" = 1;
      };
    };

    profiles.${config.home.username} = let
      containers = {
        Work = {
          color = "blue";
          icon = "briefcase";
          id = 1;
        };
        Personal = {
          color = "red";
          id = 2;
        };
      };
    in {
      isDefault = true;

      settings = {
        # Zen's window scheme: 0 = dark, 1 = light, 2 = auto (follow the system
        # colour scheme). The profile had 0, i.e. pinned dark, so the browser ignored
        # caelestia entirely. On 2 it reads `prefers-color-scheme`, which on Wayland
        # comes from the org.freedesktop.appearance portal - the same value caelestia
        # writes when the mode changes (verified: 1 dark, 2 light), so switching mode
        # in the control centre flips the browser live. Web pages follow the same
        # signal because Firefox's content-override default is "system".
        "zen.view.window.scheme" = 2;
        "zen.workspaces.continue-where-left-off" = true;
        "zen.view.compact.hide-tabbar" = true;
        "zen.view.compact.hide-toolbar" = true;
      };

      spacesForce = true;
      spaces = {
        "Work" = {
          id = "91";
          container = containers."Work".id;
        };
        "Media" = {
          id = "92";
          container = containers."Personal".id;
        };
        "Games" = {
          id = "93";
          container = containers."Personal".id;
        };
        "Programming" = {
          id = "94";
          container = containers."Work".id;
        };
      };

      containersForce = true;
      inherit containers;

      extensions = {
        force = true;
        packages = with firefox-addons; [
          ublock-origin
          darkreader
          sponsorblock
          proton-pass
        ];
      };

      search = {
        force = true;
        default = "google";
        engines = {
          nix-packages = {
            name = "Nix Packages";
            urls = [
              {
                template = "https://search.nixos.org/packages";
                params = [
                  {
                    name = "type";
                    value = "packages";
                  }
                  {
                    name = "channel";
                    value = "unstable";
                  }
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];

            icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = ["@np"];
          };

          nix-options = {
            name = "Nix Options";
            urls = [
              {
                template = "https://search.nixos.org/options";
                params = [
                  {
                    name = "channel";
                    value = "unstable";
                  }
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];

            icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = ["@no"];
          };

          nix-wiki = {
            name = "Nix Wiki";
            urls = [
              {
                template = "https://nixos.wiki/wiki/{searchTerms}";
              }
            ];

            icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = ["@nw"];
          };
          home-manager-Options = {
            name = "Home Manager Options";
            urls = [
              {
                template = "https://home-manager-options.extranix.com/{searchTerms}";
                params = [
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                  {
                    name = "release";
                    value = "master";
                  }
                ];
              }
            ];

            icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = ["@hm" "home manager"];
          };

          jisho = {
            name = "Jisho";
            urls = [
              {
                template = "https://jisho.org/search/{searchTerms}";
              }
            ];

            definedAliases = ["@js" "jisho"];
          };

          youtube = {
            name = "Youtube";
            urls = [
              {
                template = "https://youtube.com/results";
                params = [
                  {
                    name = "search_query";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];

            definedAliases = ["@yt" "youtube"];
          };

          wallhaven = {
            name = "Wallhaven";
            urls = [
              {
                template = "https://wallhaven.cc/search";
                params = [
                  {
                    name = "q";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];

            definedAliases = ["@wh" "wallhaven"];
          };

          g2a = {
            name = "G2A";
            urls = [
              {
                template = "https://g2a.com/search";
                params = [
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];

            definedAliases = ["@g" "@g2a" "g2a"];
          };

          protond-db = {
            name = "protondb";
            urls = [
              {
                template = "https://protondb.com/search";
                params = [
                  {
                    name = "q";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];

            definedAliases = ["@pdb"];
          };
        };
      };

      bookmarks = {
        force = true;
        settings = [
          {
            name = "media";
            toolbar = true;
            bookmarks = [
              {
                name = "Youtube";
                url = "https://youtube.com";
              }
              {
                name = "Netflix";
                url = "https://netflix.com";
              }
            ];
          }
          {
            name = "programming";
            toolbar = true;
            bookmarks = [
              {
                name = "Github";
                url = "https://github.com";
              }
            ];
          }
          {
            name = "jisho";
            url = "https://jisho.org";
          }
        ];
      };
    };
  };
}
