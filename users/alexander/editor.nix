# KWrite (KDE) as default editor with Kate package.
{pkgs, ...}: {
  home.sessionVariables.EDITOR = "kwrite";

  home.packages = with pkgs; [
    kdePackages.kate
  ];
}
