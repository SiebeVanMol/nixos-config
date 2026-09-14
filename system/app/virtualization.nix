# QEMU/KVM virtualization with virt-manager GUI for running VMs (e.g. custom prototype kernels).
{
  config,
  lib,
  pkgs,
  usernames,
  ...
}: {
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

    # Allow users to manage VMs without root.
    users.users = lib.genAttrs usernames (_: {extraGroups = ["libvirtd"];});
  };
}
