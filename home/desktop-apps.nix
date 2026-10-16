# Desktop-facing program settings both users want identically, so they are
# written once here instead of in each users/ programs.nix.
#
# Deliberately not included: programs.btop. Snowy enables it with a package
# override and settings while Alex has the bare package, and those are two
# different intentions rather than a copy that drifted.
{...}: {
  programs.fastfetch = {
    enable = true;
    settings.modules = [
      "title"
      "separator"
      "os"
      "host"
      "kernel"
      "uptime"
      "packages"
      "shell"
      "wm"
      "cpu"
      "gpu"
      "memory"
      "swap"
      "disk"
      "break"
      "colors"
    ];
  };

  programs.mangohud = {
    enable = true;

    settings = {
      no_display = true;
      preset = 3;
      full = true;
    };
  };
}
