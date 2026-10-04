# Custom NixOS option declarations that act as feature toggles.
# Hosts enable subsets via device.hardware.<name>.enable and device.security.<name>.enable.
{
  lib,
  usernames,
  ...
}: {
  options.device.hardware = {
    amd = {
      enable = lib.mkEnableOption "AMD GPU powercap udev rules";
    };
    backlight = {
      enable = lib.mkEnableOption "backlight control (Brillo + DDC/CI)";
    };
    bluetooth = {
      enable = lib.mkEnableOption "Bluetooth (managed by the Caelestia shell)";
    };
    dualsense = {
      enable = lib.mkEnableOption "DualSense controller touchpad ignore";
    };
    kernel = {
      enable = lib.mkEnableOption "latest kernel, uinput, swappiness";
    };
    lvm = {
      enable = lib.mkEnableOption "LVM cache support";
    };
    mesa = {
      enable = lib.mkEnableOption "Mesa graphics (enable + 32-bit)";
    };
    nvidia = {
      enable = lib.mkEnableOption "NVIDIA driver + VA-API";
    };
    time = {
      enable = lib.mkEnableOption "timesyncd";
    };
    usb-automount = {
      enable = lib.mkEnableOption "system-wide USB automount via udev + systemd-mount (no desktop session)";
    };
    zsa = {
      enable = lib.mkEnableOption "ZSA keyboard + keymapp";
    };
  };

  options.device.app = {
    steam = {
      enable = lib.mkEnableOption "Steam with Remote Play, Proton GE";
    };
    gamemode = {
      enable = lib.mkEnableOption "Feral Gamemode";
    };
    kanata = {
      enable = lib.mkEnableOption "Kanata keyboard remapper";
    };
    jellyfin = {
      enable = lib.mkEnableOption "Jellyfin media server";
    };
    music = {
      enable = lib.mkEnableOption "Navidrome music server with slskd (Soulseek) acquisition";
    };
    hipfire = {
      enable = lib.mkEnableOption "hipfire (ROCm) inference daemon as a per-user service";
      user = lib.mkOption {
        type = lib.types.str;
        default = lib.head usernames;
        description = "User whose session runs the hipfire daemon and owns its models.";
      };
      gpuTargets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["gfx1201"];
        description = ''
          AMD GPU architectures to compile hipfire kernels for. Must be
          non-empty when enabled; detect with:
            grep gfx_target_version /sys/class/kfd/kfd/topology/nodes/*/properties
        '';
      };
      defaultModel = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "qwen3.8:27b";
        description = ''
          Default registry tag the daemon routes requests to. The model is
          never pre-warmed at startup: it is loaded on the first request and
          evicted again after idleTimeout. Empty = no default, the request
          must name a tag.
        '';
      };
      maxSeq = lib.mkOption {
        type = lib.types.int;
        default = 32768;
        example = 131072;
        description = "KV cache capacity in tokens, i.e. the context length.";
      };
      idleTimeout = lib.mkOption {
        type = lib.types.int;
        default = 300;
        example = 60;
        description = ''
          Seconds of inactivity before the loaded model is evicted from VRAM.
          The model is always loaded on first request (never pre-warmed); this
          only controls how long it stays resident afterwards. 0 = never unload.
        '';
      };
      kvCache = lib.mkOption {
        type = lib.types.str;
        default = "auto";
        example = "q8";
        description = ''
          KV cache quantization preset: auto / q8 / fp8 / bf16 / fwht4 / fwht3 /
          fwht2 (legacy spellings asym4 / asym3 / asym2 / turbo* also accepted).
        '';
      };
      gpuLayerBudget = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        example = 30;
        description = ''
          Partial GPU offload. N keeps the last N layers on the GPU and spills
          the prefix to pinned host RAM, so a model whose weights exceed VRAM
          can still load; null keeps every layer resident. The KV cache always
          stays in VRAM either way, so this buys weights, not context.

          Upstream refuses this for MoE models (only the attention/DeltaNet
          weights would spill while the expert stacks stay in VRAM) and for
          tp/pp > 1, so it is single-GPU dense Qwen3.5/3.6/3.8 only. Spilled
          layers are read over PCIe and are far slower than resident ones.
        '';
      };
      offloadExec = lib.mkOption {
        type = lib.types.enum ["pcie" "cpu"];
        default = "pcie";
        description = ''
          Who multiplies a spilled layer's weights: `pcie` runs the GPU kernels
          against host-mapped weights over PCIe, `cpu` runs those GEMVs on the
          CPU instead. Only meaningful when gpuLayerBudget is set.
        '';
      };
      perModelSettings = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = {};
        example = lib.literalExpression ''
          {
            "qwen3.5:9b" = {
              "memory.gpu_layer_budget" = 1024;
            };
          }
        '';
        description = ''
          Per-model overrides written to models.toml, keyed by registry tag.
          Values take canonical dotted keys (memory.max_seq,
          memory.gpu_layer_budget, ...) or the legacy snake_case aliases, and
          win over the global settings above.

          Needed because the global placement keys apply to every model a
          request can name. A model with fewer layers than gpuLayerBudget keeps
          its whole tail resident anyway, but the budget still makes the loader
          consider spilling, so pin such a model explicitly (any N at least its
          layer count saturates to fully resident).
        '';
      };
      mtpMode = lib.mkOption {
        type = lib.types.enum ["auto" "on" "off"];
        default = "auto";
        description = ''
          MTP (multi-token-prediction head) speculative decode. `auto` uses the
          model's registry-declared MTP sidecar when it is present and silently
          runs plain autoregressive when it is not; `on` refuses to load without
          the head; `off` never loads it.
        '';
      };
      dflashMode = lib.mkOption {
        type = lib.types.enum ["auto" "on" "off"];
        default = "off";
        description = ''
          DFlash (draft-model) speculative decode. `auto` uses a registry
          draft sidecar when one is present and falls back to autoregressive
          when it is not; `on` refuses to load without the draft; `off` never
          loads it.

          DFlash and MTP are not combined: the loader's drafter registry is a
          first-match cascade (DFlash > MTP > n-gram), so enabling both selects
          DFlash and leaves the MTP head unused.
        '';
      };
    };
    ai = {
      enable = lib.mkEnableOption "llama.cpp (ROCm) server with Gemma 4 REAP 19B";
    };
    minecraft = {
      enable = lib.mkEnableOption "Minecraft server";
    };
    virtualization = {
      enable = lib.mkEnableOption "QEMU/KVM + virt-manager";
    };
  };

  options.device.wm = {
    hyprland = {
      enable = lib.mkEnableOption "Hyprland compositor";
    };
  };

  options.device.security = {
    firewall = {
      enable = lib.mkEnableOption "Firewall";
    };
    tailscale = {
      enable = lib.mkEnableOption "Tailscale VPN";
    };
    proton-vpn = {
      enable = lib.mkEnableOption "ProtonVPN CLI tools";
    };
    reverse-proxy = {
      enable = lib.mkEnableOption "Caddy reverse proxy for LAN services";
      publicDomain = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Public domain served by the reverse proxy (e.g. snowyrenard.com). Empty = LAN-only.";
      };
    };
    ssh = {
      enable = lib.mkEnableOption "OpenSSH server";
    };
  };
}
