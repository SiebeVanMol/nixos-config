# Local inference: one llama.cpp server in router mode over the model files on
# /Vault, sized for this machine's own GPU.
#
# Two models for two jobs. `agent` is what an agent loop thinks with: a 35B
# mixture-of-experts whose expert tensors live in RAM, so a token pays only for
# the ~3B parameters it activates. `quick` is a small dense model for a question
# or a page summary.
#
# Router mode is what makes one service out of several models: llama-server
# starts with no model argument, discovers every GGUF in --models-dir, loads one
# when a request names it, and unloads it again when another is wanted. A client
# therefore sees several model ids on one endpoint while the card only ever holds
# the model in use. The id is the file name without .gguf - llama.cpp derives it
# and sets each child's --alias to match - so the file names below are part of the
# interface, not an implementation detail. Every other setting is inherited by
# the children, which is why --cpu-moe is safe to set globally: it matches expert
# tensors, and a dense model has none.
#
# Hermes already speaks this protocol. It probes 127.0.0.1:8080 for /props,
# fingerprints llama-server by its build_info (the router answers it, with no
# model argument), reads the model list from /models, and adopts what it finds.
# The user side of the wiring is users/snowyrenard/hermes.nix.
#
# `enable` is declared in system/options.nix with the other host toggles; the
# knobs below are this service's own.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.device.app.ai;

  modelsDir = "/Vault/llama/models";

  # gfx1201 is the RX 9070/XT (RDNA4). nixpkgs' rocmPackages carries a
  # per-architecture scope (`rocmPackages.gfx1201`) that pins clr and everything
  # built against it to this one GPU, so the HIP build does not compile for the
  # other nineteen targets; rocmGpuTargets follows clr's localGpuTargets from
  # that scope. The host already sets nixpkgs.config.rocmSupport (see
  # system/hardware/mesa.nix), which is why the Vulkan branch has to switch it
  # back off or it would carry a HIP backend nobody asked for.
  #
  # Vulkan rides the Mesa/RADV stack the host already has, so it costs minutes
  # rather than hours to build. It is the default because it is the cheaper one
  # to be wrong about; on this card the two backends measure within a few
  # percent of each other (llama.cpp discussion #15021).
  package =
    if cfg.backend == "vulkan"
    then
      pkgs.llama-cpp.override {
        vulkanSupport = true;
        rocmSupport = false;
      }
    else
      pkgs.llama-cpp.override {
        rocmSupport = true;
        rocmPackages = pkgs.rocmPackages.gfx1201;
        rocmGpuTargets = ["gfx1201"];
      };

  # huggingface-hub's CLI fetches the weights at runtime, so 20+ GiB never
  # becomes a store path: a store copy would be re-downloaded on every pin change
  # and would not be the thing the user is allowed to delete to reclaim space.
  hf = lib.getExe' pkgs.python3Packages.huggingface-hub "hf";

  # One branch per declared model, so the small one is useful before the big one
  # has been paid for. Built as a list of lines rather than an indented string:
  # interpolated text is inserted verbatim, so alignment inside an indented
  # template would depend on which line happened to be first.
  modelNames = lib.concatStringsSep ", " (lib.attrNames cfg.models);

  fetchLine = name: m: "  ${name}) fetch ${name} \"${m.repo}\" \"${m.file}\" \"${m.revision}\" ;;";
  fetchAllLine = name: m: "    fetch ${name} \"${m.repo}\" \"${m.file}\" \"${m.revision}\"";

  llamaFetch = pkgs.writeShellScriptBin "llama-fetch" (lib.concatStringsSep "\n" (
    [
      "set -euo pipefail"
      ""
      "fetch() {"
      "  echo \"==> $1: $3\""
      "  ${hf} download \"$2\" \"$3\" --revision \"$4\" --local-dir ${modelsDir}"
      "}"
      ""
      "case \"\${1:-all}\" in"
    ]
    ++ lib.mapAttrsToList fetchLine cfg.models
    ++ (
      ["  all)"]
      ++ lib.mapAttrsToList fetchAllLine cfg.models
      ++ [
        "    ;;"
        "  *)"
        "    echo \"unknown model: $1 (try ${modelNames}, or all)\" >&2"
        "    exit 2"
        "    ;;"
        "esac"
        ""
        "echo \"in ${modelsDir} - a running server picks the file up on its next start\""
      ]
    )
  ));
in {
  options.device.app.ai = {
    backend = lib.mkOption {
      type = lib.types.enum ["vulkan" "rocm"];
      default = "vulkan";
      description = ''
        GPU backend the server is built against. Both are complete builds of
        llama.cpp, not switches on one binary: "vulkan" rides the host's Mesa
        stack, "rocm" builds against rocmPackages.<gpu target> and is the one to
        try if Vulkan measures badly on this card.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = ''
        Port on loopback. 8080 is llama-server's own default and the single port
        Hermes probes for a server it did not start, so changing it means also
        changing providers.llamacpp.base_url in users/snowyrenard/hermes.nix.
      '';
    };

    contextSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 65536;
      description = ''
        Context window every model is served with. Every model Hermes recommends
        gets at least 64K. The agent model costs very little per token here (a
        hybrid layout with 10 full-attention layers, ~10 KiB of q8 cache per
        token), so raising this is cheap until the KV cache plus the compute
        buffer stop fitting on the card; llama.cpp reduces the window at load
        time if that happens.
      '';
    };

    maxResidentModels = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = ''
        How many models may be loaded at once. 1 keeps the card for whichever
        model is in use, so switching is a load and an unload. 2 is measured to
        fit only barely here: the 12B holds 8.2 GiB above the desktop's own
        ~1.9 GiB and the agent model another 3.5 GiB, i.e. ~13.6 GiB of the
        14.27 GiB free, leaving nothing for a browser. 1 stays the default.
      '';
    };

    expose = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Publish the server as http://ai.lan through the reverse proxy, so the
        other machines can point a client at it. The server itself stays on
        loopback.
      '';
    };

    models = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          repo = lib.mkOption {
            type = lib.types.str;
            description = "Hugging Face repository the weights come from.";
          };
          revision = lib.mkOption {
            type = lib.types.str;
            description = ''
              Commit the download is pinned to, so llama-fetch is reproducible and
              a re-upload upstream cannot swap the weights under a running config.
            '';
          };
          file = lib.mkOption {
            type = lib.types.str;
            description = ''
              The GGUF in that repository. The id clients use is this file name
              without .gguf, so renaming the file renames the model.
            '';
          };
          note = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Why this model, for whoever reads this next.";
          };
        };
      });
      default = {
        agent = {
          repo = "unsloth/Qwen3.6-35B-A3B-MTP-GGUF";
          revision = "5bc3e238d916f48a861bac2f8a1990a0e9b7e98d";
          file = "Qwen3.6-35B-A3B-UD-Q4_K_M.gguf";
          note = ''
            The agent model: 35B total / 3B active, 262144 native context, and
            Hermes' own catalog entry for it ("validated" there). ~22.7 GB on
            disk, of which only the attention half needs to be on the GPU.
          '';
        };

        quick = {
          repo = "unsloth/gemma-4-12B-it-qat-GGUF";
          revision = "980b060c40a8539ac159e0501a3e0f66a6365af3";
          file = "gemma-4-12B-it-qat-UD-Q4_K_XL.gguf";
          note = ''
            The small one: 12B dense, 6.72 GB, multimodal, with four times the
            headroom of the agent model - a 64K window fits comfortably and the
            rest of the card stays with the desktop.

            These are Google's quantization-aware-trained weights (trained at the
            precision they ship at) in Unsloth's dynamic quant. QAT weights need a
            converter that understands their scales: llama.cpp's own Q4_0 format
            uses F16 scales where QAT uses BF16, and converting anyway costs real
            accuracy - 70.2% against 85.6% top-1 for this build of the same
            weights, which is also 200 MB smaller. So a UD-Q4_K_XL of the QAT
            checkpoint, not a Q4_0 of it, including the Q4_0 Google publishes.

            The alternative for this slot is Gemma 4 26B-A4B (MoE, 4B active):
            14.25 GB in the same build, i.e. 13.27 GiB of the card's 14.27 GiB
            free, which leaves ~1 GiB for the KV cache and compute buffers - a
            window near 16K, too small for the agent's own prompt plus a page to
            summarise. It is much faster per token once resident (this card
            measured ~157 t/s on that model, against ~39 t/s for a 12B on a
            smaller one): the MoE trade is that compute drops to 4B active while
            all 26B parameters still have to be in memory to keep routing fast.
          '';
        };
      };
      description = ''
        Models the router serves, keyed by the name llama-fetch takes. The key is
        only a label for fetching; the model id a client uses is the file name.
        Adding a model is one entry here, a rebuild, and `llama-fetch <name>` - no
        other file changes.
      '';
    };

    modelIds = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = lib.mapAttrs (_: m: lib.removeSuffix ".gguf" m.file) cfg.models;
      description = ''
        Model id each GGUF answers to, derived the way llama.cpp derives it.
        Clients name these - users/snowyrenard/hermes.nix reads them for its
        aliases - so a rename here renames the model everywhere.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # root:users 2775, the same shape as the rest of /Vault: any desktop user can
    # fetch a model here without sudo once the directory exists, and the service,
    # which runs as a DynamicUser, can read what they wrote.
    systemd.tmpfiles.rules = [
      "d ${modelsDir} 2775 root users - -"
    ];

    services.llama-cpp = {
      enable = true;
      inherit package;

      settings = {
        host = "127.0.0.1";
        inherit (cfg) port;

        # No `model` key, deliberately: llama-server with no model argument
        # starts as the router over these files instead of loading one of them.
        # The directory is scanned on start, so a newly fetched model appears
        # after a restart of the service.
        "models-dir" = modelsDir;
        "models-max" = cfg.maxResidentModels;

        # Tool calling depends on the template inside the GGUF; this engine's own
        # default is jinja-on, so the flag changes nothing today. It is pinned
        # rather than relied on: a default that flipped, or an engine behind a
        # downgrade, would leave the agent emitting prose where a tool call
        # belongs, which is a silent failure rather than an error.
        jinja = true;

        "n-gpu-layers" = 999;

        # Expert weights to RAM, everything else on the card. Same placement
        # Hermes' own runtime picks for a discrete card with a spilled MoE
        # (local_runtime/context_policy.py, spill_overrides), and the reason
        # decode stays interactive: a token reads only the experts it routes to.
        # 21 GiB of weights do not fit in 14 usable GiB, and this placement is
        # what makes the model usable at all: measured on this host it holds
        # 3.5 GiB of the card and decodes at 29 tok/s. It matches nothing in a
        # dense model, so the 12B is unaffected.
        "cpu-moe" = true;
        # llama.cpp warns that CPU tensor overrides under mmap cost speed
        # ("consider using --load-mode none"). mmap stays on deliberately: this
        # host has no swap, so the alternative is ~21 GiB of anonymous memory the
        # kernel cannot reclaim, which is what turns desktop memory pressure into
        # an OOM kill. Page cache under the mapping can just be dropped and
        # re-read; if first-token latency ever looks wrong, that is the knob.

        # `contextSize` is the option name; llama-server's flag is --ctx-size, and
        # the module renders each settings key verbatim, so the mapping is explicit
        # here rather than an inherit.
        "ctx-size" = cfg.contextSize;
        "batch-size" = 2048;
        "ubatch-size" = 2048;
        "flash-attn" = "on";

        # q8_0 halves the cache for no measurable quality cost, which on a 16 GiB
        # card is the difference between a 64K window and a 32K one.
        "cache-type-k" = "q8_0";
        "cache-type-v" = "q8_0";

        # One slot: the agent is the only client, and each extra slot multiplies
        # the KV cache.
        parallel = 1;

        # The model card's own sampling settings.
        temp = "1.0";
        "top-p" = "0.95";
        "top-k" = 20;
        "min-p" = "0.0";

        # This desktop shares the card with games, so an idle model gives its VRAM
        # back after fifteen minutes - the same window Hermes' own runtime unloads
        # on. Measured on this card with a 3.96 GB model: 6252 MiB of VRAM while
        # loaded, 1896 MiB after the timer, `sleeping` in /models, and a reload on
        # the next request with no client change. The children are spawned from
        # the router and inherit this flag.
        "sleep-idle-seconds" = 900;
      };

      # `contextSize` and the rest land as long options: the module renders each
      # settings key as --<key> <value>, and a boolean true as the bare flag.
    };

    systemd.services.llama-cpp.serviceConfig = {
      # The upstream unit is written for CPU inference. Both GPU runtimes need
      # the device nodes - HIP opens /dev/kfd, Vulkan opens /dev/dri/renderD* -
      # and DynamicUser gets no group memberships of its own. `render` is what
      # those nodes are owned by in the general case (on this host they happen to
      # be world-writable already, but a rebuild should not depend on that). The
      # router spawns one llama-server child per loaded model, and a child
      # inherits this sandbox, so it needs the same access.
      SupplementaryGroups = ["render" "video"];

      # The GPU runtimes load code objects and JIT small shims out of writable
      # memory; Ollama's unit, which does run these cards, leaves this off. The
      # module turns it on for the CPU case.
      MemoryDenyWriteExecute = lib.mkForce false;

      # The weights are mmapped off /Vault, so never start before it is mounted.
      RequiresMountsFor = [modelsDir];
    };

    environment.systemPackages = [llamaFetch];

    networking.hosts = lib.mkIf (cfg.expose && config.device.security.reverse-proxy.enable) {
      "127.0.0.1" = ["ai.lan"];
    };

    services.caddy.virtualHosts =
      lib.mkIf (cfg.expose && config.device.security.reverse-proxy.enable)
      (lib.listToAttrs [
        ((import ../../../lib/vhosts.nix {inherit lib config;}).mkLanVhost {
          name = "ai";
          inherit (cfg) port;
          host = null;
        })
      ]);
  };
}
