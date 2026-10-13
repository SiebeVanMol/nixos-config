# The dashboard tiles, built from the service registry.
#
# No service names live here: Homepage itself is in homepage.nix, and everything
# else is derived from device.media.services, so a service with a `dashboard`
# entry appears automatically. Each service module decides whether it gets a live
# widget (its API key is obtainable without a human) or just a link.
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
