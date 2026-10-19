-- Language servers, supplied by whichever machine is running this.
--
-- The Lua never names a path and never installs anything: it asks PATH. That is
-- what makes one config work on both sides.
--
--   NixOS  - programming.nix puts nixd, clangd (clang-tools) and csharp-ls on
--            PATH as home packages, and rustup provides rust-analyzer as a
--            shim. Nothing is downloaded here at all.
--   Ubuntu - scripts/bootstrap.sh drops a clangd binary in ~/.local/bin. That
--            is the only server worth its bytes on a 4 GB home; pyright would
--            drag in Node and csharp_ls the whole .NET SDK, so they are simply
--            absent there, and a server that is not executable is skipped
--            rather than reported as an error.
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

local enable = {}

for name, config in pairs(servers) do
  vim.lsp.config(name, config)
  if vim.fn.executable(config.cmd[1]) == 1 then
    table.insert(enable, name)
  end
end

table.sort(enable)
vim.lsp.enable(enable)
