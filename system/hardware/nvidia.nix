{ pkgs, config, ... }: {
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware = {
    graphics = {
      enable = true;
      extraPackages = with pkgs; [ nvidia-vaapi-driver ];
    };
    nvidia = {
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      modesetting.enable = true;

      dynamicBoost.enable = true;

      open = false;

      nvidiaSettings = false;
    };
  };
  environment.variables = {
    LIBVA_DRIVER_NAME = "nvidia";
    VDPAU_DRIVER = "nvidia";
  };

  # NVIDIA requires udev and systemd because of course their driver is buggy.
  services.udev.extraRules = ''
    SUBSYSTEM=="i2c-dev", ACTION=="add",\
      ATTR{name}=="NVIDIA i2c adapter*",\
      TAG+="ddcci",\
      TAG+="systemd",\
      ENV{SYSTEMD_WANTS}+="ddcci@$kernel.service"
  '';

  systemd.services."ddcci@" = {
    scriptArgs = "%i";
    script = ''
      echo Trying to attach ddcci to $1
      i=0
      id=$(echo $1 | cut -d "-" -f 2)
      if ${pkgs.ddcutil}/bin/ddcutil getvcp 10 -b $id; then
        echo ddcci 0x37 > /sys/bus/i2c/devices/$1/new_device
      fi
    '';
    serviceConfig.Type = "oneshot";
  };
}
