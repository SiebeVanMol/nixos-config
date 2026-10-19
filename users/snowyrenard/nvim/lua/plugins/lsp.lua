-- Language servers, supplied by whichever machine is running this.
--
-- LazyVim installs servers through Mason by default. That is disabled here for
-- two reasons: on NixOS the binaries Mason downloads are linked against a loader
-- that does not exist there ("No such file or directory" on a server that is
-- clearly installed), and on the Ubuntu machines the only server worth its space
-- is clangd, which scripts/bootstrap.sh already provides without root.
--
-- So the Lua never names a path and never installs anything: it asks PATH and
-- skips what is missing.
--
--   NixOS  - programming.nix puts nixd, clangd (clang-tools) and csharp-ls on
--            PATH, and rustup provides rust-analyzer as a shim.
--   Ubuntu - ~/.local/bin has clangd from the bootstrap. pyright would drag in
--            Node and csharp_ls the whole .NET SDK, so they are simply absent,
--            and a server that is not executable is skipped rather than an error.
local servers = {
  clangd = {
    cmd = {"clangd", "--background-index", "--clang-tidy"},
    filetypes = {"c", "cpp"},
    root_markers = {"compile_commands.json", ".clangd", "Makefile", ".git"},
  },
  nixd = {
    cmd = {"nixd"},
    filetypes = {"nix"},
    root_markers = {"flake.nix", "default.nix", ".git"},
  },
  rust_analyzer = {
    cmd = {"rust-analyzer"},
    filetypes = {"rust"},
    root_markers = {"Cargo.toml", "rust-toolchain.toml", ".git"},
  },
  csharp_ls = {
    cmd = {"csharp-ls"},
    filetypes = {"cs"},
    root_markers = {".git"},
  },
  lua_ls = {
    cmd = {"lua-language-server"},
    filetypes = {"lua"},
    root_markers = {".luarc.json", ".stylua.toml", ".git"},
    settings = {
      Lua = {
        diagnostics = {globals = {"vim"}},
        workspace = {checkThirdParty = false},
        telemetry = {enable = false},
      },
    },
  },
  bashls = {
    cmd = {"bash-language-server", "start"},
    filetypes = {"bash", "sh"},
    root_markers = {".git"},
  },
}

return {
  -- Mason and its lspconfig bridge are LazyVim's installers; disabled, the
  -- servers above come from PATH instead, which is the only thing that works on
  -- both machines with one config.
  {"mason-org/mason.nvim", enabled = false},
  {"mason-org/mason-lspconfig.nvim", enabled = false},
  {"WhoIsSethDaniel/mason-tool-installer.nvim", enabled = false},

  {
    "neovim/nvim-lspconfig",
    config = function()
      local enable = {}
      for name, config in pairs(servers) do
        vim.lsp.config(name, config)
        if vim.fn.executable(config.cmd[1]) == 1 then
          table.insert(enable, name)
        end
      end
      table.sort(enable)
      vim.lsp.enable(enable)
    end,
  },
}
