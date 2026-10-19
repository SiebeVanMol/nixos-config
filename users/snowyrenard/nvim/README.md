# snowyrenard's Neovim

One config, two machines: this flake's NixOS hosts, and the Ubuntu machines at
school where there is no sudo and 4 GB of home.

## On a school machine

```bash
git clone --depth=1 --filter=blob:none --sparse https://codeberg.org/SnowyRenard/nixos-config.git ~/nvim
cd ~/nvim && git sparse-checkout set users/snowyrenard/nvim
users/snowyrenard/nvim/scripts/bootstrap.sh
```

`--depth=1 --sparse` matters: this repository's *history* is 1.65 GB, while the
config itself is a few kilobytes. The shallow sparse clone is about 1 MB.

The script is idempotent - run it again after a wipe, it only replaces what is
missing. It never installs an editor: Neovim belongs to the machine, so a
missing or too-old one stops it with a single sentence. What it does install,
all inside `~/.local`:

| What | Where | Size |
| --- | --- | --- |
| ripgrep + fd (static) | `~/.local/bin` | 5 MB |
| clangd, binary + builtin headers only | `~/.local/opt/clangd` | 165 MB |
| plugins (lazy.nvim + onedark) | `~/.local/share/nvim` | ~5 MB |

That is ~175 MB, and the script refuses to run with less than 600 MB free.

## On NixOS

`users/snowyrenard/editor.nix` installs `pkgs.neovim` and points
`~/.config/nvim` at this directory. `home-manager switch --flake .#snowyrenard@<host>`
applies it; the language servers come from `programming.nix`, so nothing is
downloaded.

## Why it is shaped like this

- **Neovim 0.11 is the floor.** `vim.lsp.config`, `vim.diagnostic.jump` and
  `vim.uv` arrive in 0.11, and distributions are behind it (Ubuntu 24.04 ships
  0.9.5), so `init.lua` refuses to load on anything older with one readable
  message, and the bootstrap stops on it rather than installing a second editor.
- **No tree-sitter plugin.** Neovim 0.12 ships parsers for C, Lua, Markdown,
  Vim, Vimdoc and query. `init.lua` starts them with `pcall`, so C is
  highlighted on a machine with no compiler and no download.
- **No Mason.** On NixOS its downloaded binaries do not run (they point at a
  loader NixOS does not have), and on Ubuntu a single `clangd` is all the C
  workflow needs. The LSP layer asks `PATH` and skips what is missing, so the
  same Lua runs on both.
- **No undo or swap files.** One undo file per edited file is the thing that
  quietly eats a small home.
- **No fuzzy finder plugin.** `<leader>ff` uses `vim.fs.find` and
  `vim.ui.select`; if telescope is installed later it hooks into the same call.

Keys: `<leader>ff` files, `<leader>fg` grep, `<leader>w` write, `gd` definition,
`K` hover, `<leader>rn` rename, `<leader>ca` code action, `]d`/`[d` diagnostics,
`<leader>n` norminette.
