{ config, lib, username, ... }: {
  config = lib.mkIf config.device.hardware.tpm.enable {
    security.tpm2 = {
      enable = true;
      pkcs11.enable = true;
      tctiEnvironment.enable = true;
    };
    users.users.${username}.extraGroups = [ "tss" ];
  };
}
