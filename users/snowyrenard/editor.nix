# Helix editor with LSP servers (nixd, rust-analyzer, clangd, zls, markdown-oxide, harper, typos).
{pkgs, ...}: {
  home.sessionVariables.EDITOR = "hx";

  programs.helix = {
    enable = true;
    defaultEditor = true;

    extraPackages = with pkgs; [
      nixd
      markdown-oxide
      glsl_analyzer
      zls
      clang-tools

      tree-sitter
      tree-sitter-grammars.tree-sitter-rust
      tree-sitter-grammars.tree-sitter-toml
      tree-sitter-grammars.tree-sitter-nix
      tree-sitter-grammars.tree-sitter-nu
      tree-sitter-grammars.tree-sitter-glsl
      tree-sitter-grammars.tree-sitter-c
      tree-sitter-grammars.tree-sitter-cpp
    ];

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
