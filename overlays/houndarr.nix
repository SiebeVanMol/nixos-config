# overlays/houndarr.nix
#
# Houndarr (https://github.com/av1155/houndarr): a search scheduler for the *arr
# applications. It asks Radarr/Sonarr/Lidarr to search their wanted lists in
# small, rate-limited batches, which is what makes "go and find an HEVC/AV1 copy
# of what you already have" safe to point at public indexers - the applications
# do the searching and evaluating, Houndarr only decides when and how many.
#
# It is not in nixpkgs. The application is Python (FastAPI), but its stylesheet
# is a Tailwind v4 build, so the CSS is compiled in its own pnpm derivation and
# copied into the Python source before packaging. That keeps Node and pnpm
# entirely out of the Python build.
_final: prev: let
  # aiosqlite 0.22.1 and aiosqlitepool are newer than, or absent from, nixpkgs.
  aiosqlite = prev.python3Packages.buildPythonPackage rec {
    pname = "aiosqlite";
    version = "0.22.1";
    format = "wheel";

    src = prev.fetchurl {
      url = "https://files.pythonhosted.org/packages/00/b7/e3bf5133d697a08128598c8d0abc5e16377b51465a33756de24fa7dee953/aiosqlite-0.22.1-py3-none-any.whl";
      hash = "sha256-IcAC6xOCP610AZbFounY5i9iQ72efkofh/teROy0/Os=";
    };

    doCheck = false;

    meta = {
      description = "Asyncio bridge to the standard sqlite3 module";
      homepage = "https://github.com/omnilib/aiosqlite";
      license = prev.lib.licenses.mit;
    };
  };

  aiosqlitepool = prev.python3Packages.buildPythonPackage rec {
    pname = "aiosqlitepool";
    version = "1.0.0";
    format = "wheel";

    src = prev.fetchurl {
      url = "https://files.pythonhosted.org/packages/e0/65/4d9a7eb8a4cf6a586f14abcce9d774d5b4a986e3c3028a9c88801c9648d2/aiosqlitepool-1.0.0-py3-none-any.whl";
      hash = "sha256-gyrLFmu5r+9/RrMg0CSzQwg8kPTrS9yMDXlKeeH9G00=";
    };

    propagatedBuildInputs = [aiosqlite];
    doCheck = false;

    meta = {
      description = "Asynchronous connection pool for SQLite";
      homepage = "https://github.com/nackjicholson/aiosqlitepool";
      license = prev.lib.licenses.mit;
    };
  };

  version = "1.13.3";

  src = prev.fetchFromGitHub {
    owner = "av1155";
    repo = "houndarr";
    rev = "9b39fdbcef714b5562e9326fde7354526955bad8";
    hash = "sha256-ozIyfuvNYl1PxN/jd4J4ghDzGald4ai1hIWgh2muzI4=";
  };

  # The compiled stylesheet, built with the same pnpm + Tailwind toolchain the
  # project's own Dockerfile uses.
  css = prev.stdenv.mkDerivation (finalAttrs: {
    pname = "houndarr-css";
    inherit version src;

    pnpmDeps = prev.fetchPnpmDeps {
      inherit (finalAttrs) pname version src;
      pnpm = prev.pnpm_11;
      fetcherVersion = 4;
      hash = "sha256-V/X8tWToeqLiPHOSBzGuEFCDPdTNxrNiA2Y+xDs0tYU=";
    };

    nativeBuildInputs = [
      prev.pnpm_11
      prev.pnpmConfigHook
      prev.nodejs-slim
    ];

    buildPhase = "pnpm run build-css";
    installPhase = "install -Dm644 src/houndarr/static/css/app.built.css $out/app.built.css";
  });
in {
  houndarr = prev.python3Packages.buildPythonApplication (finalAttrs: {
    pname = "houndarr";
    inherit version src;

    pyproject = true;
    build-system = [prev.python3Packages.hatchling];

    dependencies = with prev.python3Packages; [
      fastapi
      starlette
      uvicorn
      jinja2
      markupsafe
      aiosqlite
      aiosqlitepool
      async-lru
      httpx
      bcrypt
      cryptography
      itsdangerous
      python-multipart
      click
      pydantic
    ];

    # The CSS is not in the repository; it is generated above.
    preBuild = "cp ${css}/app.built.css src/houndarr/static/css/app.built.css";

    # houndarr reads its version from a VERSION file three directories above
    # the package (repo root in a checkout, lib/python3.X in a wheel install),
    # so without this it reports 0.0.0. The project's own sdist ships VERSION,
    # but hatchling's wheel target does not include it.
    postInstall = ''
      install -Dm644 ${src}/VERSION \
        "$out/$(dirname ${prev.python3Packages.python.sitePackages})/VERSION"
    '';

    pythonImportsCheck = ["houndarr"];

    meta = {
      description = "Search scheduler for the *arr applications";
      homepage = "https://github.com/av1155/houndarr";
      license = prev.lib.licenses.agpl3Only;
      platforms = prev.lib.platforms.linux;
      mainProgram = "houndarr";
    };
  });
}
