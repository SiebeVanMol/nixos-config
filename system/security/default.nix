{ ... }: {
  imports = [
    ./automount.nix
    ./firewall.nix
    ./proton-vpn.nix
    ./ssh.nix
    ./tailscale.nix
  ];
}
