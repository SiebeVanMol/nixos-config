{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  nixpkgs.config.rocmSupport = true;

  # Overclocking
  services.lact.enable = true;
  hardware.amdgpu.overdrive = {
    enable = true;
    ppfeaturemask = "0xffffffff";
  };
}
