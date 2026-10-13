# overlays/dsh-model-router.nix
#
# @neptune810/dsh-model-router (https://github.com/Neptune810/dsh-model-router):
# a DeepSeek Harness plugin that keeps a pool of models and routes every agent
# step to one, setting its reasoning effort (trivial/standard -> low,
# engineering/hard -> high, `max` opt-in). On the default single-model pool it
# leaves the model alone and only drives the thinking level.
#
# Packaged as a dsh *bundle* rather than installed with `dsh plugin add`, because
# the nix-web profile is materialized in `managed` mode and activation restores
# package.json, pnpm-workspace.yaml and cordis.patch.yml, so a runtime install
# would be reverted. The published tarball already contains built JavaScript and
# declares no dependencies, so nothing is fetched or built with npm; the bundle
# resolver just needs it installed under its real npm name with its package.json
# and cordis.patch.yml intact, and `linkKernelNodeModules` lets its client half
# resolve the @deepseek-ai/* peers it injects.
_final: prev: {
  dsh-model-router = prev.dsh.buildDshBundle (finalAttrs: {
    pname = "dsh-model-router";
    version = "0.14.2";

    src = prev.fetchurl {
      url = "https://registry.npmjs.org/@neptune810/dsh-model-router/-/dsh-model-router-${finalAttrs.version}.tgz";
      hash = "sha512-vbARWUzpTuYUaBunnbX/vtoeMyNRod7nD/s98IiME/eg1HQwwvwsjODJQoJv3XaOinsp2qwB/IerpYTNfqLtZg==";
    };

    npmDeps = null;
    dontPatch = true;
    dontConfigure = true;
    dontBuild = true;

    linkKernelNodeModules = prev.dsh.dsh-kernel;

    installPhase = ''
      runHook preInstall
      appDir="$out/lib/node_modules/@neptune810/dsh-model-router"
      mkdir -p "$appDir"
      cp -r . "$appDir/"
      runHook postInstall
    '';

    passthru.requiresWeb = true;

    meta = {
      description = "DeepSeek Harness model router: keeps a pool of models and routes every step to one of them with its reasoning effort set";
      homepage = "https://github.com/Neptune810/dsh-model-router";
      license = prev.lib.licenses.mit;
      platforms = prev.lib.platforms.unix;
    };
  });
}
