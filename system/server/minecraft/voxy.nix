# The voxyworldgenv2 fork that does server-side chunk generation for voxy.
#
# voxyworldgenv2 generates vanilla chunks around players and streams their voxel
# data to voxyworldgenv2 clients over its own channel; voxy itself runs only on
# the client and never generates when connected to a dedicated server. The jar is
# vendored (vendor/voxyworldgenv2-2.2.4.jar); its source is the local fork
# ~/Downloads/voxy_worldgen_v2. To update: rebuild the fork, copy the jar in, bump
# the hash.
{pkgs}: let
  sha256 = "sha256-81cf0813abc1caad48f33d2890bd079551c0bb83fd689f34c2d573698c467626";
in
  pkgs.runCommand "voxyworldgenv2" {inherit sha256;} ''
    mkdir -p $out
    cp ${./vendor/voxyworldgenv2-2.2.4.jar} $out/VoxyWorldGenV2-2.2.4.jar
  ''
