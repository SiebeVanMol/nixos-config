# Builds the voxyworldgenv2 fork that does the server-side chunk generation for voxy.
#
# Server-side worldgen architecture (no VoxyServer, no voxy-on-server, no Chunky):
#   - voxyworldgenv2 generates vanilla chunks around players on the server and streams
#     their voxel data to voxyworldgenv2 clients over its own network channel.
#   - voxy itself only runs on the client (renderer + ingest target); the client never
#     generates when connected to a dedicated server.
#
# The fork is a 1.21.1 backport of iSeeEthan/voxy_worldgen_v2 with dedicated-server
# fixes: dedicated-server-safe voxy client config handling (the client config's static
# init can NoClassDefFoundError on LWJGL/sodium classes absent on a server) and keeping
# prematurely-loaded empty chunks loaded until they populate instead of saving void.
#
# To update: bump the rev + fetchgit sha256, set outputHash to a dummy value, run
# `nix build`, and copy the reported "got" hash back here.
{ pkgs }:

let
  voxyworldgenv2Src = pkgs.fetchgit {
    url = "file:///home/snowyrenard/Downloads/voxy_worldgen_v2";
    rev = "d11e1b5da8e674e9553041d4f7706c6f823460f5";
    sha256 = "sha256-kJvkyr5oOlJaDNyCmHdaOOXSM5iOYNQiWo3JcbqQkb4=";
  };
in
pkgs.stdenvNoCC.mkDerivation {
  name = "voxyworldgenv2";

  inherit voxyworldgenv2Src;

  # source is copied by name in buildPhase; there is no $src to unpack
  dontUnpack = true;

  nativeBuildInputs = [ pkgs.jdk21_headless pkgs.git ];

  # Fixed-output derivation: the gradle build needs network access to fetch the Loom
  # toolchain and maven dependencies.
  outputHashMode = "recursive";
  outputHash = "sha256-4FhfwGuKvQ/+qo1kyHe60nInuZVLm3Nt99VyhzkauDc=";

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    export GRADLE_USER_HOME=$TMPDIR/.gradle
    export JAVA_HOME=${pkgs.jdk21_headless}
    mkdir -p $TMPDIR/work
    cp -r $voxyworldgenv2Src $TMPDIR/work/voxy_worldgen_v2
    chmod -R u+w $TMPDIR/work
    cd $TMPDIR/work/voxy_worldgen_v2

    # determinism: reproducible archive timestamps so the fixed output hash stays stable
    cat >> build.gradle <<'G'
    tasks.withType(AbstractArchiveTask).configureEach {
      preserveFileTimestamps = false
      reproducibleFileOrder = true
    }
    G

    chmod +x gradlew
    sh gradlew --no-daemon -Dorg.gradle.vfs.watch=false build
    wgjar=$(realpath "$(find build/libs -maxdepth 1 -name '*.jar' ! -name '*sources*' | head -1)")
    echo "voxyworldgenv2 jar: $wgjar"

    mkdir -p $out
    cp "$wgjar" $out/VoxyWorldGenV2-2.2.4.jar
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    runHook postInstall
  '';
}
