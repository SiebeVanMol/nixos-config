# Helix editor with LSP servers (nixd, rust-analyzer, clangd, zls, markdown-oxide, harper, typos).
{
  pkgs,
  lib,
  ...
}: let
  # The servers he programs with have one home: programming.nix. What is left
  # here is editor-only - spell and typo checkers, and the tree-sitter grammars.
  programming = import ./programming.nix {inherit pkgs;};

  # Harper (the grammar and spell checker) attached to every language it can
  # parse: prose, and the comments of most programming languages. The keys are
  # Helix language names, the values are the servers Helix itself would start for
  # that language, copied from Helix 25.07.1's languages.toml.
  #
  # The copying is the price of the feature, not laziness: a `[[language]]` entry
  # *replaces* a language's `language-servers` and Helix has no way to append one,
  # so every default server has to be restated beside harper. Harper's own Helix
  # page says as much. A default that upstream adds or renames must be changed
  # here too, or that language silently loses it; `hx --health <language>` prints
  # what the editor actually ends up running.
  #
  # Only languages Harper can parse are listed - attaching it to any other would
  # start a process that never reports anything.
  harperLanguages = {
    c = ["clangd"];
    clojure = ["clojure-lsp"];
    cmake = ["neocmakelsp" "cmake-language-server"];
    cpp = ["clangd"];
    dart = ["dart"];
    elixir = ["elixir-ls"];
    git-commit = [];
    gleam = ["gleam"];
    go = ["gopls" "golangci-lint-lsp"];
    groovy = [];
    haskell = ["haskell-language-server"];
    html = ["vscode-html-language-server" "superhtml"];
    ink = [];
    java = ["jdtls"];
    javascript = ["typescript-language-server"];
    jjdescription = [];
    jsx = ["typescript-language-server"];
    kotlin = ["kotlin-language-server"];
    latex = ["texlab"];
    lua = ["lua-language-server"];
    mail = [];
    markdown = ["marksman" "markdown-oxide"];
    nix = ["nil" "nixd"];
    org = [];
    php = ["intelephense"];
    powershell = [];
    python = ["ty" "ruff" "jedi" "pylsp"];
    ruby = ["ruby-lsp" "solargraph"];
    rust = ["rust-analyzer"];
    scala = ["metals"];
    solidity = ["solc"];
    swift = ["sourcekit-lsp"];
    toml = ["taplo" "tombi"];
    tsx = ["typescript-language-server"];
    typescript = ["typescript-language-server"];
    typst = ["tinymist"];
    zig = ["zls"];

    # The shell is the one language Harper knows under another id: Helix sends
    # "bash", Harper expects "shellscript". The override is in `languageEntry`.
    bash = ["bash-language-server"];
  };

  # One `[[language]]` entry per name above. harper comes first because
  # diagnostics are merged across servers while every other feature falls through
  # to the next server that supports it, so its position costs the neighbours
  # nothing.
  languageEntry = name: let
    tabbed = name == "c" || name == "cpp";
  in
    {
      inherit name;
      language-servers =
        ["harper"]
        ++ harperLanguages.${name}
        ++ lib.optional (name == "nix" || name == "rust") "typos";
    }
    // lib.optionalAttrs tabbed {
      indent = {
        unit = "\t";
        tab-width = 4;
      };
    }
    // lib.optionalAttrs (name == "bash") {
      language-id = "shellscript";
    };
in {
  home.sessionVariables.EDITOR = "hx";

  # Neovim, as a second editor. The configuration is plain Lua under ./nvim so
  # the same tree runs on the Ubuntu machines at school, where there is no root
  # and 4 GB of home - see users/snowyrenard/nvim/README.md. There the editor
  # comes from the machine's own packages, exactly as it does from this line on
  # NixOS; only the tools around it are fetched into ~/.local.
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

      language = map languageEntry (builtins.attrNames harperLanguages);
    };
  };
}
