{
  pkgs,
  gpuArch ? "gfx1100",
}:
let
  pin = builtins.fromJSON (builtins.readFile ./source.json);
  rocm = pkgs.rocmPackages;
in
pkgs.stdenv.mkDerivation {
  pname = "strata-inkling-hip";
  inherit (pin) version;
  src = pkgs.fetchurl {
    name = "strata-${pin.version}-source.tar.gz";
    inherit (pin) url sha256;
  };
  cmakeDir = "../engine/src/inkling2";
  nativeBuildInputs = [
    pkgs.cmake
    pkgs.ninja
  ];
  buildInputs = [ rocm.clr ];
  cmakeFlags = [
    "-DSTRATA_ENABLE_HIP=ON"
    "-DSTRATA_HIP_ARCHS=${gpuArch}"
    "-DSTRATA_HIP_CXX=${rocm.clr.hipClangPath}/clang++"
    "-DSTRATA_HIP_RUNTIME_LIB=${rocm.clr}/lib/libamdhip64.so"
  ];
  buildPhase = ''
    runHook preBuild
    cmake --build . --target strata-inkling --parallel 4
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    cmake --install . --component inkling2
    install -Dm644 ../LICENSE "$out/share/licenses/strata-inkling/LICENSE"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    "$out/bin/strata-inkling" --version | grep -Fx 'strata-inkling ${pin.version}'
  '';
  meta = {
    description = "Niko1221's standalone Strata Inkling 2 HIP engine";
    license = pkgs.lib.licenses.mit;
    mainProgram = "strata-inkling";
  };
}
