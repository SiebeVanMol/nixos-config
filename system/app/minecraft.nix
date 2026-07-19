{ pkgs, lib, ... }:
let
  mcVersion = "1.21.1";
  forgeVersion = "21.1.234";
  mcVersionUnderscored = lib.replaceStrings [ "." ] [ "_" ] mcVersion;
  forgeVersionUnderscored = lib.replaceStrings [ "." ] [ "_" ] forgeVersion;
  serverVersion = "neoforge-${mcVersionUnderscored}-${forgeVersionUnderscored}";

  atmonsServerPack = pkgs.fetchzip {
    url = "https://mediafilez.forgecdn.net/files/8431/25/ServerFiles-1.1.1.zip";
    stripRoot = false;
    sha256 = "sha256-KpOoctVm2tTNKu/dUNHTfj+Xyh/1iC5fNnRA7t/3K1o=";
  };
in
{
  services.minecraft-servers = {
    enable = true;
    eula = true;

    servers.violet-town = {
      enable = true;
      openFirewall = true;

      package = pkgs.neoforgeServers.${serverVersion}.override {
        jre_headless = pkgs.jdk21_headless;
      };

      serverProperties = {
        difficulty = 3;
        gamemode = "survival";
        motd = "violet town";
        allow-cheats = true;
        allow-flight = true;
        max-tick-time = 180000;
        simulation-distance = 5;
        view-distance = 8;
        pause-when-empty-seconds=60;
      };

      symlinks = {
        "datapacks" = "${atmonsServerPack}/datapacks";
        "user_jvm_args.txt" = "${atmonsServerPack}/user_jvm_args.txt";
        "server-icon.png" = "${atmonsServerPack}/server-icon.png";
      };
      files = {
        "mods" = "${atmonsServerPack}/mods";
        "config" = "${atmonsServerPack}/config";
        "kubejs" = "${atmonsServerPack}/kubejs";
      };
      jvmOpts = "-Xms4G -Xmx16G";
    };
  };
}
