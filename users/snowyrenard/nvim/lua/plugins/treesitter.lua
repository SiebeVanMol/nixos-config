-- Tree-sitter: the parsers Neovim already ships, and nothing else.
--
-- LazyVim ensures a list of ~20 language parsers and, when one is missing,
-- reaches for the `tree-sitter` CLI - and, failing that, for Mason. With Mason
-- disabled that turns into a warning on every start, and with it enabled it
-- would want a compiler and extra megabytes. Neither is worth it here: the
-- school work is C, and Neovim 0.12 bundles c, lua, markdown, vim, vimdoc and
-- query parsers, which LazyVim's own FileType hook starts through pcall.
--
-- Assigning rather than merging because LazyVim declares `ensure_installed` in
-- `opts_extend`, so a plain opts table would be appended to its list instead of
-- replacing it.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = {}
    end,
  },
}
