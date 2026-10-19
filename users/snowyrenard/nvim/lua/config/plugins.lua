-- Plugins: lazy.nvim, fetched into ~/.local/share/nvim on first start.
--
-- lazy.nvim rather than Neovim 0.12's built-in `vim.pack` because of the
-- lockfile and the :Lazy surface - one file records what both machines run,
-- which is the whole point of one config for two operating systems.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if vim.uv.fs_stat(lazypath) == nil then
  local result = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.notify("lazy.nvim could not be cloned: " .. result, vim.log.levels.ERROR)
  end
end

vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- The colourscheme Helix already uses here, so the two editors look alike.
    {
      "navarasu/onedark.nvim",
      lazy = false,
      priority = 1000,
      config = function()
        vim.cmd.colorscheme("onedark")
      end,
    },
  },

  -- The lockfile is kept outside this directory on purpose: on NixOS the config
  -- arrives as a read-only store symlink, and on the Ubuntu machine it is the
  -- git checkout, which must stay clean after editing.
  lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json",

  install = {missing = true},
  checker = {enabled = false},
  change_detection = {notify = false},
})
