# Fish as nushell's completion engine.
#
# Home Manager has no fish-to-nushell integration: `enableNushellIntegration` is
# an option carapace's module owns, and the fish module only configures fish
# itself. So the nushell side is this closure - nushell calls it on Tab with one
# record, `place.command` being the line at the cursor as words - and the whole
# of fish's completion machinery runs inside a single `fish --command`:
# `complete --do-complete=<line>` is fish's "complete this line" entry point, so
# its bundled completions, git branch and tag logic and ssh-config host readers
# all work without a fish session behind them. Cost is one process per Tab,
# measured at 26 ms median (fish 4.9.3, nushell 0.116.1).
#
# The parsing is fish's output format, not a choice: lines of `value<TAB>
# description`, the description optional, no header. Hence `--flexible` for the
# rows that stop after the value, `--noheaders` because the first row is data,
# and `--no-infer` so a git hash does not come back as a number.
#
# The `update value` block is the one piece of real work: fish escapes paths the
# POSIX way (`my\ file.txt`), which nushell does not parse back, so a value that
# carries a special character and exists on disk is re-quoted with double quotes
# after `~` expansion. Values that are not paths are left alone.
#
# `programs.fish.enable` stays off: it would configure fish as a login shell
# (its own config, its own completions dir). Only the binary is wanted, and
# `default.nix` puts it in `home.packages` for that.
$env.config.completions.external.completer = {|place|
  fish --command $"complete '--do-complete=($place.command | str replace --all "'" "\\'" | str join ' ')'"
  | from tsv --flexible --noheaders --no-infer
  | rename value description
  | update value {|row|
    let value = $row.value
    let need_quote = ['\' ',' '[' ']' '(' ')' ' ' '\t' "'" '"' "`"] | any { $in in $value }
    if ($need_quote and ($value | path exists)) {
      let expanded_path = if ($value starts-with '~') { $value | path expand --no-symlink } else { $value }
      $'"($expanded_path | str replace --all "\"" "\\\"")"'
    } else { $value }
  }
}
