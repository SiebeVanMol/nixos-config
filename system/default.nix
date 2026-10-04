# Base system configuration shared across all machines.
# Creates a NixOS account for every user on the host, sets Nix/SSD/locale
# defaults, and pulls in the option-defined hardware and security toggle modules.
{
  usernames,
  pkgs,
  lib,
  ...
}: let
  # Glob a directory of modules instead of giving each one a default.nix that
  # only forwards to this same helper. `server` is the exception: it imports
  # subdirectories as well as files, which importDir does not do.
  importDir = import ../lib/import-dir.nix {inherit lib;};
in {
  imports =
    [
      ./options.nix
      ./server
    ]
    # Host-level maintenance: restic backups of the service state and secrets
    # (backup.nix), SMART/btrfs/capacity/service monitoring (monitoring.nix),
    # and the periodic disk housekeeping plus its weekly report (reclaim.nix).
    ++ importDir ./maintenance
    ++ importDir ./hardware
    ++ importDir ./security
    ++ importDir ./app
    ++ importDir ./wm;

  # Create a normal NixOS user for each user listed on the host. Base group
  # memberships that every desktop user needs apply to all of them.
  users.users = lib.genAttrs usernames (username: {
    isNormalUser = true;
    description = username;
    home = "/home/${username}";
    createHome = true;
    extraGroups = ["networkmanager" "wheel" "input" "uinput" "video" "render"];
    shell = pkgs.nushell;
  });

  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Do garbage collection weekly to keep disk usage low.
  nix.gc = {
    automatic = lib.mkDefault true;
    dates = lib.mkDefault "weekly";
    options = lib.mkDefault "--delete-older-than 7d";
  };
  nix.settings.auto-optimise-store = true;

  # Prevent editing boot parameters at boot.
  boot.loader.systemd-boot.editor = false;

  # Periodic SSD TRIM.
  services.fstrim.enable = true;

  # Allow unfree packages.
  nixpkgs.config.allowUnfree = true;

  # Select internationalisation properties. Every locale category that is a
  # formatting or classification choice is Japanese: dates, numbers, currency,
  # paper size, addresses, collation and character classes. The one category
  # deliberately left alone is LC_MESSAGES, which follows i18n.defaultLocale
  # (en_US.UTF-8), so the UI and tools like `make` speak English. Do not set
  # LC_MESSAGES here and never set LC_ALL, since either would undo that.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ja_JP.UTF-8";
    LC_COLLATE = "ja_JP.UTF-8";
    LC_CTYPE = "ja_JP.UTF-8";
    LC_IDENTIFICATION = "ja_JP.UTF-8";
    LC_MEASUREMENT = "ja_JP.UTF-8";
    LC_MONETARY = "ja_JP.UTF-8";
    LC_NAME = "ja_JP.UTF-8";
    LC_NUMERIC = "ja_JP.UTF-8";
    LC_PAPER = "ja_JP.UTF-8";
    LC_TELEPHONE = "ja_JP.UTF-8";
    LC_TIME = "ja_JP.UTF-8";
  };
  environment.systemPackages = with pkgs; [
    helix
    git
    # smartd is already enabled, but its tools were only reachable via the
    # store path; keep `smartctl` on PATH for checking drive health.
    smartmontools
  ];
}
