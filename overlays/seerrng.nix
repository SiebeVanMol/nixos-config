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
  # Upstream's package.json asks for `engines.node: ^24.15.0` from 3.67.0 on, and
  # pnpm refuses to run on anything older - which is what stopped this pin
  # moving for forty-eight releases.
  #
  # nixpkgs' `seerr` recipe takes its node and pnpm as callPackage arguments,
  # named after the versions it pins (`nodejs-slim_22`, `pnpm_10`), so the bump
  # goes through `.override`. A `let` binding here would only change what this
  # file computes: the first attempt did exactly that, and the build still ran
  # node 22.23.3 and failed on the same engine check.
  nodejs-slim = prev.nodejs-slim_24;
  pnpm = prev.pnpm_10.override {inherit nodejs-slim;};
in {
  seerrng =
    (prev.seerr.override {
      nodejs-slim_22 = nodejs-slim;
      pnpm_10 = pnpm;
    }).overrideAttrs (finalAttrs: _old: {
      pname = "seerrng";
      version = "3.67.0";

      # `fetchgit`, not `fetchFromGitHub`: GitHub's source tarball for 3.67.0 does
      # not contain `docs/` at all, and the package's `prebuild` hook runs
      # `current-batch:check`, which reads
      # `docs/maintainers/current-batch-acceptance-ledger.md`. A tarball checkout
      # fails the build on a missing file that exists in the repository; a clone
      # has it. The repo also moved to snapetech-org, hence the URL.
      src = prev.fetchgit {
        url = "https://github.com/snapetech-org/seerrng";
        rev = "v${finalAttrs.version}";
        hash = "sha256-jvhykP5lzoCMj9TGRI2b5+cHdKGBr7ja6WOCUU5GsQk=";
      };

      # A fork pins its own dependency set: same pnpm major, different lockfile.
      pnpmDeps = prev.fetchPnpmDeps {
        inherit (finalAttrs) pname version src;
        inherit pnpm;
        fetcherVersion = 3;
        hash = "sha256-tV2r9gAKruO+Y9aDvr+/AncuJ4N9JNNz2X2nZ0keMSw=";
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
