{
  services.minecraft-servers = {
    enable = true;
    eula = true;

    servers.violet-town = {
      enable = true;
      openFirewall = true;

      jvmOpts = "-Xms4096M -Xmx8192M";
    };
  };
}

