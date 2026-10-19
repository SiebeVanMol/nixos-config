-- One Neovim config, two machines.
--
-- It runs under Home Manager on NixOS and straight from a checkout on the
-- Ubuntu machines at school, where there is no sudo and 4 GB of home. That
-- shapes everything below: no plugin that needs a compiler, no downloaded
-- tree-sitter parsers (Neovim 0.12 already ships the C one), no undo or swap
-- files, and exactly one place that knows which OS this is - config/lsp.lua,
-- where the flag decides what gets downloaded, never how the editor behaves.

-- 0.11 is the floor: vim.lsp.config, vim.diagnostic.jump and vim.uv do not
-- exist before it. A machine's own Neovim is whatever the distribution shipped
-- (Ubuntu 24.04 has 0.9.5), so this runs before anything else and says so
-- plainly - otherwise the first filetype callback raises a stack trace that
-- names a function the user never called.
if vim.fn.has("nvim-0.11") ~= 1 then
  vim.api.nvim_echo({
    {
      ("this config needs Neovim 0.11 or newer, found %d.%d"):format(vim.version().major, vim.version().minor),
      "ErrorMsg",
    },
    {"run users/snowyrenard/nvim/scripts/bootstrap.sh, which installs one into ~/.local", "WarningMsg"},
  }, true, {})
  return
end

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

require("config.options")
require("config.keymaps")
require("config.plugins")
require("config.lsp")

-- Highlighting from the parsers Neovim ships (c, lua, markdown, vim, vimdoc,
-- query), which is why this tree needs no tree-sitter plugin and no network.
-- pcall because a filetype with no bundled parser must fall back to regex
-- syntax instead of raising on every file opened.
vim.api.nvim_create_autocmd("FileType", {
  callback = function(event)
    pcall(vim.treesitter.start, event.buf)
  end,
})
