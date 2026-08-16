# Seed caelestia's theme settings into its runtime config, and push the palette
# into kitty (the terminal) so new kitty windows inherit it.
#
# Caelestia OWNS ~/.config/caelestia/shell.json (it writes to it to persist
# settings), so home-manager must NOT manage that file as a read-only symlink.
#
# kitty reads its config (and the included colors.conf) at startup, so new
# windows always pick up the current palette. `kitty @ set-colors` additionally
# repaints already-open windows.
{ lib, pkgs, config, ... }:
let
  kittyColorsPy = ''
    import json, sys
    scheme, out = sys.argv[1], sys.argv[2]
    d = json.load(open(scheme))
    c = d.get('colours', {})
    def hx(k, default='000000'):
        v = c.get(k)
        return '#' + v if v else '#' + default
    def term(i):
        v = c.get('term%d' % i)
        return '#' + v if v else '#000000'
    L = ['background ' + hx('background'), 'foreground ' + hx('onBackground')]
    for i in range(16):
        L.append('color%d %s' % (i, term(i)))
    open(out, 'w').write('\n'.join(L) + '\n')
  '';

  postHook = ''
    SCHEME="$HOME/.local/state/caelestia/scheme.json"
    COLORS="$HOME/.config/kitty/colors.conf"
    if [ -f "$SCHEME" ]; then
      mkdir -p "$HOME/.config/kitty"
      ${pkgs.python3}/bin/python3 - "$SCHEME" "$COLORS" <<'PY'
${kittyColorsPy}
PY
      ${pkgs.kitty}/bin/kitty @ set-colors "$COLORS" 2>/dev/null || true
    fi
    ${pkgs.hyprland}/bin/hyprctl reload
  '';
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
# Launch terminal apps (btop, etc.) with kitty instead of the default foot.
d.setdefault('general', {}).setdefault('apps', {})['terminal'] = ['kitty']
# Drop any home-manager store symlink so caelestia can write to a real file.
if os.path.islink(p) or os.path.exists(p):
    os.remove(p)
with open(p, 'w') as f:
    json.dump(d, f, indent=4)
PY
  '';

  # Write the initial kitty palette so terminals are themed before the first apply.
  home.activation.writeKittyColors = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    SCHEME="$HOME/.local/state/caelestia/scheme.json"
    if [ -f "$SCHEME" ]; then
      mkdir -p "$HOME/.config/kitty"
      ${pkgs.python3}/bin/python3 - "$SCHEME" "$HOME/.config/kitty/colors.conf" <<'PY'
${kittyColorsPy}
PY
    fi
  '';
}
