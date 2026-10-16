# Host feature toggles, derived from the tree instead of listed here.
#
# Every module in these directories is a feature, and its file name is its
# option name: system/hardware/bluetooth.nix is device.hardware.bluetooth.enable.
# Adding a feature is therefore dropping the module in and naming the flag in the
# hosts that want it - this file does not change, and neither does a host's list
# of options need a declaration to exist first.
#
# The toggle's description is the module's own first comment line, up to a colon,
# so what a feature does stays in the file that does it.
#
# A module earns a toggle by reading one: its own option path has to appear in
# it. That is what keeps the deliberately unconditional modules here
# unconditional - wm/fonts.nix, wm/pipewire.nix and wm/wayland.nix apply on every
# host, and security/web-jails.nix gates on two OTHER features (Jellyfin and the
# reverse proxy) rather than on a flag of its own.
#
# The four app features whose modules live under system/server/ declare their
# enable in place, because their file names and their option names are different
# things (media/navidrome.nix is device.app.music): jellyfin, music, ai,
# minecraft. Everything else about those stacks is declared in their own modules
# for the same reason.
{lib, ...}: let
  areas = ["app" "hardware" "security" "wm"];

  modulesIn = area:
    builtins.filter (f: lib.hasSuffix ".nix" f) (
      builtins.attrNames (builtins.readDir (./. + "/${area}"))
    );

  # The module's first comment line, up to a colon: enough to say what it is
  # without repeating the file's longer explanation.
  describe = text: let
    first = builtins.head (lib.splitString "\n" text);
    comment = builtins.match "[[:space:]]*#[[:space:]]*(.*)" first;
  in
    if comment == null
    then null
    else builtins.head (lib.splitString ": " (builtins.head comment));

  toggle = area: file: let
    stem = lib.removeSuffix ".nix" file;
    text = builtins.readFile (./. + "/${area}/${file}");
    name = describe text;
  in
    lib.optional (lib.hasInfix "device.${area}.${stem}" text) {
      name = stem;
      value = {
        enable = lib.mkEnableOption (
          if name == null
          then "the feature in system/${area}/${file}"
          else name
        );
      };
    };

  areaToggles = area: builtins.listToAttrs (builtins.concatMap (toggle area) (modulesIn area));
in {
  options.device = builtins.listToAttrs (map (area: {
      name = area;
      value = areaToggles area;
    })
    areas);
}
