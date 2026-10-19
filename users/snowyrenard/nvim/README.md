# snowyrenard's Neovim

One config, two machines: this flake's NixOS hosts, and the Ubuntu machines at
school where there is no sudo and 4 GB of home. It is built on [LazyVim][], so
what you get is LazyVim's editor with onedark colours and its installers replaced
by the machine's own packages.

[LazyVim]: https://lazyvim.github.io

## On a school machine

```bash
git clone --depth=1 --filter=blob:none --sparse https://codeberg.org/SnowyRenard/nixos-config.git ~/nvim
cd ~/nvim && git sparse-checkout set users/snowyrenard/nvim
users/snowyrenard/nvim/scripts/bootstrap.sh
nvim
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
| LazyVim and its plugins (29 repositories) | `~/.local/share/nvim` | 124 MB |

That is ~295 MB, and the script refuses to run with less than 600 MB free. The
first start clones the plugins; every start after that is offline.

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
- **No Mason.** On NixOS the binaries Mason downloads do not run (they point at
  a loader NixOS does not have), and on Ubuntu a single `clangd` is all the C
  workflow needs - the bootstrap already puts it in `~/.local/bin`. So
  `lua/plugins/lsp.lua` declares the servers and enables only those `PATH`
  resolves; a missing one is skipped, never an error.
- **No downloads for tree-sitter.** Neovim 0.12 bundles parsers for C, Lua,
  Markdown, Vim, Vimdoc and query, and LazyVim starts them through `pcall`.
  LazyVim's own list of 20 languages is cleared, which also stops it reaching
  for the `tree-sitter` CLI (and then Mason) on every start.
- **No undo or swap files.** LazyVim enables undo files; one per edited file
  quietly eats a small home, so `lua/config/options.lua` turns them off and caps
  the history file.
- **The lockfile lives in `~/.local/state/nvim`.** On NixOS this directory
  arrives as a read-only store symlink, and on Ubuntu it is the git checkout
  that has to stay clean after editing.

## Keys

LazyVim's own set, with one addition at the end: `<leader><space>` files,
`<leader>/` grep, `<leader>ca` code action, `gd` definition, `K` hover,
`]d`/`[d` diagnostics, `<leader>l` opens the Lazy UI, `<leader>n` norminette.
