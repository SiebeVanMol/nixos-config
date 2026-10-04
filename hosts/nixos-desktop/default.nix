# Desktop machine configuration. Full workstation: Jellyfin media server, Minecraft server.
{...}: {
  imports = [
    ../../system/default.nix
    ./hardware-configuration.nix
  ];

  device = {
    hardware = {
      amd.enable = true;
      backlight.enable = true;
      bluetooth.enable = true;
      kernel.enable = true;
      lvm.enable = true;
      mesa.enable = true;
      time.enable = true;
      zsa.enable = true;
      dualsense.enable = true;
      usb-automount.enable = true;
    };
    security = {
      firewall.enable = true;
      tailscale.enable = true;
      proton-vpn.enable = true;
      reverse-proxy = {
        enable = true;
        publicDomain = "snowyrenard.com";
      };
      ssh.enable = true;
    };
    app = {
      steam.enable = true;
      gamemode.enable = true;
      jellyfin.enable = true;
      music.enable = true;
      # ai.enable = true;
      # hipfire runs as a per-user service in snowyrenard's session (see
      # system/app/hipfire.nix). gfx1201 is the RX 9070 XT (Navi 48).
      #
      # Requested shape: Q4V2 weights, q8 KV, 128k context. That does not fit
      # resident on this card, so part of the trunk is spilled to host RAM.
      #
      # The arithmetic. Qwen3.8-27B is a 64-layer hybrid: 16 full-attention
      # layers (4 KV heads, head_dim 256) carry a cache and the other 48 are
      # DeltaNet, so q8 costs 34816 B/token and 128k needs 4.36 GiB of KV. The
      # MQ4V2 trunk is 15.66 GB and the desktop's compositor holds ~1.5 GiB, on
      # a 15.92 GiB card. hipfire's own budget line is the proof it does not
      # fit: free_after_weights=846 MiB against min_prefill=1393 MiB, before a
      # single KV token. Weights + KV + scratch + desktop is ~22 GiB.
      #
      # So gpuLayerBudget spills the prefix of the trunk: with 30 of 64 layers
      # resident, the resident tail (~6.5 GiB), the always-resident
      # token_embd/lm_head (~1.3 GiB), the 4.36 GiB KV (which stays in VRAM) and
      # the 1.39 GiB prefill scratch land at ~13.8 GiB, leaving ~1 GiB of
      # headroom. The 34 spilled layers (~7 GiB) are pinned host RAM; the box has
      # 42 GiB free. Watch the load log's "partial offload: N resident / M
      # offloaded" line and the max_seq budget line, and lower gpuLayerBudget if
      # the load still overcommits.
      #
      # The cost is speed: spilled layers are read over PCIe (27 GB/s measured,
      # against 500+ GB/s of HBM) and graph capture is dropped while anything is
      # spilled. Upstream's own words are "expect ~10-50x slower decode on
      # offloaded layers" and "this is a 'can run' capability". This is the only
      # way to have Q4 + q8 + 128k at once here; the alternative is a smaller
      # quant or a shorter context.
      #
      # Note this cannot be used with the 35B-A3B MoE at all: upstream refuses
      # partial offload when num_experts > 0, because only the attention and
      # DeltaNet weights would spill while the expert stacks stay in VRAM.
      hipfire = {
        enable = true;
        gpuTargets = ["gfx1201"];
        # MQ4V2 base, already in ~/.hipfire/models, so nothing to pull.
        defaultModel = "qwen3.8:27b";
        maxSeq = 131072;
        kvCache = "q8";
        gpuLayerBudget = 30;
        offloadExec = "pcie";
        # Still loaded on first request, never at login, but held for half an
        # hour: an interactive agent session leaves gaps longer than a minute
        # between turns, and every reload would pay the full PCIe-bound prefill
        # again. It is evicted once the session goes idle for good.
        idleTimeout = 1800;
        # The DFlash draft (1.21 GB) and MTP head would both have to be
        # resident and would eat the ~1 GiB of headroom this placement has.
        dflashMode = "off";
        mtpMode = "auto";
        # gpuLayerBudget above is global and applies to every tag a request can
        # name, so each resident model pins its own placement. Any N >= the
        # model's layer count saturates to fully resident.
        #
        # KV cost comes from the architecture: full_attention_interval 4 over 64
        # layers = 16 KV-carrying layers at 4 KV heads x head_dim 256, which
        # hipfire measured at 34816 B/token for q8 (half that, 17408 B/token,
        # for the 32-layer 9b/4b). Budgets below assume the compositor holds
        # ~1.5 GiB and leave ~1 GiB of margin.
        perModelSettings = {
          # 5.31 GB trunk + 0.55 GB DFlash draft + 128k KV (~2.2 GiB) is ~9 GiB
          # against ~10.7 GiB free, so 128k stays and the draft is affordable.
          "qwen3.5:9b" = {
            "memory.gpu_layer_budget" = 1024;
            "speculation.dflash" = "auto";
          };
          # 2.59 GB, no published draft; 128k of KV is ~2.2 GiB.
          "qwen3.5:4b" = {
            "memory.gpu_layer_budget" = 1024;
          };
          # Dense 27B MQ3: the 10.7 GB trunk fits resident, but 128k of KV
          # (4.4 GiB) does not - trunk + 0.67 GB draft + KV + prefill exceeds
          # the card. 64k costs ~2.2 GiB and leaves ~1.2 GiB of margin. The
          # draft is pulled alongside the trunk and gives ~126 tok/s on code.
          "qwen3.6:27b-mq3" = {
            "memory.gpu_layer_budget" = 1024;
            "memory.max_seq" = 65536;
            "speculation.dflash" = "auto";
          };
        };
      };
      minecraft.enable = true;
      virtualization.enable = true;
    };
    wm.hyprland.enable = true;
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  networking.networkmanager.enable = true;
  networking.hostName = "nixos-desktop";

  powerManagement.cpuFreqGovernor = "performance";

  time.timeZone = "Europe/Brussels";

  system.stateVersion = "25.05";
}
