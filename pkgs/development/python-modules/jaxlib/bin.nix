# For the moment we only support the CPU and GPU backends of jaxlib. The TPU
# backend will require some additional work. Those wheels are located here:
# https://storage.googleapis.com/jax-releases/libtpu_releases.html.

# For future reference, the easiest way to test the GPU backend is to run
#   NIX_PATH=.. nix-shell -p python3 python3Packages.jax "python3Packages.jaxlib-bin.override { cudaSupport = true; }"
#   export XLA_FLAGS=--xla_gpu_force_compilation_parallelism=1
#   python -c "from jax.lib import xla_bridge; assert xla_bridge.get_backend().platform == 'gpu'"
#   python -c "from jax import random; random.PRNGKey(0)"
#   python -c "from jax import random; x = random.normal(random.PRNGKey(0), (100, 100)); x @ x"
# There's no convenient way to test the GPU backend in the derivation since the
# nix build environment blocks access to the GPU. See also:
#   * https://github.com/google/jax/issues/971#issuecomment-508216439
#   * https://github.com/google/jax/issues/5723#issuecomment-913038780

{ absl-py
, addOpenGLRunpath
, autoPatchelfHook
, buildPythonPackage
, config
, fetchPypi
, fetchurl
, flatbuffers
, jaxlib-build
, lib
, ml-dtypes
, python
, scipy
, stdenv
  # Options:
, cudaSupport ? config.cudaSupport
, cudaPackagesGoogle
}:

let
  inherit (cudaPackagesGoogle) cudatoolkit cudnn cudaVersion;

  version = "0.4.24";

  inherit (python) pythonVersion;

  # As of 2023-06-06, google/jax upstream is no longer publishing CPU-only wheels to their GCS bucket. Instead the
  # official instructions recommend installing CPU-only versions via PyPI.
  cpuSrcs =
    let
      getSrcFromPypi = { platform, dist, hash }: fetchPypi {
        inherit version platform dist hash;
        pname = "jaxlib";
        format = "wheel";
        # See the `disabled` attr comment below.
        python = dist;
        abi = dist;
      };
    in
    {
      "3.9-x86_64-linux" = getSrcFromPypi {
        platform = "manylinux2014_x86_64";
        dist = "cp39";
        hash = "sha256-6P5ArMoLZiUkHUoQ/mJccbNj5/7el/op+Qo6cGQ33xE=";
      };
      "3.9-aarch64-darwin" = getSrcFromPypi {
        platform = "macosx_11_0_arm64";
        dist = "cp39";
        hash = "sha256-23JQZRwMLtt7sK/JlCBqqRyfTVIAVJFN2sL+nAkQgvU=";
      };
      "3.9-x86_64-darwin" = getSrcFromPypi {
        platform = "macosx_10_14_x86_64";
        dist = "cp39";
        hash = "sha256-OgMedn9GHGs5THZf3pkP3Aw/jJ0vL5qK1b+Lzf634Ik=";
      };

      "3.10-x86_64-linux" = getSrcFromPypi {
        platform = "manylinux2014_x86_64";
        dist = "cp310";
        hash = "sha256-/VwUIIa7mTs/wLz0ArsEfNrz2pGriVVT5GX9XRFRxfY=";
      };
      "3.10-aarch64-darwin" = getSrcFromPypi {
        platform = "macosx_11_0_arm64";
        dist = "cp310";
        hash = "sha256-LgICOyDGts840SQQJh+yOMobMASb62llvJjpGvhzrSw=";
      };
      "3.10-x86_64-darwin" = getSrcFromPypi {
        platform = "macosx_10_14_x86_64";
        dist = "cp310";
        hash = "sha256-vhyULw+zBpz1UEi2tqgBMQEzY9a6YBgEIg6A4PPh3bQ=";
      };

      "3.11-x86_64-linux" = getSrcFromPypi {
        platform = "manylinux2014_x86_64";
        dist = "cp311";
        hash = "sha256-VJO/VVwBFkOEtq4y/sLVgAV8Cung01JULiuT6W96E/8=";
      };
      "3.11-aarch64-darwin" = getSrcFromPypi {
        platform = "macosx_11_0_arm64";
        dist = "cp311";
        hash = "sha256-VtuwXxurpSp1KI8ty1bizs5cdy8GEBN2MgS227sOCmE=";
      };
      "3.11-x86_64-darwin" = getSrcFromPypi {
        platform = "macosx_10_14_x86_64";
        dist = "cp311";
        hash = "sha256-4Dj5dEGKb9hpg3HlVogNO1Gc9UibJhy1eym2mjivxAQ=";
      };

      "3.12-x86_64-linux" = getSrcFromPypi {
        platform = "manylinux2014_x86_64";
        dist = "cp312";
        hash = "sha256-TlrGVtb3NTLmhnILWPLJR+jISCZ5SUV4wxNFpSfkCBo=";
      };
      "3.12-aarch64-darwin" = getSrcFromPypi {
        platform = "macosx_11_0_arm64";
        dist = "cp312";
        hash = "sha256-FIwK5CGykQjteuWzLZnbtAggIxLQeGV96bXlZGEytN0=";
      };
      "3.12-x86_64-darwin" = getSrcFromPypi {
        platform = "macosx_10_14_x86_64";
        dist = "cp312";
        hash = "sha256-9/jw/wr6oUD9pOadVAaMRL086iVMUXwVgnUMcG1UNvE=";
      };
    };

  # Note that the prebuilt jaxlib binary requires specific version of CUDA to
  # work. The cuda12 jaxlib binaries only works with CUDA 12.2, and cuda11
  # jaxlib binaries only works with CUDA 11.8. This is why we need to find a
  # binary that matches the provided cudaVersion.
  gpuSrcVersionString = "cuda${cudaVersion}-${pythonVersion}";

  # Find new releases at https://storage.googleapis.com/jax-releases
  # When upgrading, you can get these hashes from prefetch.sh. See
  # https://github.com/google/jax/issues/12879 as to why this specific URL is the correct index.
  gpuSrcs = {
    "cuda12.2-3.9" = fetchurl {
      url = "https://storage.googleapis.com/jax-releases/cuda12/jaxlib-${version}+cuda12.cudnn89-cp39-cp39-manylinux2014_x86_64.whl";
      hash = "sha256-xdJKLPtx+CIza2CrWKM3M0cZJzyNFVTTTsvlgh38bfM=";
    };
    "cuda12.2-3.10" = fetchurl {
      url = "https://storage.googleapis.com/jax-releases/cuda12/jaxlib-${version}+cuda12.cudnn89-cp310-cp310-manylinux2014_x86_64.whl";
      hash = "sha256-QCjrOczD2mp+CDwVXBc0/4rJnAizeV62AK0Dpx9X6TE=";
    };
    "cuda12.2-3.11" = fetchurl {
      url = "https://storage.googleapis.com/jax-releases/cuda12/jaxlib-${version}+cuda12.cudnn89-cp311-cp311-manylinux2014_x86_64.whl";
      hash = "sha256-Ipy3vk1yUplpNzECAFt63aOIhgEWgXG7hkoeTIk9bQQ=";
    };
    "cuda12.2-3.12" = fetchurl {
      url = "https://storage.googleapis.com/jax-releases/cuda12/jaxlib-${version}+cuda12.cudnn89-cp312-cp312-manylinux2014_x86_64.whl";
      hash = "sha256-LSnZHaUga/8Z65iKXWBnZDk4yUpNykFTu3vukCchO6Q=";
    };
    "cuda11.8-3.9" = fetchurl {
      url = "https://storage.googleapis.com/jax-releases/cuda11/jaxlib-${version}+cuda11.cudnn86-cp39-cp39-manylinux2014_x86_64.whl";
      hash = "sha256-UmyugL0VjlXkiD7fuDPWgW8XUpr/QaP5ggp6swoZTzU=";
    };
    "cuda11.8-3.10" = fetchurl {
      url = "https://storage.googleapis.com/jax-releases/cuda11/jaxlib-${version}+cuda11.cudnn86-cp310-cp310-manylinux2014_x86_64.whl";
      hash = "sha256-luKULEiV1t/sO6eckDxddJTiOFa0dtJeDlrvp+WYmHk=";
    };
    "cuda11.8-3.11" = fetchurl {
      url = "https://storage.googleapis.com/jax-releases/cuda11/jaxlib-${version}+cuda11.cudnn86-cp311-cp311-manylinux2014_x86_64.whl";
      hash = "sha256-4+uJ8Ij6mFGEmjFEgi3fLnSLZs+v18BRoOt7mZuqydw=";
    };
    "cuda11.8-3.12" = fetchurl {
      url = "https://storage.googleapis.com/jax-releases/cuda11/jaxlib-${version}+cuda11.cudnn86-cp312-cp312-manylinux2014_x86_64.whl";
      hash = "sha256-bUDFb94Ar/65SzzR9RLIs/SL/HdjaPT1Su5whmjkS00=";
    };
  };

in
buildPythonPackage {
  pname = "jaxlib";
  inherit version;
  format = "wheel";

  disabled = !(pythonVersion == "3.9" || pythonVersion == "3.10" || pythonVersion == "3.11" || pythonVersion == "3.12");

  # See https://discourse.nixos.org/t/ofborg-does-not-respect-meta-platforms/27019/6.
  src =
    if !cudaSupport then
      (
        cpuSrcs."${pythonVersion}-${stdenv.hostPlatform.system}"
          or (throw "jaxlib-bin is not supported on ${stdenv.hostPlatform.system}")
      ) else gpuSrcs."${gpuSrcVersionString}";

  # Prebuilt wheels are dynamically linked against things that nix can't find.
  # Run `autoPatchelfHook` to automagically fix them.
  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ]
    ++ lib.optionals cudaSupport [ addOpenGLRunpath ];
  # Dynamic link dependencies
  buildInputs = [ stdenv.cc.cc.lib ];

  # jaxlib contains shared libraries that open other shared libraries via dlopen
  # and these implicit dependencies are not recognized by ldd or
  # autoPatchelfHook. That means we need to sneak them into rpath. This step
  # must be done after autoPatchelfHook and the automatic stripping of
  # artifacts. autoPatchelfHook runs in postFixup and auto-stripping runs in the
  # patchPhase. Dependencies:
  #   * libcudart.so.11.0 -> cudatoolkit_11.lib
  #   * libcublas.so.11   -> cudatoolkit_11
  #   * libcuda.so.1      -> opengl driver in /run/opengl-driver/lib
  preInstallCheck = lib.optional cudaSupport ''
    shopt -s globstar

    addOpenGLRunpath $out/**/*.so

    for file in $out/**/*.so; do
      rpath=$(patchelf --print-rpath $file)
      # For some reason `makeLibraryPath` on `cudatoolkit_11` maps to
      # <cudatoolkit_11.lib>/lib which is different from <cudatoolkit_11>/lib.
      patchelf --set-rpath "$rpath:${cudatoolkit}/lib:${lib.makeLibraryPath [ cudatoolkit.lib cudnn ]}" $file
    done
  '';

  propagatedBuildInputs = [
    absl-py
    flatbuffers
    ml-dtypes
    scipy
  ];

  # Note that cudatoolkit is snecessary since jaxlib looks for "ptxas" in $PATH.
  # See https://github.com/NixOS/nixpkgs/pull/164176#discussion_r828801621 for
  # more info.
  postInstall = lib.optional cudaSupport ''
    mkdir -p $out/bin
    ln -s ${cudatoolkit}/bin/ptxas $out/bin/ptxas
  '';

  inherit (jaxlib-build) pythonImportsCheck;

  meta = with lib; {
    description = "XLA library for JAX";
    homepage = "https://github.com/google/jax";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    license = licenses.asl20;
    maintainers = with maintainers; [ samuela ];
    platforms = [ "aarch64-darwin" "x86_64-linux" "x86_64-darwin" ];
    broken =
      !(cudaSupport -> (cudaPackagesGoogle ? cudatoolkit) && lib.versionAtLeast cudatoolkit.version "11.1")
      || !(cudaSupport -> (cudaPackagesGoogle ? cudnn) && lib.versionAtLeast cudnn.version "8.2")
      || !(cudaSupport -> stdenv.isLinux)
      || !(cudaSupport -> (gpuSrcs ? "cuda${cudaVersion}-${pythonVersion}"));
  };
}
