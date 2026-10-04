# overlays/hipfire.nix
#
# hipfire's kernel build exports HIPFIRE_ROCM_PATH from `rocmPackages.clr` and
# its resolver then demands libamdhip64, libhsa-runtime64, the HIP headers and
# hipcc from that single prefix. Current nixpkgs splits the HSA runtime out into
# the separate `rocm-runtime` package, so the lookup fails and the whole system
# build dies on hipfire-kernels. Hand the kernel build a joined ROCm prefix that
# carries both libraries; the daemon itself only needs LD_LIBRARY_PATH, which
# upstream's wrapper already sets from the same packages.
_final: prev: let
  hipfireRocm = prev.symlinkJoin {
    name = "hipfire-rocm";
    paths = with prev.rocmPackages; [
      clr
      rocm-runtime
      rocm-comgr
      rocprofiler-register
    ];
  };
in {
  hipfire-kernels = prev.hipfire-kernels.override {
    rocmPackages = prev.rocmPackages // {clr = hipfireRocm;};
  };
}
