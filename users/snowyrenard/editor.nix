# Helix editor with LSP servers (nixd, rust-analyzer, clangd, zls, markdown-oxide, harper, typos).
{pkgs, ...}: let
  # The servers he programs with have one home: programming.nix. What is left
  # here is editor-only - spell and typo checkers, and the tree-sitter grammars.
  programming = import ./programming.nix {inherit pkgs;};
in {
  home.sessionVariables.EDITOR = "hx";

  # Neovim, as a second editor. The configuration is plain Lua under ./nvim so
  # the same tree runs on the Ubuntu machines at school, where there is no root
  # and 4 GB of home - see users/snowyrenard/nvim/README.md.
  #
  # `programs.neovim` is deliberately not used: it writes its own init.vim into
  # ~/.config/nvim, which would collide with the tree symlinked below. The store
  # path is read-only, which is why plugins.lua keeps lazy's lockfile in
  # ~/.local/state/nvim instead of beside the config.
  home.packages = [pkgs.neovim];
  xdg.configFile."nvim".source = ./nvim;

  programs.helix = {
    enable = true;
    defaultEditor = true;

    extraPackages =
      programming.servers
      ++ (with pkgs; [
        markdown-oxide
        glsl_analyzer
        zls

        tree-sitter
        tree-sitter-grammars.tree-sitter-rust
        tree-sitter-grammars.tree-sitter-toml
        tree-sitter-grammars.tree-sitter-nix
        tree-sitter-grammars.tree-sitter-nu
        tree-sitter-grammars.tree-sitter-glsl
        tree-sitter-grammars.tree-sitter-c
        tree-sitter-grammars.tree-sitter-cpp
      ]);

    settings = {
      theme = "onedark";

      editor = {
        bufferline = "multiple";
        color-modes = true;
        cursorline = true;
        completion-replace = true;
        lsp.display-inlay-hints = true;
        line-number = "relative";

        cursor-shape = {
          insert = "bar";
          normal = "block";
          select = "underline";
        };
        indent-guides = {
          render = true;
          skip-levels = 1;
        };
        soft-wrap = {
          enable = true;
        };
      };

      keys.normal = {
        "A-," = "goto_previous_buffer";
        "A-." = "goto_next_buffer";
        "A-w" = ":buffer-close";
      };
    };
    languages = {
      language-server.harper = with pkgs; {
        command = "${harper}/bin/harper-ls";
        args = ["--stdio"];
      };
      language-server.typos = with pkgs; {
        command = "${typos-lsp}/bin/typos-lsp";
      };

      language = [
        {
          name = "c";
          indent = {
            unit = "\t";
            tab-width = 4;
          };
        }
        {
          name = "cpp";
          indent = {
            unit = "\t";
            tab-width = 4;
          };
        }
        {
          name = "rust";
          language-servers = ["harper" "typos" "rust-analyzer"];
        }
        {
          name = "markdown";
          language-servers = ["harper" "markdown-oxide"];
        }
        {
          name = "nix";
          language-servers = ["harper" "typos" "nixd"];
        }
      ];
    };
  };
}
