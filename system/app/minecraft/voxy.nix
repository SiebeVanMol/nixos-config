# The voxyworldgenv2 fork that does the server-side chunk generation for voxy.
#
# Server-side worldgen architecture (no VoxyServer, no voxy-on-server, no Chunky):
#   - voxyworldgenv2 generates vanilla chunks around players on the server and streams
#     their voxel data to voxyworldgenv2 clients over its own network channel.
#   - voxy itself only runs on the client (renderer + ingest target); the client never
#     generates when connected to a dedicated server.
#
# The jar is vendored here (vendor/voxyworldgenv2-2.2.4.jar); its source lives in the
# local fork ~/Downloads/voxy_worldgen_v2 (1.21.1 backport of iSeeEthan/voxy_worldgen_v2
# with dedicated-server fixes). To update: rebuild the fork, copy the new jar in here,
# and bump the hash.
{ pkgs }:

let
  sha256 = "sha256-81cf0813abc1caad48f33d2890bd079551c0bb83fd689f34c2d573698c467626";
in
pkgs.runCommand "voxyworldgenv2" { inherit sha256; } ''
  mkdir -p $out
  cp ${./vendor/voxyworldgenv2-2.2.4.jar} $out/VoxyWorldGenV2-2.2.4.jar
''
