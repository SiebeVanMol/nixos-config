{ ... }: {
  imports = [
    ./amd.nix
    ./backlight.nix
    ./bluetooth.nix
    ./dualsense.nix
    ./kernel.nix
    ./lvm.nix
    ./mesa.nix
    ./nvidia.nix
    ./printing.nix
    ./time.nix
    ./tpm.nix
    ./zsa.nix
  ];
}
