{ pkgs, ... }:
{
  services.udev.extraRules = ''
  SUBSYSTEM=="powercap", ACTION=="add", RUN+="${pkgs.coreutils}/bin/chmod -R a+r /sys%p"
'';
}
