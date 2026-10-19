-- One Neovim config, two machines, built on LazyVim.
--
-- It runs under Home Manager on NixOS and straight from a checkout on the
-- Ubuntu machines at school, where there is no sudo and 4 GB of home. LazyVim
-- supplies the editor's behaviour; lua/plugins holds the few places this
-- machine set differs from it (onedark, no Mason, servers resolved from PATH).
--
-- 0.11 is the floor: vim.lsp.config, vim.diagnostic.jump and vim.uv do not
-- exist before it, and LazyVim needs 0.11 as well. A machine's own Neovim is
-- whatever the distribution shipped (Ubuntu 24.04 has 0.9.5), so this runs
-- before anything else and says so plainly - otherwise the first filetype
-- callback raises a stack trace naming a function the user never called.
if vim.fn.has("nvim-0.11") ~= 1 then
  vim.api.nvim_echo({
    {
      ("this config needs Neovim 0.11 or newer, found %d.%d"):format(vim.version().major, vim.version().minor),
      "ErrorMsg",
    },
    {"this machine's Neovim has to be 0.11 or newer: vim.lsp.config, vim.diagnostic.jump and vim.uv arrive there", "WarningMsg"},
  }, true, {})
  return
end

require("config.lazy")
