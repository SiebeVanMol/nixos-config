# Mesa graphics drivers (OpenGL/Vulkan) with 32-bit support for Steam/gaming.
{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf config.device.hardware.mesa.enable {
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
      # Expose the Vulkan loader at the stable /run/opengl-driver/lib path so
      # non-FHS processes (e.g. GE-Proton's vulkan.py, which does
      # CDLL('libvulkan.so.1')) can find libvulkan.so.1 via LD_LIBRARY_PATH.
      # Without this the loader only exists inside the hash-pinned nix store.
      extraPackages = with pkgs; [vulkan-loader];
    };
  };
}
