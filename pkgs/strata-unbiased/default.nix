{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  rocmPackages,
  frontendOnly ? false,
  gpuArch ? "gfx1100",
}:
let
  rocm = rocmPackages;
  llamaSource = fetchFromGitHub {
    owner = "robertkarl";
    repo = "llama.cpp";
    rev = "db1f382bb25f9cc481893105dbead09c86a52f01";
    hash = "sha256-Him+wiXA84lA638Ltql3Guzr5FEEe+CbTgN+0SXr9ng=";
  };
  targets = [
    "unbiased-strata"
  ]
  ++ lib.optionals (!frontendOnly) [
    "strata"
    "strata-poly"
    "strata-device"
    "native_expert_parity"
  ];
in
stdenv.mkDerivation {
  pname = if frontendOnly then "unbiased-strata-frontend" else "unbiased-strata-hip";
  version = "0.1.45-poly.1";
  src = fetchFromGitHub {
    owner = "robertkarl";
    repo = "UnbiasedStrata";
    rev = "9f75192287c2abf88c77da3b4b6f54ccee01db83";
    hash = "sha256-RI2/+EHPL1DmXtEUf/l+JC31nNSnffPZocYt8kkEOG0=";
  };

  patches = [
    ./patches/0001-hip-build.patch
    ./patches/0002-frontend-sampling-and-inkling-vocab.patch
    ./patches/0003-fp16-parity-diagnostics.patch
  ];
  nativeBuildInputs = [
    cmake
    ninja
  ];
  buildInputs = lib.optionals (!frontendOnly) [
    rocm.clr
    rocm.hipblas
    rocm.rocblas
  ];

  postUnpack = ''
    mkdir -p "$sourceRoot/third_party/llama.cpp"
    cp -r ${llamaSource}/. "$sourceRoot/third_party/llama.cpp/"
    chmod -R u+w "$sourceRoot/third_party/llama.cpp"
  '';
  cmakeFlags = [
    "-DSTRATA_ENABLE_HIP=${if frontendOnly then "OFF" else "ON"}"
    "-DSTRATA_ENABLE_CUDA=OFF"
    "-DSTRATA_BUILD_TESTS=OFF"
    "-DSTRATA_PORTABLE=ON"
  ]
  ++ lib.optionals (!frontendOnly) [
    "-DCMAKE_HIP_COMPILER=${rocm.clr.hipClangPath}/clang++"
    "-DCMAKE_HIP_ARCHITECTURES=${gpuArch}"
  ];
  buildPhase = ''
    runHook preBuild
    jobs="$NIX_BUILD_CORES"
    if [ "$jobs" -eq 0 ] || [ "$jobs" -gt 4 ]; then jobs=4; fi
    cmake --build . --target ${lib.escapeShellArgs targets} --parallel "$jobs"
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    for target in ${lib.escapeShellArgs targets}; do
      install -Dm755 "$target" "$out/bin/$target"
    done
    runHook postInstall
  '';
  passthru = { inherit llamaSource; };
  meta = {
    description = "UnbiasedStrata C++ API server${
      lib.optionalString (!frontendOnly) " and HIP engines"
    }";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "unbiased-strata";
  };
}
