# Seed caelestia's theme settings into its runtime config.
#
# Caelestia OWNS ~/.config/caelestia/shell.json (it writes to it to persist
# settings), so home-manager must NOT manage that file as a read-only symlink.
# Instead, at activation we merge our theme defaults into the existing file,
# only filling in keys that are not already set, so caelestia can keep writing.
#
# The icon theme is handled statically by home-manager (gtk.iconTheme =
# Papirus-Dark); the only runtime hook here reloads Hyprland so borders follow
# the caelestia scheme.
{ lib, pkgs, config, ... }:
let
  postHook = "${pkgs.hyprland}/bin/hyprctl reload";
in {
  home.activation.seedCaelestiaTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/caelestia"
    ${pkgs.python3}/bin/python3 - "$HOME/.config/caelestia/shell.json" "${postHook}" <<'PY'
import json, os, sys
p, post = sys.argv[1], sys.argv[2]
d = {}
if os.path.exists(p) or os.path.islink(p):
    try:
        with open(p) as f:
            d = json.load(f)
    except Exception:
        d = {}
theme = d.setdefault('theme', {})
theme['enableHypr'] = True
for k in ['enableTerm', 'enableDiscord', 'enableSpicetify', 'enablePandora',
          'enableFuzzel', 'enableBtop', 'enableNvtop', 'enableHtop',
          'enableGtk', 'enableQt', 'enableWarp', 'enableChromium',
          'enableZed', 'enableCava']:
    theme[k] = False
theme['postHook'] = post
theme.pop('iconThemeLight', None)
theme.pop('iconThemeDark', None)
# Drop any home-manager store symlink so caelestia can write to a real file.
if os.path.islink(p) or os.path.exists(p):
    os.remove(p)
with open(p, 'w') as f:
    json.dump(d, f, indent=4)
PY
  '';
}
