# OpenSSH server for remote access.
{ config, lib, ... }: {
  config = lib.mkIf config.device.security.ssh.enable {
    services.openssh.enable = true;
  };
}
