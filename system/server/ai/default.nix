# Local inference: one llama.cpp server, declared by the host that runs it.
#
# Hermes already speaks this protocol. It probes 127.0.0.1:8080 for /props,
# fingerprints llama-server by its build_info, and adopts the server it finds
# (hermes_cli/local_runtime/detect.py), then reads the context window from the
# running server rather than from a catalog. A server declared here therefore
# needs no plugin, no API key and no per-user download, and every other local
# client (the desktop app's own Local Models pane, aider, curl) uses the same
# endpoint. The user side of the wiring is users/snowyrenard/hermes.nix.
#
# The model choice is dictated by the card. 16 GiB of VRAM cannot hold a 4-bit
# 30B-class model *and* a 64K window, and the card is shared with a compositor
# and a browser. A mixture-of-experts model is the way out: attention, the KV
# cache and the router stay on the card while the expert tensors stay in RAM
# (--cpu-moe), so a token pays only for the ~3B parameters it activates. A dense
# model that spills instead re-reads its whole self out of RAM on every token.
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
  modelPath = "${modelsDir}/${cfg.model.file}";

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

  # huggingface-hub's CLI fetches the weights at runtime, so a 20 GiB model never
  # becomes a store path: a store copy would be re-downloaded on every pin change
  # and would not be the thing the user is allowed to delete to reclaim space.
  hf = lib.getExe' pkgs.python3Packages.huggingface-hub "hf";

  llamaFetch = pkgs.writeShellScriptBin "llama-fetch" ''
    set -euo pipefail
    echo "fetching ${cfg.model.repo}:${cfg.model.file}"
    echo "into ${modelsDir} ($(du -sh ${modelsDir} 2>/dev/null | cut -f1 || echo empty))"
    exec ${hf} download ${cfg.model.repo} ${cfg.model.file} \
      --revision ${cfg.model.revision} \
      --local-dir ${modelsDir}
  '';
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
        Context window to serve. Every model Hermes recommends gets at least 64K.
        A hybrid-attention model costs very little per token here (this one holds
        10 full-attention layers, ~10 KiB of q8 cache per token), so raising this
        is cheap until the KV cache plus the compute buffer stop fitting on the
        card; 131072 is the next sensible step.
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

    model = {
      repo = lib.mkOption {
        type = lib.types.str;
        default = "unsloth/Qwen3.6-35B-A3B-MTP-GGUF";
        description = "Hugging Face repository the weights come from.";
      };

      revision = lib.mkOption {
        type = lib.types.str;
        default = "5bc3e238d916f48a861bac2f8a1990a0e9b7e98d";
        description = ''
          Commit the download is pinned to, so llama-fetch is reproducible and a
          re-upload upstream cannot swap the weights under a running config.
        '';
      };

      file = lib.mkOption {
        type = lib.types.str;
        default = "Qwen3.6-35B-A3B-UD-Q4_K_M.gguf";
        description = ''
          The GGUF in that repository. This is Hermes' own catalog entry for the
          model ("validated" there): 35B total parameters, 3B active, 262144
          native context, multi-token-prediction heads. ~22.7 GB on disk, of
          which only the attention half needs to be on the GPU.
        '';
      };

      alias = lib.mkOption {
        type = lib.types.str;
        default = "qwen3.6-35b-a3b";
        description = ''
          Name the API answers to (llama-server --alias). This is the model id
          every client sees, including Hermes' picker.
        '';
      };
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
        model = modelPath;
        inherit (cfg.model) alias;

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
        # 21 GiB of weights do not fit in 14 usable GiB, but 1.7 GiB of active
        # experts per token over ~70 GB/s of DDR5 do.
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

        # This desktop shares the card with games, so the server gives the VRAM
        # back after fifteen minutes of silence - the same idle window Hermes'
        # own runtime unloads on. The process and its page cache stay; the next
        # request reloads the model.
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
      # be world-writable already, but a rebuild should not depend on that).
      # Skipping the groups entirely is also what upstream's GPU-capable Ollama
      # unit does, minus the DeviceAllow list it needs because it closes
      # DevicePolicy.
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
