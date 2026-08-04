# QEMU/KVM virtualization with virt-manager GUI for running VMs (e.g. custom prototype kernels).
{ config, lib, pkgs, username, ... }: {
  config = lib.mkIf config.device.app.virtualization.enable {
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
      };
    };

    programs.virt-manager.enable = true;

    # Allow the primary user to manage VMs without root.
    users.users.${username}.extraGroups = ["libvirtd"];
  };
}
