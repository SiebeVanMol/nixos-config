# Neovim: the portable config from the nvim-config submodule, wired in through
# its Home Manager module. This only adds Neovim alongside Helix - ./editor.nix
# still owns the default editor, so $EDITOR and the MIME handlers are unchanged.
{inputs, ...}: {
  imports = [inputs.nvim-config.homeManagerModules.default];

  programs.nvim-config.enable = true;
}
