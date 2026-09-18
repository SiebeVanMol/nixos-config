# overlays/mangohud-workarounds.nix
#
# Wrappers for packages that coredump when the MangoHud / obs-vkcapture Vulkan
# layers get injected into them.
#
# `programs.mangohud.enableSessionWide` (users/snowyrenard/programs.nix)
# exports MANGOHUD=1 / MANGOHUD_DLSYM=1, and users/snowyrenard/home.nix adds
# OBS_VKCAPTURE=1. Those variables are what switches the implicit Vulkan layers
# shipped by the mangohud and obs-vkcapture packages on/off (each layer
# manifest declares them as its "enable_environment"), so every Vulkan process
# in the session loads libMangoHud.so.
#
# MangoHud 0.8.4 then crashes while handling vkCreateDevice from certain
# callers: its overlay_CreateDevice null-dereferences inside the loader's
# vkSetDeviceDispatch (Vulkan-Loader 1.4.357). Qt apps hit that path at
# startup, because constructing a QMediaPlayer makes the Qt ffmpeg backend
# probe Vulkan hardware-decode devices:
#
#   QMediaPlayer ctor -> QFFmpeg HWAccel::decodingDeviceTypes
#   -> av_hwdevice_ctx_create (libavutil) -> vkCreateDevice
#   -> overlay_CreateDevice (libMangoHud) -> vkSetDeviceDispatch: write to 0x0
#
# Both listed packages die this way before their UI ever appears, so instead of
# patching upstream or rebuilding from source we keep the upstream nixpkgs
# builds and re-wrap just the affected binary to drop the layer env vars. The
# emulators themselves (shadps4, and RPCS3's own perf overlay) do not need
# MangoHud; everything else in the session still gets it.
#
# Adding another victim is one entry in the attribute set at the bottom.
final: prev: let
  # Copy the package out of the store, swap one binary for a wrapper that drops
  # the Vulkan-layer environment, and keep the rest of the tree as-is.
  dropLayerInjection = pkg: binary:
    final.runCommand pkg.pname {
      inherit (pkg) meta pname version;
      nativeBuildInputs = [final.makeWrapper];
    } ''
      cp -a ${pkg}/. $out/
      chmod -R u+w $out
      rm $out/bin/${binary}
      makeWrapper ${pkg}/bin/${binary} $out/bin/${binary} \
        --unset MANGOHUD \
        --unset MANGOHUD_DLSYM \
        --unset OBS_VKCAPTURE \
        --set DISABLE_MANGOHUD 1
    '';
in {
  # Qt launcher for the shadPS4 emulator. Only the launcher needs this; the
  # emulator itself is unaffected and can still be run with MangoHud directly.
  shadps4-qtlauncher = dropLayerInjection prev.shadps4-qtlauncher "shadPS4QtLauncher";

  # PS3 emulator: crashes right after installing the PS3 firmware, while
  # booting the "sys" title (qt_music_handler -> QMediaPlayer).
  rpcs3 = dropLayerInjection prev.rpcs3 "rpcs3";
}
