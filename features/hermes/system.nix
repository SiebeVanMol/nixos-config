# The local effort judge: one llama.cpp server holding Kev-0.8B on the CPU.
#
# The agent runs on DeepSeek. What stays local is the one model whose job a cloud
# model does worse and dearer: Kev answers a multiple-choice question - which
# effort fits this prompt - with a probability per labelled option in a single
# forward pass, ~50 ms and no tokens billed. That makes per-turn effort a lookup
# rather than a sampled judgement, and it is what the plugin's `jev` backend in
# features/hermes/home.nix posts to.
#
# It is deliberately the only local model left. The 35B/12B/20B chat models, the
# router, the speculative-decoding presets, the CPU title server and the ai.lan
# vhost went when the agent moved to DeepSeek alone: measured at $0.0015 a call
# over 556 calls, the local models were never the cheaper option - they were the
# offline one, and they cost 59 GB of store, a 16 GB card and 740 lines of
# routing to keep. Their pins and flags are in git history
# (`git log -- features/hermes/system.nix`), so any of them can be brought back
# without re-deriving a hash.
#
# CPU on purpose: 0.8B in Q8 is 812 MB of RAM and answers in one pass, and this
# desktop shares its card with games - nothing here may claim VRAM.
#
# `enable` and `port` are declared in this file because the module's path is not
# its option name; a host sets only `ai.enable`.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.device.app.ai;

  # Pinned as a fixed-output derivation like every other input here: the file is
  # named by its sha256, and that hash is the LFS object id Hugging Face reports
  # for the revision, so the pin can be checked without downloading.
  kev = pkgs.fetchurl {
    url = "https://huggingface.co/ggml-org/Kev-0.8B-GGUF/resolve/9231cb757e3320120077e42e52371971968f008d/Kev-0.8B-Q8_0.gguf";
    sha256 = "sha256-JyePNOsyc7zupMBT3FDdYaUWHaIacYxKrN+P1YMHcdA=";
    name = "Kev-0.8B-Q8_0.gguf";
  };
in {
  options.device.app.ai = {
    enable = lib.mkEnableOption "the local effort judge (Kev-0.8B on the CPU)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = ''
        Loopback port of the judge server. 8080 is llama-server's own default and
        the port Hermes probes; home.nix derives the judge URL from this option,
        so raising it is a change here alone.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Not the llama-cpp NixOS module: that one is built for a model the agent
    # chats with, and this is a 0.8B scorer. One unit, no router, no preset.
    systemd.services.kev-judge = {
      description = "Kev-0.8B effort judge (llama.cpp, CPU only)";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];

      serviceConfig = {
        ExecStart = lib.escapeShellArgs [
          "${pkgs.llama-cpp}/bin/llama-server"
          "--model"
          "${kev}"
          # No layers on the card, deliberately: the judge is one forward pass
          # through 0.8B, and a GPU batch would wake the card this desktop shares
          # with games for no measurable gain.
          "--n-gpu-layers"
          "0"
          "--ctx-size"
          "8192"
          "--host"
          "127.0.0.1"
          "--port"
          (toString cfg.port)
          # The id a client names; the effort judge asks for exactly this.
          "--alias"
          "Kev-0.8B-Q8_0"
          # One slot: the judge sees one request per turn, and a second context
          # would only cost memory.
          "--parallel"
          "1"
        ];
        DynamicUser = true;
        Restart = "always";
        RestartSec = 5;
      };
    };
  };
}
