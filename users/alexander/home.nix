# Alex's user home: Japanese input (fcitx5 + Mozc).
{ pkgs, ... }: {
  imports = [
    ../../home/core.nix

    ./editor.nix
    ./browser.nix
    ./programs.nix
  ];

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
