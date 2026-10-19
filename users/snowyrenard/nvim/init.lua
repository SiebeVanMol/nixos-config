-- One Neovim config, two machines.
--
-- It runs under Home Manager on NixOS and straight from a checkout on the
-- Ubuntu machines at school, where there is no sudo and 4 GB of home. That
-- shapes everything below: no plugin that needs a compiler, no downloaded
-- tree-sitter parsers (Neovim 0.12 already ships the C one), no undo or swap
-- files, and exactly one place that knows which OS this is - config/lsp.lua,
-- where the flag decides what gets downloaded, never how the editor behaves.
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
