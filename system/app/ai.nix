# KoboldCpp (OpenAI-compatible server + web UI) served through Caddy on the
# `ai` subdomain, with a model store under /models.
#
# KoboldCpp runs in router mode against /Vault/llama/models: the LM Studio-like
# web UI hotswaps models, and its built-in "Download Models" tab saves into the
# same directory. The backend is Vulkan (RADV) on the AMD box. Models can also
# be managed with the interactive `llama-model` helper, which wraps the
# official `hf` CLI:
#
#   llama-model                interactive menu (search HF, add, remove, ...)
#   llama-model search QUERY   search Hugging Face, then pick a model + file
#   llama-model add REPO[:REV][:FILE]
#   llama-model list / rm FILE / status
#   llama-model login          `hf auth login` (tokens for gated/private repos)
#   llama-model hf <args...>   pass anything through to the hf CLI
#
# Downloads land group-writable in modelsDir; the services run as the desktop
# user so the user's HF token is available and /Vault stays out of reach of
# anything untrusted.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  modelsDir = "/Vault/llama/models";

  # nixpkgs installs the embedded UI assets (klite.embd, ...) flat in bin/,
  # but koboldcpp looks for them in bin/embd_res/. Symlink them so the web
  # UI is served instead of the "connect via the main client" fallback page.
  koboldCppPkg = pkgs.koboldcpp.overrideAttrs (final: prev: {
    postInstall = (prev.postInstall or "") + ''
      mkdir -p "$out/bin/embd_res"
      ln -s "$out"/bin/*.embd "$out/bin/embd_res/"
    '';
  });

  # Web store: search Hugging Face, pick a quant, and manage installed models
  # from the browser. Served at http://ai.lan/models. Uses huggingface_hub
  # directly (same token as `llama-model login`), downloads into modelsDir.
  storePython = pkgs.python3.withPackages (ps: [ ps.huggingface-hub ps.requests ]);
  llamaStore = pkgs.writeScriptBin "llama-store" ''
    #!${storePython}/bin/python
    ${builtins.readFile ./llama-store.py}
  '';

  # Interactive model manager. All Hugging Face interactions (search, file
  # listing, download, auth) are delegated to the official `hf` CLI; this
  # wrapper only adds the menus and the local model directory bookkeeping.
  hfCli = lib.getExe' pkgs.python3Packages.huggingface-hub "hf";
  fzfBin = lib.getExe pkgs.fzf;
  llamaModelScript = pkgs.writeScriptBin "llama-model" ''
    #!${lib.getExe pkgs.bash}
    set -euo pipefail

    models_dir="''${LLAMA_MODEL_DIR:-${modelsDir}}"
    hf="${hfCli}"
    fzf="${fzfBin}"
    python="${lib.getExe pkgs.python3}"
    curl="${lib.getExe pkgs.curl}"

    usage() {
      echo "Usage: llama-model [command]" >&2
      echo "  (no command)          interactive TUI (fzf)" >&2
      echo "  search [QUERY]        fuzzy-search Hugging Face, pick a model + file, download" >&2
      echo "  add REPO[:REV][:FILE] download a GGUF; without FILE the repo's files are picked" >&2
      echo "  list                  show installed models" >&2
      echo "  rm [FILE]             delete a downloaded model" >&2
      echo "  status                show the server and loaded models" >&2
      echo "  login | logout        manage your Hugging Face token (hf auth login/logout)" >&2
      echo "  whoami                who is logged in" >&2
      echo "  hf <args...>          pass through to the hf CLI" >&2
    }

    # Fuzzy picker over stdin lines; prints the chosen line. Requires a TTY.
    pick_fzf() { # $1=prompt
      # stdin is usually a pipe here, so test the TTY device, not fd 0.
      if ! { exec 3<> /dev/tty; } 2>/dev/null; then
        echo "No terminal available; pass the file explicitly (REPO:FILE) or run interactively." >&2
        return 1
      fi
      exec 3>&-
      "$fzf" --prompt="$1> " --height 60% --layout=reverse --border --select-1 \
        || { echo "No selection." >&2; return 1; }
    }

    hf_gguf_files() { # $1=repo → "path<TAB>human-size" lines, main revision
      "$hf" models ls "$1" -R --format json 2>/dev/null \
        | "$python" -c '
import json, sys
for f in json.load(sys.stdin):
    p = f.get("path", "")
    if p.endswith(".gguf"):
        n = f.get("size") or 0
        for u in ["B", "KiB", "MiB", "GiB", "TiB"]:
            if n < 1024:
                print(p + "\t" + ("%.1f %s" % (n, u)))
                break
            n /= 1024'
    }

    cmd_search() {
      local q="''${1:-}"
      [[ -n "$q" ]] || { read -rp "Search Hugging Face for: " q || return; }
      [[ -n "$q" ]] || return
      local -a models=()
      mapfile -t models < <(
        "$hf" models ls --search "$q" --sort downloads --limit 40 --format json 2>/dev/null \
          | "$python" -c 'import json, sys
for m in json.load(sys.stdin):
    print(m["id"] + "\t" + str(m.get("downloads", 0)) + " downloads")'
      )
      (( ''${#models[@]} > 0 )) || { echo "No models found for '$q'."; return; }
      local picked repo
      picked=$(printf '%s\n' "''${models[@]}" | pick_fzf "Pick a model") || return
      repo=''${picked%%$'\t'*}
      cmd_add "$repo"
    }

    cmd_add() {
      local spec="''${1:-}" repo rev file
      [[ -n "$spec" ]] || { read -rp "Hugging Face repo (REPO[:REV][:FILE]): " spec || return; }
      if [[ "$spec" == *@*:* ]]; then
        rev=''${spec%%:*}; rev=''${rev##*@}
        repo=''${spec%%:*}; repo=''${repo%@*}
        file=''${spec##*:}
      elif [[ "$spec" == *:* ]]; then
        repo=''${spec%%:*}; file=''${spec##*:}; rev="main"
      elif [[ "$spec" == *@* ]]; then
        repo=''${spec%@*}; rev=''${spec##*@}; file=""
      else
        repo="$spec"; rev="main"; file=""
      fi

      if [[ -z "$file" ]]; then
        local -a files=()
        mapfile -t files < <(hf_gguf_files "$repo")
        (( ''${#files[@]} > 0 )) || { echo "No .gguf files found in $repo."; return; }
        local picked
        picked=$(printf '%s\n' "''${files[@]}" | pick_fzf "Pick a file from $repo") || return
        file=''${picked%%$'\t'*}
      fi

      if [[ "$file" =~ ^(.*)-[0-9]+-of-[0-9]+\.gguf$ ]]; then
        local base="''${BASH_REMATCH[1]}"
        echo "Multi-part model: downloading all shards of $base."
        "$hf" download "$repo" --revision "$rev" --include "''${base}-*.gguf" --local-dir "$models_dir"
      else
        "$hf" download "$repo" "$file" --revision "$rev" --local-dir "$models_dir"
      fi
      echo "Saved under $models_dir — served by request under the model name."
    }

    cmd_list() {
      if [[ ! -d "$models_dir" ]]; then
        echo "No models yet ($models_dir does not exist)."
        return
      fi
      echo "Installed models in $models_dir:"
      find "$models_dir" -type f -name '*.gguf' -printf '%f\t%k KiB\n' | sort
    }

    cmd_rm() {
      local file="''${1:-}"
      if [[ -z "$file" ]]; then
        local -a files=()
        if [[ -d "$models_dir" ]]; then
          while IFS= read -r f; do files+=("$f"); done < <(
            find "$models_dir" -type f -name '*.gguf' -printf '%f\t%k KiB\n' | sort
          )
        fi
        local picked
        picked=$(printf '%s\n' "''${files[@]}" | pick_fzf "Pick a model to remove") || { echo "Nothing to remove."; return; }
        file=''${picked%%$'\t'*}
      fi
      rm -f "$models_dir/$file"
      echo "Removed $models_dir/$file."
    }

    cmd_status() {
      printf 'Service:\n'
      systemctl --no-pager status koboldcpp --output=short || true
      printf '\nLoaded models (GET /v1/models):\n'
      "$curl" --silent --fail http://127.0.0.1:5001/v1/models || echo "server not reachable yet"
      echo
    }

    interactive() {
      while true; do
        echo
        echo "llama-model — manage local GGUF models (via the hf CLI + fzf)"
        echo "  1) Search Hugging Face (fzf)"
        echo "  2) Add a model by repo"
        echo "  3) List installed models"
        echo "  4) Remove a model"
        echo "  5) Server status"
        echo "  6) Hugging Face login"
        echo "  7) Quit"
        local choice
        read -rp "> " choice || { echo; return; }
        case "$choice" in
          1) cmd_search "" ;;
          2) cmd_add "" ;;
          3) cmd_list ;;
          4) cmd_rm "" ;;
          5) cmd_status ;;
          6) "$hf" auth login ;;
          7 | q) return ;;
          *) ;;
        esac
      done
    }

    if (($# == 0)); then
      interactive
      exit 0
    fi
    case "$1" in
      search) cmd_search "''${2:-}" ;;
      add) cmd_add "''${2:-}" ;;
      list) cmd_list ;;
      rm) cmd_rm "''${2:-}" ;;
      status) cmd_status ;;
      login) "$hf" auth login ;;
      logout) "$hf" auth logout ;;
      whoami) "$hf" auth whoami ;;
      hf) shift; exec "$hf" "$@" ;;
      -h | --help | help) usage ;;
      *) usage; exit 1 ;;
    esac
  '';
in
{
  config = lib.mkIf config.device.app.ai.enable {
    # Web store service: runs as the desktop user (group `users`) so downloads
    # land group-writable in modelsDir and the user's HF token is available.
    systemd.services.llama-store = {
      description = "Model store web UI for the KoboldCpp server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      environment.MODELS_DIR = modelsDir;
      environment.LLAMA_SERVER = "http://127.0.0.1:5001";
      serviceConfig = {
        User = username;
        Group = "users";
        ExecStart = "${llamaStore}/bin/llama-store";
        Restart = "on-failure";
        RestartSec = 3;
      };
    };

    # KoboldCpp: an LM Studio-like web UI with model downloads built in
    # ("Download Models" tab) and a router that hotswaps models from the UI
    # without a server restart. Vulkan backend (RADV), same models dir.
    systemd.services.koboldcpp = {
      description = "KoboldCpp AI server (router mode)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = username;
        Group = "users";
        ExecStart = toString [
          "${koboldCppPkg}/bin/koboldcpp"
          "--host"
          "127.0.0.1"
          # In router mode the proxy binds the *positional* port, so the empty
          # model placeholder + port slot below is what actually sets it.
          ""
          "5001"
          "--nomodel"
          "--usevulkan"
          "--gpulayers"
          "99"
          "--contextsize"
          "8192"
          "--routermode"
          "--admin"
          "--admindir"
          modelsDir
          "--downloaddir"
          modelsDir
        ];
        Restart = "on-failure";
        RestartSec = 3;
      };
    };

    systemd.tmpfiles.rules = [
      "d /Vault/llama 0755 root users -"
      "d ${modelsDir} 0775 root users -"
    ];

    # Serve on ai.lan (plain HTTP, LAN-only). Optionally also on the public
    # domain (ai.snowyrenard.com) via the automatic HTTPS challenge.
    # The model store lives under /models on ai.lan; everything else (the
    # KoboldCpp web UI + OpenAI API) goes straight to the backend.
    services.caddy.virtualHosts = lib.mkIf config.device.security.reverse-proxy.enable (
      lib.listToAttrs (
        [{
          name = "http://ai.lan";
          value = {
            extraConfig = ''
              handle_path /models* {
                reverse_proxy 127.0.0.1:8090
              }
              reverse_proxy 127.0.0.1:5001
            '';
          };
        }]
        ++ lib.optionals config.device.app.ai.public [{
          name = "ai.${config.device.security.reverse-proxy.publicDomain}";
          value = {
            extraConfig = ''
              reverse_proxy 127.0.0.1:5001
            '';
          };
        }]
      )
    );

    networking.hosts = lib.mkIf config.device.security.reverse-proxy.enable {
      "127.0.0.1" = [ "ai.lan" ];
    };

    environment.systemPackages = [
      llamaModelScript
    ];
  };
}