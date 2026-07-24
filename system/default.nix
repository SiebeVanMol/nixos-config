{ username, pkgs, lib, ... }: {
  imports = [
    ./options.nix
    ./hardware
  ];

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = ["networkmanager" "wheel" "input" "uinput" "video" "render" ];
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

  # Put /tmp on tmpfs with a 4G cap instead of the default 50% of RAM.
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "4G";

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
