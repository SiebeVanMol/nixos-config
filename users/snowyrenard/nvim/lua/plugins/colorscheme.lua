-- onedark, the colourscheme Helix already uses on these machines.
--
-- LazyVim ships tokyonight and loads it during startup, so the default has to be
-- switched off or it wins the race; catppuccin goes too, because LazyVim treats
-- it as an alternative default and it would otherwise be installed (and its
-- ~10 MB carried) for nothing.
return {
  {
    "navarasu/onedark.nvim",
    lazy = false,
    priority = 1000,
    opts = {style = "dark"},
    config = function(_, opts)
      require("onedark").setup(opts)
      vim.cmd.colorscheme("onedark")
    end,
  },
  {"folke/tokyonight.nvim", enabled = false},
  {"catppuccin/nvim", enabled = false},

  {"LazyVim/LazyVim", opts = {colorscheme = "onedark"}},
}
