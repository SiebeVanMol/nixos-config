# overlays/shadps4.nix
#
# shadps4-qtlauncher: the Qt launcher for the shadPS4 emulator.
#
# shadps4 itself works fine, but the official nixpkgs qtlauncher coredumps as
# soon as it starts, right when QtMultimedia initializes its ffmpeg backend:
# QMediaPlayer -> QFFmpegMediaIntegration -> Vulkan HW-decode device probe
# (av_hwdevice_ctx_create -> vkCreateDevice). If MangoHud's Vulkan layer is
# injected into the process (session-wide `mangohud.enableSessionWide`, which
# sets MANGOHUD=1), that probe segfaults inside libMangoHud's
# overlay_CreateDevice. This happens before the UI ever appears.
#
# Rather than patch upstream or rebuild from source, we keep the official
# nixpkgs shadps4-qtlauncher and just wrap its binary to drop the Vulkan
# overlay env vars (MANGOHUD / MANGOHUD_DLSYM / OBS_VKCAPTURE) that cause the
# crash. The launcher itself is a plain management UI and does not need those
# overlays; the emulator (shadps4) can still be run with MangoHud directly.
final: prev: let
  launcher = prev.shadps4-qtlauncher;
in {
  shadps4-qtlauncher =
    final.runCommand "shadps4-qtlauncher" {
      inherit (launcher) meta pname version;
      nativeBuildInputs = [final.makeWrapper];
    } ''
      # Copy the whole store package (bin, share, ...) then re-wrap only the
      # launcher binary to unset the crashing Vulkan-layer env vars.
      cp -a ${launcher}/. $out/
      chmod -R u+w $out
      rm $out/bin/shadPS4QtLauncher
      makeWrapper ${launcher}/bin/shadPS4QtLauncher $out/bin/shadPS4QtLauncher \
        --unset MANGOHUD \
        --unset MANGOHUD_DLSYM \
        --unset OBS_VKCAPTURE
    '';
}
