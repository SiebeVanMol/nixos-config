{ pkgs, lib, ... }:
let
  
  llama-cpp-rocm = pkgs.llama-cpp.override { rocmSupport = true; };
  llama-server = lib.getExe' llama-cpp-rocm "llama-server";

  modelsDir = "/Vault/models";

  mkModel = { path, mmproj ? null, ctx ? 8192, extra ? "" }:
    "${llama-server} --port \${PORT} -m ${modelsDir}/${path} "
    + lib.optionalString (mmproj != null) "--mmproj ${modelsDir}/${mmproj} "
    + "-ngl 99 -c ${toString ctx} --flash-attn on --no-webui ${extra}";
in
{
  systemd.services.llama-swap.serviceConfig = {
    SupplementaryGroups = [ "render" "video" ];
  };

  services.llama-swap = {
    enable = true;
    openFirewall = true;
    settings = {
      healthCheckTimeout = 120;
      models = {
        "mellum-4b" = {
          cmd = mkModel {
            path = "JetBrains/Mellum-4b-base-gguf/mellum-4b-base.Q8_0.gguf";
            ctx = 8192;
          };
          ttl = 300;
        };

        "glm-4.6v-flash" = {
          cmd = mkModel {
            path = "lmstudio-community/GLM-4.6V-Flash-GGUF/GLM-4.6V-Flash-Q4_K_M.gguf";
            mmproj = "lmstudio-community/GLM-4.6V-Flash-GGUF/mmproj-GLM-4.6V-Flash-F16.gguf";
            ctx = 16384;
          };
          ttl = 300;
        };

        "qwen3.5-9b-q4" = {
          cmd = mkModel {
            path = "lmstudio-community/Qwen3.5-9B-GGUF/Qwen3.5-9B-Q4_K_M.gguf";
            mmproj = "lmstudio-community/Qwen3.5-9B-GGUF/mmproj-Qwen3.5-9B-BF16.gguf";
            ctx = 16384;
          };
          ttl = 300;
        };

        "qwen3.5-9b-q8" = {
          cmd = mkModel {
            path = "lmstudio-community/Qwen3.5-9B-GGUF/Qwen3.5-9B-Q8_0.gguf";
            mmproj = "lmstudio-community/Qwen3.5-9B-GGUF/mmproj-Qwen3.5-9B-BF16.gguf";
            ctx = 16384;
          };
          ttl = 300;
        };

        "qwen3.6-35b-a3b" = {
          cmd = mkModel {
            path = "lmstudio-community/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-Q8_0.gguf";
            mmproj = "lmstudio-community/Qwen3.6-35B-A3B-GGUF/mmproj-Qwen3.6-35B-A3B-BF16.gguf";
            ctx = 16384;
          };
          ttl = 300;
        };

        "gemma-4-12b" = {
          cmd = mkModel {
            path = "lmstudio-community/gemma-4-12B-it-QAT-GGUF/gemma-4-12B-it-QAT-Q4_0.gguf";
            mmproj = "lmstudio-community/gemma-4-12B-it-QAT-GGUF/mmproj-gemma-4-12B-it-QAT-BF16.gguf";
            ctx = 16384;
          };
          ttl = 300;
        };

        "gemma-4-26b-a4b" = {
          cmd = mkModel {
            path = "lmstudio-community/gemma-4-26B-A4B-it-QAT-GGUF/gemma-4-26B-A4B-it-QAT-Q4_0.gguf";
            mmproj = "lmstudio-community/gemma-4-26B-A4B-it-QAT-GGUF/mmproj-gemma-4-26B-A4B-it-QAT-BF16.gguf";
            ctx = 16384;
          };
          ttl = 300;
        };

        "gemma-4-31b" = {
          cmd = mkModel {
            path = "lmstudio-community/gemma-4-31B-it-GGUF/gemma-4-31B-it-Q8_0.gguf";
            mmproj = "lmstudio-community/gemma-4-31B-it-GGUF/mmproj-gemma-4-31B-it-BF16.gguf";
            ctx = 16384;
          };
          ttl = 300;
        };
      };
    };
  };
}
