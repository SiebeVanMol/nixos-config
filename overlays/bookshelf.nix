# overlays/bookshelf.nix
#
# Bookshelf (https://github.com/pennydreadful/bookshelf): the maintained revival
# of Readarr. Upstream Readarr/Readarr was retired and ARCHIVED by the Servarr
# team (last commit June 2025), and its metadata pipeline is dead: it resolves
# book metadata through api.bookinfo.club, a Goodreads proxy that no longer
# answers, which is why the stack carries Shelfmark as a second ebook path.
# Bookshelf is the same codebase kept alive, and it is the reason this overlay
# exists:
#
#   * MetadataSource falls back to the METADATA_URL environment variable and
#     then to https://api.bookinfo.pro, a service the fork's maintainer runs, so
#     metadata works out of the box. Setting METADATA_URL to
#     https://hardcover.bookinfo.pro switches the whole instance to Hardcover.
#   * BuildInfo.AppName is still "Readarr", so SeerrNG's readarr client (which
#     only special-cases an appName of "chaptarr") keeps talking to it over the
#     unchanged /api/v1 surface.
#   * It removed the Servarr analytics beacons and no longer caches metadata
#     locally.
#
# It is not in nixpkgs, so it is built here, from source. Two things make this
# derivation less trivial than the other overlays in this directory:
#
#   1. Bookshelf is still a .NET 6 application (its own CI pins SDK 6.0.427 and
#      the projects target net6.0). .NET 6 is out of support, so nixpkgs marks
#      the SDK and the ASP.NET runtime as insecure. The consuming configuration
#      MUST list them in `nixpkgs.config.permittedInsecurePackages` (see
#      system/app/jellyfin.nix); without that, evaluation aborts. Building with
#      a newer SDK is not an option while global.json pins 6.x.
#   2. Its frontend is a yarn/webpack project that is built and copied next to
#      the managed assemblies, alongside a NuGet dependency graph that has to be
#      materialised offline.
#
# `deps.json` and the small NuGet.config patch are vendored next to this file
# instead of being regenerated on every build; they are a coherent triple with
# `rev`/`hash` below and must be updated together. To move to a newer commit:
#
#   1. pick the commit from the fork's `develop` branch,
#   2. set `rev` here and put lib.fakeHash in `hash` / the yarn hash, then take
#      the correct hashes from the two build errors,
#   3. regenerate the NuGet graph with
#        nix build --impure --expr \
#          '(builtins.getFlake (toString ./.)).packages.x86_64-linux.bookshelf.fetch-deps' \
#          --print-out-paths
#      and run the resulting script with the path of deps.json.
final: prev: {
  bookshelf = prev.buildDotnetModule (finalAttrs: {
    pname = "bookshelf";
    # Bookshelf publishes no versioned releases (its CI only builds container
    # images), so the package is pinned to a commit and versioned the way
    # nixpkgs versions commit-pinned packages.
    version = "0-unstable-2026-02-04";

    src = prev.fetchFromGitHub {
      owner = "pennydreadful";
      repo = "bookshelf";
      rev = "c21c4134fdb710481ed69db05bf943b0acdbbf60";
      hash = "sha256-dHQLZVFKvOz7BD6C7qxmlns0eDgLD/+K6CLMWF1f+cQ=";
    };

    strictDeps = true;

    nativeBuildInputs = [
      prev.nodejs
      prev.yarn
      prev.prefetch-yarn-deps
      prev.fixup-yarn-lock
    ];

    # The frontend's dependency tree, resolved offline from the lockfile.
    yarnOfflineCache = prev.fetchYarnDeps {
      yarnLock = "${finalAttrs.src}/yarn.lock";
      hash = "sha256-lmtvDXf745fQN67MtZ5muIFyT3e41XYQELHHStgLauQ=";
    };

    # nixpkgs' .NET infrastructure only looks for NuGet.config in the source
    # root; Bookshelf keeps it in src/.
    patches = [./bookshelf-nuget-config.patch];

    postConfigure = ''
      yarn config --offline set yarn-offline-mirror "$yarnOfflineCache"
      fixup-yarn-lock yarn.lock
      yarn install --offline --frozen-lockfile --ignore-platform --ignore-scripts --no-progress --non-interactive
      patchShebangs --build node_modules
    '';

    postBuild = ''
      yarn --offline run build --env production
    '';

    postInstall = ''
      cp -a -- _output/UI "$out/lib/bookshelf/UI"
    '';

    nugetDeps = ./bookshelf-deps.json;

    runtimeDeps = [prev.sqlite];

    dotnet-sdk = prev.dotnetCorePackages.sdk_6_0;
    dotnet-runtime = prev.dotnetCorePackages.aspnetcore_6_0;

    # The binary keeps the Readarr name on purpose: services.readarr runs
    # "$out/bin/Readarr", and renaming it would mean hand-writing a unit.
    executables = ["Readarr"];

    projectFile = [
      "src/NzbDrone.Console/Readarr.Console.csproj"
      "src/NzbDrone.Mono/Readarr.Mono.csproj"
    ];

    dotnetFlags = [
      "--property:TargetFramework=net6.0"
      "--property:EnableAnalyzers=false"
      "--property:AssemblyVersion=10.0.0.0"
      "--property:AssemblyConfiguration=main"
      "--property:RuntimeIdentifier=${prev.dotnetCorePackages.systemToDotnetRid prev.stdenvNoCC.hostPlatform.system}"
    ];

    __structuredAttrs = true;

    meta = {
      description = "Book manager and automation (maintained Readarr revival)";
      homepage = "https://github.com/pennydreadful/bookshelf";
      license = prev.lib.licenses.gpl3Only;
      mainProgram = "Readarr";
      platforms = prev.lib.platforms.linux;
    };
  });
}
