{ config, lib, username, pkgs, ... }:
let
  extractUuid = dev:
    if lib.isString dev then
      let parts = builtins.match "/dev/disk/by-uuid/(.+)" dev;
      in if parts != null then builtins.head parts else null
    else null;

  fileSystemUuids = builtins.filter (x: x != null) (map (fs: extractUuid fs.device) (builtins.attrValues config.fileSystems));
  swapUuids = builtins.filter (x: x != null) (map (swap: extractUuid swap.device) config.swapDevices);
  configuredUuids = fileSystemUuids ++ swapUuids;

  existingUuids = if builtins.pathExists "/dev/disk/by-uuid"
    then builtins.attrNames (builtins.readDir "/dev/disk/by-uuid")
    else [];

  missingUuids = builtins.filter (uuid: !(builtins.elem uuid existingUuids)) configuredUuids;
in {
  imports = [
    ./options.nix
    ./hardware
  ];

  assertions = [{
    assertion = builtins.length missingUuids == 0;
    message = "Configured disk UUIDs not found on this system (check hardware-configuration.nix):\n"
      + lib.concatStringsSep "\n" (map (uuid: "  - /dev/disk/by-uuid/${uuid}") missingUuids);
  }];

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
