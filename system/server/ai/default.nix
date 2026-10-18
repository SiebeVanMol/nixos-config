# Local inference: one llama.cpp server in router mode over the model files on
# /Vault, sized for this machine's own GPU.
#
# Two models for two jobs. `agent` is what an agent loop thinks with: a 35B
# mixture-of-experts whose expert tensors live in RAM, so a token pays only for
# the ~3B parameters it activates. `quick` is a small dense model for a question
# or a page summary, and `tiny` titles sessions. `oss` and `qwen27` are the two
# alternatives to `agent`, both of them recommendations rather than guesses:
# gpt-oss-20b activates 3.6B and fits the card outright, with the best
# tool-calling measured in its size class, while Qwen3.8-27B is a dense 27B at
# 3 bits whose hybrid attention keeps a long window nearly free.
#
# Four of the five decode with a draft head, which is the largest single win
# available on this card: generation is bandwidth-bound, so a head that guesses
# the next few tokens correctly lets the engine verify them in one pass instead
# of one per token. `agent` carries its head fused in the same file; `quick`,
# `qwen27` and `oss` need a second one, which lives outside --models-dir because
# the router would otherwise offer a 0.5-1.4 GB head to clients as a model.
# They are wired per model through a preset INI, because a head is only valid
# against the revision it shipped with - see the note on `models`.
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
# `enable` and the knobs below are this service's own: they are declared in this
# file, because the module's path is not its option name and the tree cannot
# derive one from the other. The other host toggles are derived in
# system/options.nix.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.device.app.ai;

  modelsDir = "/Vault/llama/models";

  # Draft heads sit outside the models directory: the router scans that
  # directory for models, so a speculative head lying beside the weights would
  # be offered to clients as a model of its own. A head is not optional once a
  # model declares one - measured against this build, a missing file fails the
  # model's load with a 500 and takes the child down rather than falling back to
  # plain decoding - so `llama-fetch <model>` has to run before anything asks for
  # a model that has one. `agent` is fused and needs no fetch; the other three
  # answer only after theirs.
  draftsDir = "/Vault/llama/drafts";

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

  # A draft head is pinned and fetched exactly like the weights: a speculative
  # decoder is only valid against the revision it was trained with, so an
  # unpinned head is a slower way of fetching something that may not load.
  fetchLine = name: m:
    [
      "  ${name})"
      "    fetch ${name} \"${m.repo}\" \"${m.file}\" \"${m.revision}\" ${modelsDir}"
    ]
    ++ lib.optional (m.draft.type != "none" && m.draft.file != null)
    "    fetch ${name}-draft \"${m.repo}\" \"${m.draft.file}\" \"${m.revision}\" ${draftsDir}"
    ++ ["    ;;"];

  fetchAllLine = name: m:
    [
      "    fetch ${name} \"${m.repo}\" \"${m.file}\" \"${m.revision}\" ${modelsDir}"
    ]
    ++ lib.optional (m.draft.type != "none" && m.draft.file != null)
    "    fetch ${name}-draft \"${m.repo}\" \"${m.draft.file}\" \"${m.revision}\" ${draftsDir}";

  # Speculative decoding and the context window are both per model, and neither
  # can be a command-line flag: `--ctx-size` on the CLI outranks the preset, so a
  # per-model window is only reachable through this file. The `[*]` section is
  # the default everything inherits; a model section overrides it.
  presetGlobal = ''
    [*]
    ctx-size = ${toString cfg.contextSize}
    fit-ctx = ${toString cfg.contextSize}
  '';

  presetSection = _: m:
    lib.optionalString (m.draft.type != "none" || m.ctx != null)
    (''[${lib.removeSuffix ".gguf" m.file}]''
      + "\n"
      + lib.optionalString (m.ctx != null) ''
        ctx-size = ${toString m.ctx}
        fit-ctx = ${toString m.ctx}
      ''
      + lib.optionalString (m.draft.type != "none") ''
        spec-type = ${m.draft.type}
        spec-draft-n-max = ${toString m.draft.nMax}
      ''
      + lib.optionalString (m.draft.type != "none" && m.draft.file != null) ''
        spec-draft-model = ${draftsDir}/${m.draft.file}
      ''
      + "\n");

  modelsPreset = pkgs.writeText "llama-models.ini" (
    presetGlobal + lib.concatStrings (lib.mapAttrsToList presetSection cfg.models)
  );

  llamaFetch = pkgs.writeShellScriptBin "llama-fetch" (lib.concatStringsSep "\n" (
    [
      "set -euo pipefail"
      ""
      "fetch() {"
      "  echo \"==> $1: $3\""
      "  ${hf} download \"$2\" \"$3\" --revision \"$4\" --local-dir \"$5\""
      # huggingface-hub writes 0600 under the caller's umask, and the service is
      # a DynamicUser: weights it cannot read are the one failure that looks like
      # a corrupt model. Weights are not secret, so make what was just written
      # world-readable. Tolerant on purpose: -R also visits the directory itself,
      # which root owns here (2775 root:users, already readable and writable), and
      # a test.sh-less `set -eux` aborted the whole fetch on exactly that.
      "  chmod -R a+rX \"$5\" 2>/dev/null || true"
      "}"
      ""
      "case \"\${1:-all}\" in"
    ]
    ++ lib.concatMap (n: fetchLine n cfg.models.${n}) (lib.attrNames cfg.models)
    ++ (
      ["  all)"]
      ++ lib.concatMap (n: fetchAllLine n cfg.models.${n}) (lib.attrNames cfg.models)
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
    # Declared here rather than derived from the tree: this module is
    # server/ai/default.nix, whose path is not its option name.
    enable = lib.mkEnableOption "llama.cpp inference server (system/server/ai, sized by device.app.ai.backend)";

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
        Hermes probes for a server it did not start. Everything that talks to
        this server derives its URL from this option, so raising it is a change
        here alone.
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
      default = 2;
      description = ''
        How many models may be loaded at once. 1 keeps the card for whichever
        model is in use, so switching is a load and an unload. 2 is measured to
        fit only barely here: the 12B holds 8.2 GiB above the desktop's own
        ~1.9 GiB and the agent model another 3.5 GiB, i.e. ~13.6 GiB of the
        14.27 GiB free, leaving nothing for a browser. 1 stayed the default
        while there were two models.

        With five it is still 2, and `tiny` is the reason: Hermes asks that model for
        a session title at the start of every session, and at models-max 1 the
        request would unload whichever chat model was resident - a title costing
        a 75 s reload of the agent model on the next turn. The pairs that happen
        in practice fit: tiny with the agent model is ~6.5 GiB, tiny with the
        12B ~11.2 GiB. The pair that does not fit is the 12B and the agent model
        together, which now takes loading both within the fifteen-minute idle
        window - set this back to 1 to forbid that and accept the reload.
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
          ctx = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.positive;
            default = null;
            description = ''
              Context window for this model, when it should differ from
              `contextSize`. A model whose attention is mostly sliding-window or
              hybrid pays so little per token that it can hold twice the default
              window in the same VRAM; one that only just fits at the default
              cannot. Null means the default.
            '';
          };
          draft = lib.mkOption {
            default = {};
            description = ''
              Speculative decoding for this model. Off by default: a draft head
              only helps a model that shipped with one, and using the wrong one
              is a decode path that guesses badly rather than an error.
            '';
            type = lib.types.submodule {
              options = {
                type = lib.mkOption {
                  type = lib.types.enum ["none" "draft-mtp" "draft-eagle3" "draft-simple"];
                  default = "none";
                  description = ''
                    llama-server's --spec-type. MTP and EAGLE3 are the two heads
                    the recommended models actually publish; both are worth about
                    2x decode on a bandwidth-bound card, and neither helps prefill.
                  '';
                };
                file = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = ''
                    The head in the same repository, when it is not fused into
                    the weight file. Positional path, so a head the repository
                    keeps in its own directory keeps that directory.
                  '';
                };
                nMax = lib.mkOption {
                  type = lib.types.ints.positive;
                  default = 3;
                  description = ''
                    Tokens to draft per step (--spec-draft-n-max). The engine's
                    own default is 3; higher drafts more per step and loses more
                    when the guesses miss.
                  '';
                };
              };
            };
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
          # 128K, and it costs about a tenth of decode: measured on this card with
          # its head on, 79.6 t/s at 64K against 72.0 at 128K, in the same VRAM
          # (14966 against 15022 MiB - fit spills differently, not more). The
          # window is the trade an agent model wants: half as many compressions of
          # a long session for 9.5% of the token rate.
          ctx = 131072;
          # Fused: the MTP repository ships its quants with the draft tensors
          # already in them, so this model needs a flag and no second fetch.
          draft.type = "draft-mtp";
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
          # 128K of its 256K trained window: the 12B's attention is sliding-window
          # (1024 tokens), so the extra window costs a fraction of a GiB, and this
          # is the model that summarises pages and holds long drafts.
          ctx = 131072;
          # The Q8_0 head, not the BF16 one: 0.47 GB against 0.86 GB for the
          # same job, and the weights it drafts for are 4-bit.
          draft = {
            type = "draft-mtp";
            file = "MTP/mtp-gemma-4-12B-it-Q8_0.gguf";
          };
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

        oss = {
          repo = "ggml-org/gpt-oss-20b-GGUF";
          revision = "ef9b12f2ff56c69cf32153a02784e7a3c88bf524";
          file = "gpt-oss-20b-MXFP4.gguf";
          # 64K, not the trained 128K it was given first. The sliding-window
          # argument (24 blocks on a 128-token window, so the cache is small) held
          # for VRAM but not for speed: measured on this card with the eagle3 head
          # on, 70.0 t/s decode at 64K against 50.1 at 128K, and prefill 524
          # against 373 - the wider window costs a third of both. Gemma 12B is the
          # one where it really is free (110.1 against 111.6), because its cache
          # per token is a constant around a 1024-token window; here the attention
          # still spans the whole prompt, so the window is paid per token.
          ctx = 65536;
          draft = {
            type = "draft-eagle3";
            file = "eagle3-gpt-oss-20b-Q8_0.gguf";
          };
          note = ''
            The resident option: 20B total but 3.6B active, and 12.11 GB of
            weights, which fits this card outright - no expert spill, no fit
            negotiation, and a window that is paid for out of the ~3.8 GiB left
            over rather than out of compressed weights.

            MXFP4 is the vendor's own storage format, and on RDNA4 it is storage
            only: the silicon has no FP4 matrix instruction, so llama.cpp's
            Vulkan kernels unpack 4.25 bpw to f16 and dot that. The bytes per
            weight still decide decode speed here, which is why 12.11 GB behaves
            like a 12 GB model rather than like a 4-bit one from a denser family.

            Recommended over every other 16 GB candidate in the eval that
            actually tested agentic work rather than benchmarks: it was the only
            model to pass all eight tasks, including a two-step tool-calling
            exchange. Owners of this card report ~92 t/s through ROCm and
            several hundred t/s of prefill, so it is also the fastest thing here
            per token by a wide margin.
          '';
        };

        qwen27 = {
          repo = "unsloth/Qwen3.8-27B-GGUF";
          revision = "4ca720788d1e01f1bff70c033e0d0028fd02e502";
          file = "Qwen3.8-27B-UD-IQ3_S.gguf";
          # No draft head, although the repository publishes one: measured on
          # this card at 512 tokens it takes the model from 38.7 t/s to 15.8,
          # i.e. the MTP head is not the one this 3-bit conversion was made for
          # and every drafted token is verified and thrown away. The head is
          # therefore not even fetched - `llama-fetch qwen27` gets the weights
          # alone.
          note = ''
            The dense alternative, and the reason it is 3 bits rather than 4:
            IQ4_XS is 14.25 GB, which leaves this card nothing for a cache, while
            IQ3_S is 12.04 GB and leaves ~2.5 GiB. A dense model does not spill
            gracefully - every weight is read on every token - so the quant has
            to fit outright or the speed is lost to the trade the MoE entries
            above make deliberately.

            What makes 3 bits tolerable here is the architecture: a hybrid with
            only every fourth block doing full attention, so KV costs roughly
            10 KiB/token instead of a plain 27B's hundreds - a 64K window is
            ~0.6 GiB, which is what lets a dense 27B hold an agent's context at
            all. Owners of this card report ~36 t/s decode and ~1.4K t/s prefill
            on this exact quant, and call it smarter than the 9B and the 26B-A4B
            despite the bit depth.

            Not in Hermes' catalog, so its tool-calling template is worth testing
            before trusting it with an agent loop; `agent` remains the default
            for that job.
          '';
        };

        tiny = {
          repo = "unsloth/gemma-4-E2B-it-GGUF";
          revision = "0314792d7f1f7e229411f620751375812bb9faf2";
          file = "gemma-4-E2B-it-Q4_K_M.gguf";
          note = ''
            The title model: the smallest of the family the other two come from,
            for the one job that needs no more than this - Hermes asks for a
            3-7 word JSON title once per session.

            3.11 GB of weights, against 6.72 GB for the 12B that held this slot
            before. Replacing the 12B is the point: it was loaded at the start of
            every session and held ~10 GiB of the card for the next fifteen
            minutes, after a ~23 s cold load off /Vault, to emit five tokens.

            E2B is the family floor (E2B < E4B < 12B < 26B < 31B), so this is
            the smallest gemma-4 rather than an older small line: 1B-class models
            a generation back start at 0.81 GB (gemma-3-1b-it), and holding a
            JSON contract this simple is exactly where a 1B gives way, which
            Hermes answers by keeping its own derived title instead.

            Plain Q4_K_M, not the UD-Q4_K_XL the 12B takes: none of this is QAT
            weights, so the dynamic quant would buy 70 MB and no accuracy.

            It starts in thinking mode: a request with no reasoning control
            comes back with the whole budget spent in `reasoning_content` and
            nothing in the content, which reads as a broken model and is not
            one. Hermes turns it off on every call (`reasoning_effort: none`,
            the shape its custom profile projects for a disabled
            `reasoning_config`); a hand-written request has to say so itself.
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
      "d ${draftsDir} 2775 root users - -"
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

        # Per-model arguments, which is where speculative decoding lives: the
        # section for each model that has a draft head carries --spec-type and
        # the head's path, and the models without one simply have no section.
        "models-preset" = modelsPreset;

        # Tool calling depends on the template inside the GGUF; this engine's own
        # default is jinja-on, so the flag changes nothing today. It is pinned
        # rather than relied on: a default that flipped, or an engine behind a
        # downgrade, would leave the agent emitting prose where a tool call
        # belongs, which is a silent failure rather than an error.
        jinja = true;

        # Placement is left to llama.cpp's own fit logic instead of pinned, and
        # that is a measured decision rather than a default: `--fit` only adjusts
        # arguments left *unset*, so setting `n-gpu-layers` and `cpu-moe`
        # together is itself what switches it off - which is how this file spent
        # its first version, holding 3.5 GiB of the card and decoding at 29-31
        # tok/s. Released on a spare port against the same model, same prompt,
        # same 128 tokens: 37.9 tok/s decode, 101 tok/s prefill, 13.2 GiB
        # resident, settling on 41 of 42 layers with CPU tensor overrides for
        # the remainder.
        #
        # The old placement was not wrong, it was conservative in one direction
        # only: pinning experts to RAM assumes the card has no room for any of
        # them, so 8.5 GiB sat idle while every expert matmul ran on the CPU.
        # Fit decides per launch from the VRAM free at that moment, so the
        # placement tracks what else holds the card instead of assuming a 14 GiB
        # budget. `cpu-moe` also matched nothing in a dense model, so the 12B
        # is unaffected either way.
        #
        # The cost is that the split is load-order dependent: with
        # `models-max = 2`, whichever model loads second fits around the first.
        # The reproducible form is to read the split the first launch chose
        # (`-v` prints `offloaded N/M layers to GPU`) and pin `n-cpu-moe` to it.
        "fit" = "on";

        # MiB left free per device while fitting. This desktop shares the card
        # with games, so this is the dial to raise if a model ever loads too
        # eagerly - not a return to `cpu-moe`, which gives away the whole card.
        "fit-target" = 1024;

        # Both the window and the floor fit may shrink to are per model now, so
        # they live in the preset (`[*]` for the default, a section for a model
        # that can afford more). Deliberately not on this command line: a CLI
        # argument outranks the preset, which would flatten every model back to
        # one window - that is what the previous version did without meaning to.
        #
        # The floor exists so fit trades layers for VRAM and never window for
        # VRAM: a 32K agent model is not the model this host serves.

        # llama.cpp warns that CPU tensor overrides under mmap cost speed
        # ("consider using --load-mode none"). mmap stays on deliberately: this
        # host has no swap, so the alternative is ~21 GiB of anonymous memory the
        # kernel cannot reclaim, which is what turns desktop memory pressure into
        # an OOM kill. Page cache under the mapping can just be dropped and
        # re-read; if first-token latency ever looks wrong, that is the knob.
        # Expert tensors reach the CPU through exactly these overrides whenever
        # fit spills, so the warning appears in the log on every load.

        # `contextSize` is the option name; llama-server's flag is --ctx-size, and
        # the module renders each settings key verbatim, so the mapping is explicit
        # in the preset rather than an inherit here.
        "batch-size" = 2048;
        # 1024, not the 2048 that matched the batch size. A 2048-token micro-batch
        # costs the card its stride: measured on this host at 64K, gpt-oss-20b
        # decoded 87.0 t/s and prefilled 554, against 147.0 and 989 at 1024 - the
        # same weights, the same 13.8 GiB, one flag apart. Repeating the pair gave
        # 128.4/946 at 512 and 145.4/997 at 1024, so 1024 is the plateau and 2048
        # is the cliff. The 35B gains prefill from it too (157 to 197 t/s at 128K,
        # decode within noise), and the 12B does not move either way, which is why
        # this is global rather than per model.
        "ubatch-size" = 1024;
        "flash-attn" = "on";

        # q8_0 halves the cache for no measurable quality cost, which on a 16 GiB
        # card is the difference between a 64K window and a 32K one.
        #
        # q4_0 is not an option here, and that is a decision rather than a
        # measurement: the 9070 XT numbers invite it (delta PPL 0.004 against
        # q8_0, "quality-free" by perplexity, and it is what makes a 96K window
        # fit), but a cache that is cheap by perplexity is still a cache whose
        # errors accumulate across a long agent session, where they compound
        # instead of averaging out. Long context is bought by picking a model
        # with a cheap cache, not by degrading the one it has.
        "cache-type-k" = "q8_0";
        "cache-type-v" = "q8_0";

        # Prefix reuse, and the measurement first, because the obvious claim is
        # wrong: the same 4403-token prompt sent twice returned prompt_ms 4174 then
        # 16 - and it returns 16 with or without this flag. llama.cpp already
        # matches a common prefix against the slot's cache, so an ordinary agent
        # turn, where each request appends to the last, is cached either way and
        # this flag is not what buys it.
        #
        # What it adds is the case where the common prefix breaks before its end.
        # When a long session fills the window the oldest messages drop out of the
        # middle and everything after them shifts; 256 is the shortest run of
        # tokens worth shifting KV positions for rather than re-running prefill
        # over the surviving tail. Below the floor it neither costs nor does
        # anything, which is the right side to err on for a flag whose failure
        # mode would be a subtly worse prompt than the one that was sent.
        "cache-reuse" = 256;

        # One slot: the agent is the only client, and each extra slot multiplies
        # the KV cache.
        parallel = 1;

        # The model card's own sampling settings.
        temp = "1.0";
        "top-p" = "0.95";
        "top-k" = 20;
        "min-p" = "0.0";

        # This desktop shares the card with games, so an idle model gives its VRAM
        # back after five minutes. That is deliberately shorter than Hermes' own
        # fifteen-minute unload window: the agent still holds the model, so the
        # next turn after a lull pays a reload - measured cold, ~23 s for the 12B
        # and ~75 s for the 35B off /Vault - instead of the card staying claimed
        # for another ten minutes. Sleeping is not unloading: measured here with a
        # 3.96 GB model, 6252 MiB of VRAM while loaded, 1896 MiB after the timer,
        # `sleeping` in /models, and a reload on the next request with no client
        # change. The children are spawned from the router and inherit this flag.
        "sleep-idle-seconds" = 300;
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
