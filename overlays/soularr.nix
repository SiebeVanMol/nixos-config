# overlays/soularr.nix
#
# Soularr (https://github.com/mrusse/soularr), a Python bridge between Lidarr and
# slskd, not in nixpkgs. It reads Lidarr's wanted/missing albums, asks the
# VPN-confined slskd to search Soulseek and download them, then tells Lidarr to
# import the results - which is how one UI drives music acquisition while the
# peer traffic stays in wg0.
#
# `slskd-api` is a pure-Python wheel; Soularr is a bare script with no setup.py,
# so it is wrapped around a Python environment rather than installed as a
# package. Only the CLI is packaged - the optional web frontend is not used.
_final: prev: let
  slskd-api = prev.python3Packages.buildPythonPackage rec {
    pname = "slskd-api";
    version = "0.1.5";
    format = "wheel";

    src = prev.fetchurl {
      url = "https://files.pythonhosted.org/packages/83/d8/4f06e30ca269ce08076fa42b62727a6c6c8983b28aa9028e51221eeb92a0/slskd_api-0.1.5-py3-none-any.whl";
      hash = "sha256-3gPCGgtfK2MW+NvycMaFkIW/VS6B7WAkqxkvUdRWpMA=";
    };

    propagatedBuildInputs = [prev.python3Packages.requests];

    meta = {
      description = "API wrapper to interact with slskd";
      homepage = "https://github.com/bigoulours/slskd-python-api";
      license = prev.lib.licenses.mit;
    };
  };

  # Soularr's requirements.txt, minus flask/waitress which are only for the
  # optional web UI.
  python = prev.python3.withPackages (ps: [
    ps.music-tag
    ps.pyarr
    slskd-api
  ]);
in {
  soularr = prev.stdenv.mkDerivation (finalAttrs: {
    pname = "soularr";
    version = "1.2.2";

    # Upstream tags releases now (v1.2.2), so this follows the tag rather than a
    # bare commit: the `unstable-<date>` pin existed only because there were no
    # tags to point at, and a tag is the version string a reader can check.
    src = prev.fetchFromGitHub {
      owner = "mrusse";
      repo = "soularr";
      tag = "v${finalAttrs.version}";
      hash = "sha256-gtz99+DiFjJZuq54qo5C+5Exx++S+ePzldgDM9NHAOA=";
    };

    nativeBuildInputs = [prev.makeWrapper];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/soularr
      cp soularr.py config.ini $out/share/soularr/

      makeWrapper ${python}/bin/python $out/bin/soularr \
        --add-flags "$out/share/soularr/soularr.py"

      runHook postInstall
    '';

    meta = {
      description = "Downloads Lidarr's wanted albums from Soulseek through slskd";
      homepage = "https://github.com/mrusse/soularr";
      license = prev.lib.licenses.mit;
      platforms = prev.lib.platforms.linux;
      mainProgram = "soularr";
    };
  });
}
