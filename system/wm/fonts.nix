# System fonts: Noto (CJK, emoji), Fira Code, Fira Code Nerd Font with subpixel rendering.
{ pkgs, ... }:

{
  fonts = {
    packages = with pkgs; [
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji

        fira-code
        nerd-fonts.fira-code
    ];

    fontconfig.subpixel.rgba = "vbgr";
  };
}
