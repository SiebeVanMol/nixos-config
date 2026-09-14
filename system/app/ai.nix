# AI stack: llama-cpp-rocm (ROCm/AMD) serving Gemma 4 REAP 19B
# Optimized for RX 9070 XT (16GB VRAM)
#
# Gemma 4 REAP 19B at Q4_K_M uses ~13GB VRAM
# Achieves ~128 tokens/sec on this hardware
# Expert-pruned architecture delivers 26B-quality at 19B size
{
  config,
  lib,
  pkgs,
  ...
}: let
  modelsDir = "/Vault/llama/models";
  modelFile = "gemma-4-19B-A4B-text-REAP-Q4_K_M.gguf";
  modelPath = "${modelsDir}/${modelFile}";

  # Download script for Gemma 4 REAP 19B
  hfCli = lib.getExe' pkgs.python3Packages.huggingface-hub "hf";
  llamaFetch = pkgs.writeScriptBin "llama-fetch" ''
    #!${lib.getExe pkgs.bash}
    set -euo pipefail
    ${pkgs.coreutils}/bin/mkdir -p "${modelsDir}"
    # Models live under /Vault, shared by every desktop user (all members of the
    # `users` group). Make the directory group-writable and setgid so any desktop
    # user can fetch models and new files keep the shared group, rather than
    # chown-ing it to a single user.
    ${pkgs.coreutils}/bin/chown root:users "${modelsDir}"
    ${pkgs.coreutils}/bin/chmod 2770 "${modelsDir}"

    echo "Downloading Gemma 4 REAP 19B Q4_K_M..."
    ${hfCli} download potto007/gemma-4-19B-A4B-text-REAP-GGUF \
      gemma-4-19B-A4B-text-REAP-Q4_K_M.gguf \
      --local-dir "${modelsDir}"

    echo "Model downloaded to ${modelsDir}"
  '';
in {
  config = lib.mkIf config.device.app.ai.enable {
    environment.systemPackages = [
      pkgs.llama-cpp-rocm
      llamaFetch
    ];

    services.llama-cpp = {
      enable = true;
      package = pkgs.llama-cpp-rocm;

      settings = {
        host = "0.0.0.0";
        port = 8080;
        model = modelPath;

        # Performance optimizations for REAP architecture
        "flash-attn" = "on";
        "cache-type-k" = "q4_0";
        "cache-type-v" = "q4_0";
        # "n-gpu-layers" = 999;        # Offload all layers to GPU
        "parallel" = 4; # Handle concurrent requests
        # "spec-type" = "draft-mtp";   # MTP for REAP models
        # "spec-draft-n-max" = 4;      # 4 tokens per draft step

        # Context management for REAP's efficient architecture
        # "ctx-size" = 32768;          # 32K context fits easily
        "ubatch-size" = 256;
        "batch-size" = 512;

        # Performance tuning for RX 9070 XT
        "threads" = 16; # Adjust to your CPU cores
        "threads-batch" = 8;

        # Keep server ready
        "sleep-idle-seconds" = 300;
      };
    };

    services.caddy.virtualHosts = lib.mkIf config.device.security.reverse-proxy.enable {
      "http://ai.lan" = {
        extraConfig = "reverse_proxy 127.0.0.1:8080";
      };
    };
  };
}
