# Collects the API keys Homepage's widgets need and writes them as environment
# variables for the homepage-dashboard unit.
#
# Keys are read at runtime from each application's OWN configuration - the same
# rule the rest of this repository follows, because /nix/store is world readable
# and a widget key is as good as a login. That is also why the widget YAML in
# dashboard.nix refers to them as {{HOMEPAGE_VAR_*}} placeholders.
#
# Anything not found is reported and skipped: a widget whose key is missing shows
# an error in the dashboard, it does not break the unit.
#
# Nushell rather than bash because every step is a file or JSON read: the
# registry arrives as JSON, Bazarr's key is a line to match, and Seerr's is a
# field of a JSON document. The shell version needed jq for the first, an
# embedded Python heredoc for the second and another `python3 -c` for the third.
def main [out?: string = "/run/homepage-dashboard/env"] {
  mkdir ($out | path dirname)
  # systemd reads this file as EnvironmentFile and refuses to start the unit when
  # it is absent, so it is created before anything that can fail.
  "" | save --force $out
  ^chmod 600 $out

  mut lines = []

  # Servarr applications: the key lives in config.xml, and where that file sits
  # depends on how the service runs. The shared `arr-api-key` helper knows both
  # places, so all this loop does is name the environment variable. Which
  # applications exist comes from its registry, handed over as JSON by the
  # module: naming them here meant a new one silently got no key at all.
  let registry = ($env.HOMEPAGE_ARR_APPS? | default "")
  if ($registry | is-empty) {
    print -e "homepage-env: HOMEPAGE_ARR_APPS is not set - no *arr keys collected"
  } else {
    for app in (open $registry | get apps | transpose key value) {
      let dir = ($app.value.dir? | default "")
      if ($dir | is-empty) or not ($dir | path exists) { continue }

      let name = $"HOMEPAGE_VAR_($app.key | str uppercase)_KEY"
      # A missing key exits 1 with nothing on stdout; `complete` keeps that from
      # aborting the whole script, which must still write the other keys.
      let probe = (^arr-api-key $dir | complete)
      let key = ($probe.stdout | str trim)
      if ($probe.exit_code == 0) and not ($key | is-empty) {
        $lines = ($lines | append $"($name)=($key)")
        print $"homepage-env: ($name) supplied"
      } else {
        print -e $"homepage-env: no value found for ($name)"
      }
    }
  }

  # Bazarr keeps its key under [auth] as "apikey", but WHERE depends on version:
  # 1.6 moved settings from config.ini to config.yaml and converts an existing
  # INI on first start, so both file names and both syntaxes have to be accepted
  # ("apikey: value" in YAML, "apikey = value" in INI). Reading the old INI only
  # is exactly why the Bazarr widget reported an API error while every other
  # *arr widget worked.
  let apikey_regex = "(?im)^\\s*apikey\\s*[:=]\\s*[\"\x27]?(?<key>[^\"\x27\\s#]+)"
  mut bazarr_key = ""
  for file in ["/var/lib/bazarr/config/config.yaml" "/var/lib/bazarr/config/config.ini"] {
    if not ($bazarr_key | is-empty) { break }
    if not ($file | path exists) { continue }
    let found = (open --raw $file | parse --regex $apikey_regex)
    if ($found | is-not-empty) { $bazarr_key = ($found | first | get key) }
  }
  if ($bazarr_key | is-empty) {
    print -e "homepage-env: no value found for HOMEPAGE_VAR_BAZARR_KEY"
  } else {
    $lines = ($lines | append $"HOMEPAGE_VAR_BAZARR_KEY=($bazarr_key)")
    print "homepage-env: HOMEPAGE_VAR_BAZARR_KEY supplied"
  }

  # Seerr (and the SeerrNG fork) keep theirs in settings.json under main.apiKey.
  let seerr_settings = "/var/lib/seerr/settings.json"
  if ($seerr_settings | path exists) {
    let key = (open $seerr_settings | get -o main.apiKey | default "")
    if ($key | is-empty) {
      print -e "homepage-env: no value found for HOMEPAGE_VAR_SEERR_KEY"
    } else {
      $lines = ($lines | append $"HOMEPAGE_VAR_SEERR_KEY=($key)")
      print "homepage-env: HOMEPAGE_VAR_SEERR_KEY supplied"
    }
  }

  ($lines | append "" | str join (char nl)) | save --force $out
  ^chmod 600 $out
}
