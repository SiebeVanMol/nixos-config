# Mesa graphics drivers (OpenGL/Vulkan) with 32-bit support for Steam/gaming.
{ config, lib, ... }: {
  config = lib.mkIf config.device.hardware.mesa.enable {
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };
  };
}
