# Mesa graphics drivers (OpenGL/Vulkan) with 32-bit support for Steam/gaming,
# plus system-wide ROCm support for the AMD GPU.
{
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.device.hardware.mesa.enable {
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    # nixpkgs-wide flag: build packages with ROCm support by default
    # (blender, torch, opencv, btop, ...). This is a mass rebuild.
    nixpkgs.config.rocmSupport = true;
  };
}
