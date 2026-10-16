# Japanese input for every user: fcitx5 with Mozc, on Wayland.
#
# Shared because both users type Japanese and the block was byte-identical in
# both users/ modules. A user who ever wants a different input method overrides
# this beside their own settings rather than the two copies drifting apart.
{pkgs, ...}: {
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true;
      addons = with pkgs; [
        fcitx5-mozc
        fcitx5-gtk
      ];
    };
  };
}
