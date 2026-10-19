# Re-colour Hyprland's borders from caelestia's current scheme, without reloading
# the compositor.
#
# This used to be `hyprctl reload`, and that is what broke the cursor in games: a
# reload re-applies the cursor theme and drops pointer state for every surface, so
# any wallpaper change mid-game left the cursor wrong until the compositor was
# restarted. Changing the wallpaper writes a new scheme, so simply picking a
# different picture was enough to trigger it.
#
# Hyprland 0.56 parses Lua, so `hyprctl keyword` refuses ("keyword can't work with
# non-legacy parsers. Use eval."). `hyprctl eval` runs one Lua snippet against the
# running compositor instead: the border takes the new colours and nothing else in
# the session is touched.
#
# HYPRCTL, DCONF and SCHEME are substituted by caelestia.nix.
const hyprctl = "HYPRCTL"
const dconf = "DCONF"
const scheme = "SCHEME"

# home.nix builds the active border from primary and tertiary (c1/c2), so the live
# value has to be that same two-colour gradient; one colour here would look
# different from a fresh login.
#
# Assembled by concatenation rather than interpolation: nushell reads `(` inside
# `$"..."` as a subexpression, so `$"rgb(($primary))"` comes out as `rgbb0c8ec`.
def lua_border [primary: string, second: string] {
  let pair = ([("rgb(" + $primary + ")") ("rgb(" + $second + ")")] | str join '", "')
  'hl.config({general = {col = {active_border = {colors = {"' + $pair + '"}}}}})'
}

# GTK3 has no notion of a light/dark variant - the theme *name* is the switch - and
# caelestia's own GTK step writes 'adw-gtk3-dark' whatever the mode is, so light mode
# would keep dark chrome around the scheme colours. adw-gtk3 ships both variants, so
# pick the one that matches and let gsettings carry it; GTK4 apps need nothing here,
# they read gtk.css and the color-scheme preference that caelestia already writes.
def gtk_theme [mode: string] {
  if $mode != "light" and $mode != "dark" {
    return
  }
  let theme = (if $mode == "light" { "adw-gtk3" } else { "adw-gtk3-dark" })
  let answer = (do -i { ^$dconf write /org/gnome/desktop/interface/gtk-theme $"'($theme)'" | complete })
  if $answer.exit_code != 0 {
    print -e $"theme-apply: dconf write failed: ($answer.stderr | str trim)"
  }
}

def main [] {
  if not ($scheme | path exists) {
    print -e $"theme-apply: ($scheme) is missing, leaving the border alone"
    return
  }

  # The scheme is nested: {name, flavour, mode, variant, colours: {...}}. A file
  # written by a different caelestia version may not carry these keys, and a
  # half-applied gradient is worse than the colours already on screen, so every
  # miss below ends in "leave the border alone".
  # `open` on a .json file already parses it, so it needs --raw: handing a record
  # to `from json` is "only string input data is supported".
  let document = (open --raw $scheme | from json)
  let colours = ($document | get --optional colours)
  if $colours == null {
    print -e "theme-apply: the scheme has no colours block, leaving the border alone"
    return
  }

  let primary = ($colours | get --optional primary | default "")
  let tertiary = ($colours | get --optional tertiary | default "")
  if $primary == "" {
    print -e "theme-apply: the scheme has no primary colour, leaving the border alone"
    return
  }

  let second = (if $tertiary == "" { $primary } else { $tertiary })
  gtk_theme ($document | get --optional mode | default "")

  # `complete` rather than a bare call: hyprctl reports a Lua error on stdout with
  # exit 7, and a bare external call would abort the script before anything is
  # printed, leaving the service log with a failure and no reason in it.
  let run = (do -i { ^$hyprctl eval (lua_border $primary $second) | complete })
  if $run.exit_code != 0 {
    print -e $"theme-apply: hyprctl eval failed: ($run.stdout | str trim)"
  } else if ($run.stdout | str trim) != "ok" {
    print -e $"theme-apply: hyprctl eval said '($run.stdout | str trim)'"
  }
}
