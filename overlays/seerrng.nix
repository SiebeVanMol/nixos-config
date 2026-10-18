# overlays/seerrng.nix
#
# SeerrNG (https://github.com/snapetech/seerrng), a fork of Seerr extending the
# request/approval workflow to music, ebooks and audiobooks. Not in nixpkgs.
#
# This is nixpkgs' `seerr` derivation with the fork's source, not a copy of it.
# SeerrNG inherits upstream's stack - a pnpm-managed Next.js app with two native
# modules (bcrypt, sqlite3) rebuilt against the pinned Node - so a copy would
# stop tracking the recipe it was taken from, which is exactly what had happened:
# buildInputs, the rebuild step, `pnpm build`, the prune and the broken-symlink
# cleanup were all verbatim, and would have stayed verbatim after any upstream
# change. The one part that cannot be inherited is the wrapper, because
# `postInstall` writes `$out/bin/seerr`, so it is restated here with the fork's
# name.
#
# `passthru` is not inherited: upstream's `nixosTests.seerr` would run against a
# package it does not describe, and its `updateScript` would bump upstream's
# repo. Neither has a meaning for a fork, so both go.
_final: prev: let
  nodejs-slim = prev.nodejs-slim_22;
  pnpm = prev.pnpm_10.override {inherit nodejs-slim;};
in {
  seerrng = prev.seerr.overrideAttrs (finalAttrs: _old: {
    pname = "seerrng";
    version = "3.19.3";

    src = prev.fetchFromGitHub {
      owner = "snapetech";
      repo = "seerrng";
      tag = "v${finalAttrs.version}";
      hash = "sha256-veGXitixf6P1djgtyreitkptR8I25HS6t1lctXcn0TY=";
    };

    # A fork pins its own dependency set: same pnpm major, different lockfile.
    pnpmDeps = prev.fetchPnpmDeps {
      inherit (finalAttrs) pname version src;
      inherit pnpm;
      fetcherVersion = 3;
      hash = "sha256-uUClXen1HLuVQGMDXcgqKOecDqSLVvFcP2by1w8ODFg=";
    };

    postInstall = ''
      mkdir -p $out/bin
      makeWrapper '${nodejs-slim}/bin/node' "$out/bin/seerrng" \
        --add-flags "$out/share/dist/index.js" \
        --chdir "$out/share" \
        --set NODE_ENV production
    '';

    passthru = {};

    meta = {
      description = "Request and discovery manager for Jellyfin, Plex and Emby, with music and book support";
      homepage = "https://github.com/snapetech/seerrng";
      license = prev.lib.licenses.mit;
      platforms = prev.lib.platforms.linux;
      mainProgram = "seerrng";
    };
  });
}
