# The dashboard tiles, built from the service registry.
#
# This file contains no service names. Homepage itself is configured in
# homepage.nix; everything here is derived from device.media.services, so a
# service that registers a `dashboard` entry appears automatically and one that
# does not (like the dashboard) stays off the page.
#
# Which apps get a live widget and which only a link is decided by the service
# module: it sets `dashboard.widget` when its API key is obtainable without a
# human (the *arr family, Bazarr, Seerr, Transmission keep theirs in their own
# config files), and leaves it null otherwise (Jellyfin and Kavita mint theirs
# in their web UIs; create a key there and promote the service to a widget by
# adding one line to its registry entry).
{
  config,
  lib,
  ...
}: let
  registered = config.device.media.services;

  # `admin` entries are bookmarks rather than tiles; everything else is a tile
  # in its group's row.
  tiled = lib.filterAttrs (_: s: s.dashboard != null && s.dashboard.group != "admin") registered;
  admin = lib.filterAttrs (_: s: s.dashboard != null && s.dashboard.group == "admin") registered;

  mkTile = name: s: let
    d = s.dashboard;
    inherit (d) widget;
    title =
      if d.title != null
      then d.title
      else name;
  in {
    ${title} =
      {
        href =
          if d.href != null
          then d.href
          else "http://${name}.lan";
        inherit (d) description;
      }
      // lib.optionalAttrs (d.icon != null) {inherit (d) icon;}
      // lib.optionalAttrs (widget != null) {
        widget =
          {
            inherit (widget) type;
            url =
              if widget.url != null
              then widget.url
              else "http://127.0.0.1:${toString s.port}";
          }
          // lib.optionalAttrs (widget.keyVar != null) {key = "{{${widget.keyVar}}}";};
      };
  };

  group = groupName: let
    entries = lib.mapAttrsToList (name: s: {
      inherit name;
      order = s.dashboard.order;
      site = s;
    }) (lib.filterAttrs (_: s: s.dashboard.group == groupName) tiled);
  in
    map (entry: mkTile entry.name entry.site) (lib.sort (a: b: a.order < b.order) entries);

  # Homepage bookmarks are a list of { <Name> = [ { href; abbr ?; } ]; }.
  adminBookmarks =
    lib.mapAttrsToList (name: s: let
      title =
        if s.dashboard.title != null
        then s.dashboard.title
        else name;
    in {
      ${title} = [
        (
          {
            href =
              if s.dashboard.href != null
              then s.dashboard.href
              else "http://${name}.lan";
          }
          // lib.optionalAttrs (s.dashboard.abbr != null) {inherit (s.dashboard) abbr;}
        )
      ];
    })
    admin;
in {
  config = lib.mkIf config.device.media.enabled {
    services.homepage-dashboard = {
      # Compact tiles: the point is to see status at a glance, not to scroll.
      settings.layout = {
        Library = {
          style = "row";
          columns = 3;
        };
        Acquisition = {
          style = "row";
          columns = 6;
        };
        Downloads = {
          style = "row";
          columns = 2;
        };
      };

      widgets = [
        {
          search = {
            provider = "duckduckgo";
            target = "_blank";
          };
        }
        {
          datetime = {
            text_size = "sm";
            format = {
              dateStyle = "medium";
              timeStyle = "short";
            };
          };
        }
      ];

      services = [
        {"Library" = group "library";}
        {"Acquisition" = group "acquisition";}
        {"Downloads" = group "downloads";}
      ];

      bookmarks = lib.optionals (adminBookmarks != []) [
        {"Tools" = adminBookmarks;}
      ];
    };
  };
}
