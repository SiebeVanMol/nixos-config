# overlays/seerrng.nix
#
# SeerrNG (https://github.com/snapetech/seerrng): a fork of Seerr that extends the
# familiar request/approval workflow beyond movies and TV to music, ebooks and
# audiobooks. It is not packaged in nixpkgs, so it is built here.
#
# The build mirrors nixpkgs' own `seerr` derivation, because SeerrNG inherits its
# stack from upstream Seerr ("upstream Seerr remains the base project"): a
# pnpm-managed Next.js app with two native modules (bcrypt, sqlite3) that have to
# be rebuilt against the pinned Node rather than used as prebuilt artifacts.
final: prev: let
  nodejs-slim = prev.nodejs-slim_22;
  pnpm = prev.pnpm_10.override {inherit nodejs-slim;};
in {
  seerrng = prev.stdenv.mkDerivation (finalAttrs: {
    pname = "seerrng";
    version = "3.19.3";

    src = prev.fetchFromGitHub {
      owner = "snapetech";
      repo = "seerrng";
      tag = "v${finalAttrs.version}";
      hash = "sha256-veGXitixf6P1djgtyreitkptR8I25HS6t1lctXcn0TY=";
    };

    pnpmDeps = prev.fetchPnpmDeps {
      inherit (finalAttrs) pname version src;
      inherit pnpm;
      fetcherVersion = 3;
      hash = "sha256-uUClXen1HLuVQGMDXcgqKOecDqSLVvFcP2by1w8ODFg=";
    };

    buildInputs = [prev.sqlite];

    nativeBuildInputs = [
      prev.python3
      prev.python3Packages.distutils
      nodejs-slim
      prev.makeWrapper
      prev.pnpmConfigHook
      pnpm
    ];

    preBuild = ''
      export npm_config_nodedir=${nodejs-slim}
      pushd node_modules
      pnpm rebuild bcrypt sqlite3
      popd
    '';

    buildPhase = ''
      runHook preBuild

      pnpm build
      CI=true pnpm prune --prod --ignore-scripts
      rm -rf .next/cache

      # Clean up broken symlinks left behind by `pnpm prune`
      # https://github.com/pnpm/pnpm/issues/3645
      find node_modules -xtype l -delete

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share
      cp -r -t $out/share .next node_modules dist public package.json seerr-api.yml

      runHook postInstall
    '';

    postInstall = ''
      mkdir -p $out/bin
      makeWrapper '${nodejs-slim}/bin/node' "$out/bin/seerrng" \
        --add-flags "$out/share/dist/index.js" \
        --chdir "$out/share" \
        --set NODE_ENV production
    '';

    meta = {
      description = "Request and discovery manager for Jellyfin, Plex and Emby, with music and book support";
      homepage = "https://github.com/snapetech/seerrng";
      license = prev.lib.licenses.mit;
      platforms = prev.lib.platforms.linux;
      mainProgram = "seerrng";
    };
  });
}
