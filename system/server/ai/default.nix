# Local inference: one llama.cpp server holding Qwen3.6-35B-A3B, built for ROCm,
# with the MoE expert cache that makes a 20.8 GiB model live on a 16 GiB card.
#
# This is the single-model descendant of the four-model router that 2f9f78b
# deleted. The router is not coming back: it needed a preset INI, two link farms,
# a separate CPU port for titles and a draft-head-per-model matrix, and it served
# three models nothing was calling. What was worth keeping is the plumbing below
# - weights as pinned store paths, the per-architecture ROCm scope, a context
# window that is a decision rather than a leftover - plus two things the old build
# could not do, both added in October 2026 and both cheaper on this card than the
# alternative they replace:
#
#   --cpu-moe          keeps the expert tensors in RAM instead of streaming them
#                      to the card. A 35B-A3B pays for ~3B parameters per token,
#                      so the experts are the 18 GiB of the 20.8 GiB file that
#                      nothing reads on most tokens.
#   --moe-cache-mib N  holds the hottest of those CPU experts in VRAM. Without it
#                      every expert read crosses PCIe; with it the miss rate falls
#                      to the cache's hit rate (llama.cpp #29887 measured 25.0 ->
#                      39.4 t/s on a 24 GiB card, 30.8 -> 54.5 t/s on a 32 GiB one).
#                      It only engages on batches of <= 32 tokens, so it buys
#                      decode, never prefill.
#
# The KV cache stays uncompressed: f16 is llama.cpp's own default and its highest
# precision for K and V short of f32, which doubles the same numbers for no gain
# anyone has measured. On this hybrid layout - 40 blocks, only every fourth one
# full-attention, 2 KV heads x 256 dims - a token costs 20 KiB at f16, so the
# window is affordable in a way a dense model's would not be:
#
#     32K  0.66 GiB      64K  1.31 GiB      128K  2.62 GiB      256K  5.24 GiB
#
# That is the trade the two knobs below make: the expert cache and the context
# window are the only two things competing for what the weights leave free.
#
# `enable` and the knobs below are this service's own: they are declared in this
# file, because the module's path is not its option name and the tree cannot
# derive one from the other.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.device.app.ai;

  # gfx1201 is the RX 9070/XT (RDNA4). nixpkgs' rocmPackages carries a
  # per-architecture scope (`rocmPackages.gfx1201`) that pins clr and everything
  # built against it to this one GPU, so the HIP build does not compile for the
  # other nineteen targets; rocmGpuTargets follows clr's localGpuTargets from that
  # scope. ROCm rather than Vulkan because HIP *is* the CUDA backend in llama.cpp:
  # the expert cache and the MoE kernels land there first, while Vulkan's batched
  # upload path is still the slow one (#29887's author calls it "not fully
  # optimised", and #30697 is still open for a load-time crash on RDNA2/3).
  #
  # Do not export GGML_CUDA_ENABLE_UNIFIED_MEMORY here: on RDNA it makes the
  # driver migrate pages behind llama.cpp's back and silently corrupts output
  # (#26148). HSA_OVERRIDE_GFX_VERSION is not needed either - ROCm 7 knows
  # gfx1201 natively, and the override is what breaks every other card family.
  base =
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

  # nixpkgs pins llama.cpp v0.6.0, which predates the MoE cache *entirely*: the
  # 0.6.0 binary this machine still runs answers "--moe-cache-mib" with
  # `error: invalid argument`. v0.7.0 (2026-10-15) is the newest upstream release
  # that ships src/llama-moe-cache.cpp, so the source is swapped to it here
  # rather than waiting for nixpkgs to bump - the release is already older than
  # the cache code it carries, so the wait has no useful length.
  #
  # The three hashes and the dropped patch are all consequences of that swap:
  # `patches` is emptied because the recipe's #30034 backport is upstream by
  # 0.7.0 and no longer applies, and npmDepsHash is regenerated because the web
  # UI's lockfile moved. `doCheck = false` because ctest downloads models over
  # the network and the backport being gone makes the recipe's test fix moot.
  # 0.7.0's cache is the original LRU one (#29887); the SLRU replacement that
  # measures 1-5% better (#30637) landed after this tag.
  package = base.overrideAttrs (old: {
    version = "0.7.0";
    src = pkgs.fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      tag = "v0.7.0";
      hash = "sha256-pEDYgI3AMTU+cekvRX7NNt5wddznydQSNuerswvEpsA=";
    };
    patches = [];
    npmDepsHash = "sha256-hqYzdp1FwPhYkBP278fQXgY9NCKB6Q3P6Gko7BfP0m0=";
    doCheck = false;
  });

  # Weights are a store path, for the reason the old router stated and this file
  # keeps: a file fetched at runtime is only as reproducible as the command
  # someone happened to run, and its hash is never checked. The hash is Hugging
  # Face's LFS object id, which is the file's sha256, so a pin can be verified
  # through the API without downloading 20.8 GiB. Garbage collection reclaims it.
  model = pkgs.fetchurl {
    url = "https://huggingface.co/${cfg.model.repo}/resolve/${cfg.model.revision}/${cfg.model.file}";
    sha256 = cfg.model.sha256;
    name = baseNameOf cfg.model.file;
  };
in {
  options.device.app.ai = {
    enable = lib.mkEnableOption "the llama.cpp inference server for the agent's local model";

    backend = lib.mkOption {
      type = lib.types.enum ["rocm" "vulkan"];
      default = "rocm";
      description = ''
        GPU backend the server is built against. Both are complete builds of
        llama.cpp, not switches on one binary. "rocm" is the default because the
        expert cache sits on the HIP/CUDA path and Vulkan's upload path is the
        one still being optimised; "vulkan" is kept because it costs minutes
        rather than hours to rebuild and is the cheaper one to be wrong about.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = ''
        Port on loopback. 8080 is llama-server's own default and the port Hermes
        probes for a server it did not start; the user half of the wiring
        (users/snowyrenard/hermes/home.nix) names it in the `local` alias.
      '';
    };

    contextSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 131072;
      description = ''
        Context window the server is started with. 128K is not a round number
        picked for the card: Qwen's own model card says the model "leverages
        extended context for complex tasks" and advises "maintaining a context
        length of at least 128K tokens to preserve thinking capabilities", and
        their published agent benchmarks (Terminal-Bench 2.0, QwenClawBench) were
        run at 256K. The native window is 262,144 and extensible to 1.01M, so
        262144 is reachable here too - it costs 5.24 GiB of f16 KV instead of
        2.62 GiB, which is expert cache given up for context nothing in an agent
        loop has needed.
      '';
    };

    expertCacheMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 6656;
      description = ''
        VRAM, in MiB, for the CPU-resident experts (llama.cpp's
        --moe-cache-mib). This and `contextSize` are the only two numbers that
        compete for the card, and this is the cheaper of them to raise.

        Measured on this machine (gfx1201, 128K window, f16 KV, desktop holding
        ~1.5 GiB, 256-token generations, two runs each, second run quoted):

          cache    no MTP      with MTP     peak VRAM    headroom
              0    36.0 t/s         -        7.12 GiB   8.8 GiB
           6656               101.9 t/s     14.3 GiB   1.5 GiB  (default)
           7168    52.9 t/s   103.3 t/s     15.0 GiB   0.9 GiB
           7680    57.6 t/s   107.4 t/s     15.4 GiB   0.5 GiB
           8192    58.5 t/s       -         15.0 GiB   0.9 GiB  (no MTP draft ctx)
           9216    60.7 t/s       -         15.8 GiB   0.06 GiB

        MTP (below) adds ~0.85 GiB of draft context and roughly doubles decode,
        which is why the cache is *smaller* here than it was without it: 18 GiB
        of experts do not fit either way, the cache only decides how many of
        them are already on the card, and 6.5 vs 7.5 GiB is 6% of throughput for
        three times the VRAM headroom. 7680 is the fastest thing that runs and
        0.5 GiB is not enough to share with a compositor that can spike.

        A game running first changes the arithmetic outright - VRAM already in
        use is not available at load, and an allocation error there is a failed
        start, not a degraded one (#30697).
      '';
    };

    modelAlias = lib.mkOption {
      type = lib.types.str;
      default = "qwen3.6-35b-a3b";
      description = ''
        The model id clients send, which llama-server makes up from the file
        name unless --alias overrides it. Kept lowercase and undecorated so the
        Hermes-side alias can name it verbatim.
      '';
    };

    model = {
      repo = lib.mkOption {
        type = lib.types.str;
        default = "unsloth/Qwen3.6-35B-A3B-MTP-GGUF";
        description = ''
          Hugging Face repository the weights come from. The -MTP- one, not the
          plain -GGUF-: the checkpoint carries 19 `mtp.*` tensors (one NextN
          block, an fc projection and its MoE experts) and only this conversion
          keeps them. Without them llama.cpp refuses MTP outright -
          `model doesn't contain MTP layers` - which is what the plain quant
          answers.
        '';
      };

      revision = lib.mkOption {
        type = lib.types.str;
        default = "5bc3e238d916f48a861bac2f8a1990a0e9b7e98d";
        description = ''
          Commit the download is pinned to, so the store path is reproducible and
          a re-upload upstream cannot swap the weights under a running config.
        '';
      };

      file = lib.mkOption {
        type = lib.types.str;
        default = "Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf";
        description = ''
          The GGUF in that repository - 21.3 GiB, architecture qwen35moe. The
          MTP heads cost 0.5 GiB over the trunk-only file. Q4_K_XL rather than
          Q4_K_M for the extra spent on the attention and output tensors, which
          are the ones that stay on the card and the ones a 3B-active model
          reads on every token.
        '';
      };

      sha256 = lib.mkOption {
        type = lib.types.str;
        default = "sha256-VZg8WnWhq5aYJAd7O7PeQUboKpI0BytIrU6Pkq0/6fE=";
        description = ''
          Hash of that file in SRI form. Hugging Face publishes it as the LFS
          object id of the revision, so it can be filled without downloading.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.llama-cpp = {
      enable = true;
      inherit package;

      # Flag names are nixpkgs' cli conventions: a multi-character key becomes
      # --key, and a `true` boolean becomes the bare flag, which is how
      # "cpu-moe" ends up as --cpu-moe rather than --cpu-moe true.
      settings = {
        host = "127.0.0.1";
        inherit (cfg) port;

        model = "${model}";
        alias = cfg.modelAlias;

        # 999 rather than "all": every non-expert layer goes to the card, and the
        # expert tensors are taken back out by cpu-moe below.
        n-gpu-layers = 999;
        cpu-moe = true;
        moe-cache-mib = cfg.expertCacheMiB;

        # Read the weights into RAM instead of mmapping them. The CPU-resident
        # experts are copied to the card from that buffer, and llama.cpp warns
        # at load that the combination of mmap and per-tensor CPU overrides is
        # the slow path: measured 57.6 -> 61.1 t/s at 7680 MiB, at the cost of
        # holding the whole 21.3 GiB resident (46 GiB of 62 stayed available).
        load-mode = "none";

        # Speculative decoding from the model's own MTP heads - no second model
        # file, no extra VRAM for a draft, and it is what the -MTP- repo pin in
        # `model` exists for: the trunk-only GGUF answers this flag with
        # "model doesn't contain MTP layers" and refuses to start.
        #
        # Measured, same prompt, cache 6656: 60.7 -> 101.9 t/s, i.e. decode
        # nearly doubles. The log line to watch is `slot print_timing ... draft
        # acceptance = 0.785, mean len = 3.36` - 3.36 tokens accepted per step
        # for 3 drafts offered. `--spec-draft-n-max` above 3 does not help here:
        # 6 measured 83.0 t/s and 2 measured 102.3, so the default of 3 is the
        # peak and this is spelled out rather than left to the default so it
        # cannot drift.
        spec-type = "draft-mtp";
        spec-draft-n-max = 3;

        ctx-size = cfg.contextSize;

        # Uncompressed on purpose, both halves. f16 is the default and this file
        # says so out loud so no later edit drifts into q8_0 for the VRAM: the
        # window above is already sized with f16 in it, and a quantised KV cache
        # is the one saving that degrades the thing the context is for.
        cache-type-k = "f16";
        cache-type-v = "f16";

        # Flash attention on: with an uncompressed KV cache it is a speed and
        # buffer win and no precision question, and it is what the old build ran.
        flash-attn = "on";

        # Slots stay on auto (llama.cpp's -np -1), which on this machine comes up
        # as 4, and the KV is one unified pool the slots draw from rather than
        # four fixed slices - so an agent with a 90K prompt and three agents with
        # 5K prompts coexist, which a hard --parallel 1 or a 4-way split of
        # 131072 cannot do. Measured with 400-token replies:
        #
        #   agents   aggregate   per agent      wall
        #        1    77.3 t/s     77.4 t/s      5.2s
        #        2   112.7 t/s     57.3 t/s      7.1s
        #        4   148.6 t/s     37.7 t/s     10.8s
        #        8   158.5 t/s     37.9 t/s     20.2s (4 queued)
        #
        # So four is the knee: twice the aggregate of one at half the per-agent
        # rate, and the fifth concurrent request waits rather than degrades.
        # cache-ram gives idle slots somewhere to park their KV (4 GiB of the
        # 62 GiB of RAM, which is also where the experts live) so a returning
        # agent resumes instead of re-prefilling. jinja renders the chat template
        # and the tool-call schema from the GGUF, which is what makes this
        # model's tool calls work at all.
        kv-unified = true;
        cache-ram = 4096;
        jinja = true;

        # Five minutes of read/write tolerance before a stuck stream is dropped.
        # The default is an hour, which is long enough that a wedged client holds
        # a slot forever; 300s still covers a 100K-token prefill at the measured
        # 480 t/s and the reply after it.
        timeout = 300;

        batch-size = 2048;
        ubatch-size = 512;

        # Never sleep. Sleeping is what "disconnecting" looks like from a client:
        # after a quarter hour idle the model is unloaded and the next request
        # either waits out a full reload or errors outright, so an agent that
        # idles between turns drops its endpoint. The cost of staying up is the
        # VRAM below, and it is 1.6 GiB under the card's limit.
        sleep-idle-seconds = -1;
      };
    };
  };
}
