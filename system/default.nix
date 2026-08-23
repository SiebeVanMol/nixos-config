# Base system configuration shared across all machines.
# Creates the primary user, sets Nix/SSD/locale defaults, and pulls in the option-defined
# hardware and security toggle modules.
{
  username,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./options.nix
    ./hardware
    ./security
    ./app
    ./wm
  ];

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = ["networkmanager" "wheel" "input" "uinput" "video" "render"];
    shell = pkgs.nushell;
  };

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

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ja_JP.UTF-8";
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
  ];
}
