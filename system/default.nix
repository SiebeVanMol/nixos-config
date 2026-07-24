{ lib, username, pkgs, ... }:
let
  readUuids = path:
    if builtins.pathExists path then
      let
        lines = lib.splitString "\n" (builtins.readFile path);
        matchLine = line: builtins.match ".*/dev/disk/by-uuid/([^\"]+).*" line;
        matched = builtins.filter (x: x != null) (map matchLine lines);
      in map builtins.head matched
    else [];

  hostConfigs = [
    { name = "nixos-desktop"; uuids = readUuids ../hosts/nixos-desktop/hardware-configuration.nix; }
    { name = "nixos-laptop"; uuids = readUuids ../hosts/nixos-laptop/hardware-configuration.nix; }
    { name = "AlexDesktop"; uuids = readUuids ../hosts/AlexDesktop/hardware-configuration.nix; }
  ];

  allPairs = builtins.concatLists (map (h: map (uuid: { inherit uuid; host = h.name; }) h.uuids) hostConfigs);
  uniqueUuids = lib.unique (map (p: p.uuid) allPairs);

  duplicates = builtins.filter (uuid:
    let hosts = builtins.filter (p: p.uuid == uuid) allPairs;
    in builtins.length hosts > 1
  ) uniqueUuids;

  duplicateInfo = map (uuid:
    let hosts = builtins.filter (p: p.uuid == uuid) allPairs;
    in "  ${uuid} appears in: ${lib.concatStringsSep ", " (map (h: h.host) hosts)}"
  ) duplicates;
in {
  imports = [
    ./options.nix
    ./hardware
  ];

  assertions = lib.mkIf (duplicates != []) [{
    assertion = false;
    message = "Duplicate disk UUIDs across hosts (did you copy hardware-configuration.nix?):\n${lib.concatStringsSep "\n" duplicateInfo}";
  }];

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = ["networkmanager" "wheel" "input" "uinput" "video" "render" ];
    shell = pkgs.nushell;
  };

  nix.settings.experimental-features = ["nix-command" "flakes"];

  nix.gc = {
    automatic = lib.mkDefault true;
    dates = lib.mkDefault "weekly";
    options = lib.mkDefault "--delete-older-than 7d";
  };
  nix.settings.auto-optimise-store = true;

  boot.loader.systemd-boot.editor = false;
  services.fstrim.enable = true;

  nixpkgs.config.allowUnfree = true;

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
