# overlays/kapowarr.nix
#
# Kapowarr (https://github.com/Casvt/Kapowarr): a comic book library manager
# that slots into the *arr stack alongside Sonarr and Radarr.
#
# It is not packaged in nixpkgs, so we build it here. Kapowarr is a plain
# Python (Flask) application that upstream runs as a script - there is no
# installable package - and its frontend is hand-written JS committed to the
# repository, so there is no build step at all: ship the sources and wrap them
# with an interpreter that carries the dependencies.
#
# Every dependency from requirements.txt is already in nixpkgs except
# `bencoding`, a tiny dependency-free bencode codec, which is packaged inline.
final: prev: let
  bencoding = prev.python3Packages.buildPythonPackage rec {
    pname = "bencoding";
    version = "0.2.6";
    format = "setuptools";

    src = prev.fetchPypi {
      inherit pname version;
      hash = "sha256-Q8zjHUhj4p1rxhFVHU6fJlK+KZXp1eFbRtg4PxgNREA=";
    };

    doCheck = false;

    meta = {
      description = "Bencode encoder/decoder for Python 3";
      homepage = "https://pypi.org/project/bencoding/";
      license = prev.lib.licenses.mit;
    };
  };

  # Kapowarr's runtime dependencies, mirroring its requirements.txt.
  # `requests[socks]` pulls in PySocks alongside requests.
  kapowarrPython = prev.python3.withPackages (ps:
    with ps; [
      aiohttp
      beautifulsoup4
      bencoding
      cron-converter
      cryptography
      flask
      flask-socketio
      pysocks
      requests
      typing-extensions
      waitress
      websocket-client
    ]);
in {
  kapowarr = prev.stdenv.mkDerivation (finalAttrs: {
    pname = "kapowarr";
    version = "1.3.1";

    src = prev.fetchFromGitHub {
      owner = "Casvt";
      repo = "Kapowarr";
      tag = "V${finalAttrs.version}";
      hash = "sha256-BlIqXbpyNp1otxZHbKsJRsI9AgAMDnhzUI1WgahwWP0=";
    };

    nativeBuildInputs = [prev.makeWrapper];

    # Nothing to compile: the sources run as-is.
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/kapowarr
      cp -r . $out/share/kapowarr/

      # Wrap the interpreter (not the script) so that the PYTHONPATH carrying
      # the dependencies survives: Kapowarr re-executes Kapowarr.py in a
      # subprocess via sys.executable and relies on inheriting that environment.
      makeWrapper ${kapowarrPython}/bin/python3 $out/bin/kapowarr \
        --add-flags "-u $out/share/kapowarr/Kapowarr.py"

      runHook postInstall
    '';

    meta = {
      description = "Comic book library manager for the *arr stack";
      homepage = "https://github.com/Casvt/Kapowarr";
      license = prev.lib.licenses.gpl3Only;
      mainProgram = "kapowarr";
      platforms = prev.lib.platforms.linux;
    };
  });
}
