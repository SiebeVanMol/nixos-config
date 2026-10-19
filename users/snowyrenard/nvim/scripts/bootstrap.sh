#!/usr/bin/env bash
# Install this config on a machine with no sudo and 4 GB of home.
#
# Why bash and not nushell, against this repository's rule: the script's whole
# job is to put the first tools on a machine that has almost none of them.
# Nushell is one of the things it would have to install first, so bash is the
# only shell that is guaranteed to be there.
#
# Neovim itself is deliberately not installed here. The editor belongs to the
# machine - the same rule that makes Home Manager install pkgs.neovim on NixOS -
# so this script only checks the one it finds and refuses to continue if it is
# too old. Everything else is deliberately the smallest thing that runs: static
# ripgrep and fd, and clangd trimmed down to the binary and the builtin headers
# it reads, dropping the 70 MB of sanitizer runtime that a language server never
# loads.
set -euo pipefail

CLANGD_VERSION=23.1.0
CLANGD_MAJOR=23
RG_VERSION=14.1.1
FD_VERSION=10.2.0

case $(uname -m) in
  x86_64) ARCH=x86_64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  *)
    echo "unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

OPT=$HOME/.local/opt
BIN=$HOME/.local/bin
SRC=$HOME/.local/src

fetch() { # url destination
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 2 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$2" "$1"
  else
    echo "need curl or wget to download $1" >&2
    exit 1
  fi
}

# Is the Neovim the machine already has new enough?
#
# The config needs 0.11 (vim.lsp.config, vim.diagnostic.jump, vim.uv), and the
# version shipped by the distribution is frequently older: Ubuntu 24.04 has
# 0.9.5. So the tarball below is only for a machine with no Neovim or with one
# too old - a machine that already has 0.11 or later keeps its own.
nvim_is_new_enough() {
  local exe raw version major minor
  exe=$(command -v nvim 2>/dev/null) || return 1
  raw=$("$exe" --version 2>/dev/null) || return 1
  # Parsed with shell expansion alone: this runs before anything is installed,
  # so it may not assume awk or head exist on the machine.
  version=${raw#NVIM v}
  version=${version%%$'\n'*}
  major=${version%%.*}
  minor=${version#*.}
  minor=${minor%%.*}
  case $major in '' | *[!0-9]*) return 1 ;; esac
  case $minor in '' | *[!0-9]*) return 1 ;; esac
  [ "$major" -gt 0 ] || [ "$minor" -ge 11 ]
}

# The whole install is about 175-215 MB; refuse to start below 600 MB free so a
# half-finished download can never be what fills the disk.
free_mb=$(df -Pk "$HOME" | awk 'NR == 2 {print int($4 / 1024)}')
if [ "$free_mb" -lt 600 ]; then
  echo "need 600 MB free in $HOME, found ${free_mb} MB" >&2
  exit 1
fi

# Neovim is the machine's responsibility, so the only thing done about it here
# is a version check: 0.11 is the floor (vim.lsp.config, vim.diagnostic.jump,
# vim.uv), and stopping with one sentence beats downloading a second editor that
# shadows the system one, drifts from it, and costs 40 MB of a 4 GB home.
if ! nvim_is_new_enough; then
  echo "neovim 0.11 or newer is required, and none was found on PATH." >&2
  echo "the config serves a 0.11+ editor; this script never installs one." >&2
  exit 1
fi

mkdir -p "$OPT" "$BIN" "$SRC"

# Static search tools: ripgrep for :grep and <leader>fg, fd for the file picker.
if [ ! -x "$BIN/rg" ]; then
  echo "==> ripgrep $RG_VERSION"
  tarball=$SRC/rg.tar.gz
  fetch "https://github.com/BurntSushi/ripgrep/releases/download/$RG_VERSION/ripgrep-$RG_VERSION-$ARCH-unknown-linux-musl.tar.gz" "$tarball"
  rm -rf "$SRC/rg"
  mkdir -p "$SRC/rg"
  tar -xzf "$tarball" -C "$SRC/rg" --strip-components=1
  cp "$SRC/rg/rg" "$BIN/rg"
  rm -rf "$SRC/rg" "$tarball"
fi

if [ ! -x "$BIN/fd" ]; then
  echo "==> fd $FD_VERSION"
  tarball=$SRC/fd.tar.gz
  fetch "https://github.com/sharkdp/fd/releases/download/v$FD_VERSION/fd-v$FD_VERSION-$ARCH-unknown-linux-musl.tar.gz" "$tarball"
  rm -rf "$SRC/fd"
  mkdir -p "$SRC/fd"
  tar -xzf "$tarball" -C "$SRC/fd" --strip-components=1
  cp "$SRC/fd/fd" "$BIN/fd"
  rm -rf "$SRC/fd" "$tarball"
fi

# clangd: the only language server worth its bytes on a 4 GB home. It is the
# 42 C workflow, and the alternative - pyright, csharp-ls - pulls in Node or the
# .NET SDK, which is another gigabyte.
if [ ! -x "$BIN/clangd" ]; then
  echo "==> clangd $CLANGD_VERSION"
  archive=$SRC/clangd.zip
  fetch "https://github.com/clangd/clangd/releases/download/$CLANGD_VERSION/clangd-linux-$CLANGD_VERSION.zip" "$archive"
  rm -rf "$SRC/clangd" "$OPT/clangd"
  mkdir -p "$SRC/clangd"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$archive" -d "$SRC/clangd"
  else
    python3 -m zipfile -e "$archive" "$SRC/clangd"
  fi
  unpacked=$SRC/clangd/clangd_$CLANGD_VERSION
  mkdir -p "$OPT/clangd/bin" "$OPT/clangd/lib/clang/$CLANGD_MAJOR"
  cp "$unpacked/bin/clangd" "$OPT/clangd/bin/clangd"
  cp -r "$unpacked/lib/clang/$CLANGD_MAJOR/include" "$OPT/clangd/lib/clang/$CLANGD_MAJOR/include"
  rm -rf "$SRC/clangd" "$archive"
fi
ln -sfn "$OPT/clangd/bin/clangd" "$BIN/clangd"

# Point ~/.config/nvim at this checkout, so editing the config is editing the
# repository and `git status` shows it. A real directory there is left alone:
# it may be a config from before this script, and silently replacing it would
# throw away work.
CONFIG=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$HOME/.config"
if [ -e "$HOME/.config/nvim" ] && [ ! -L "$HOME/.config/nvim" ]; then
  echo "$HOME/.config/nvim exists and is not a symlink; move it aside and re-run" >&2
  exit 1
fi
ln -sfn "$CONFIG" "$HOME/.config/nvim"

case $PATH in
  *"$BIN"*) ;;
  *) echo "note: $BIN is not on PATH; Ubuntu's ~/.profile adds it on next login" ;;
esac

echo
echo "==> what this used"
du -sh "$OPT" "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" 2>/dev/null || true
df -h "$HOME" | tail -1
echo
echo "first start downloads the plugins: nvim"
