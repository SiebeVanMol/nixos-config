{ pkgs, ... }: {
  services.tailscale = {
    enable = true;
    # test are broken so override them.
    # https://github.com/nixos/nixpkgs/issues/438765
    package = pkgs.tailscale.overrideAttrs { doCheck = false; };
  };
}
