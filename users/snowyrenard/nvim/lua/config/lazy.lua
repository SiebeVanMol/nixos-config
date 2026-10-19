-- LazyVim's bootstrap and this config's own lazy options.
--
-- The only things changed from LazyVim's starter: the lockfile lives in state
-- rather than beside this file (on NixOS the config arrives as a read-only
-- store symlink, and on Ubuntu this directory is the git checkout that has to
-- stay clean), and the update checker is off, because a config that fetches
-- without being asked is wrong on a machine with 4 GB of home.
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local out = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({{"lazy.nvim could not be cloned: " .. out, "ErrorMsg"}}, true, {})
    return
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    {"LazyVim/LazyVim", import = "lazyvim.plugins"},
    {import = "plugins"},
  },
  defaults = {lazy = false, version = false},
  install = {colorscheme = {"onedark", "habamax"}},
  checker = {enabled = false},
  change_detection = {notify = false},
  lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json",
})
