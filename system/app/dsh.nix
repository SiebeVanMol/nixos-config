# dsh (DeepSeek shell) web UI.
# Runs the dsh web server as a systemd service and exposes it on the LAN
# through Caddy as http://deepseek.lan.
{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf config.device.app.dsh.enable {
    systemd.services.dsh-web = {
      description = "dsh (DeepSeek shell) web UI";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        ExecStart = "${pkgs.llm-agents.dsh}/bin/dsh web --host 127.0.0.1 --port ${toString config.device.app.dsh.port}";
        Restart = "on-failure";
      };
    };

    # Make deepseek.lan resolve to this machine so the Caddy vhost works.
    networking.hosts = lib.mkIf config.device.security.reverse-proxy.enable {
      "127.0.0.1" = ["deepseek.lan"];
    };

    services.caddy.virtualHosts = lib.mkIf config.device.security.reverse-proxy.enable {
      "http://deepseek.lan" = {
        extraConfig = "reverse_proxy 127.0.0.1:${toString config.device.app.dsh.port}";
      };
    };
  };
}
