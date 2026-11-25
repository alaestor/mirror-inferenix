{
  perSystem =
    { pkgs, ... }:
    let
      strata = pkgs.callPackage ../pkgs/strata-unbiased { };
      frontend = strata.override { frontendOnly = true; };
      niko = import ../pkgs/strata { inherit pkgs; };
      gpuCheck = pkgs.writeShellApplication {
        name = "strata-check-gpu";
        runtimeInputs = [ strata ];
        text = ''
          strata-device
          for pair in q4_K/q5_1 q5_K/q5_1 q6_K/q5_1; do
            native_expert_parity --synthetic "$pair"
          done
        '';
      };
    in
    {
      packages = {
        default = strata;
        strata = niko;
        strata-unbiased = strata;
        strata-unbiased-frontend = frontend;
        strata-niko-0-1-67 = niko;
      };
      apps.default = {
        type = "app";
        program = "${strata}/bin/unbiased-strata";
        meta.description = "Run the UnbiasedStrata HTTP server";
      };
      apps.check-gpu = {
        type = "app";
        program = "${gpuCheck}/bin/strata-check-gpu";
        meta.description = "Run the AMD device and synthetic expert parity diagnostics";
      };
      formatter = pkgs.nixfmt;
      checks = {
        strata-unbiased = strata;
        strata-niko-0-1-67 = niko;
        frontend = frontend.overrideAttrs (old: {
          pname = "strata-frontend-tests";
          nativeBuildInputs = old.nativeBuildInputs ++ [
            pkgs.python3
            pkgs.curl
          ];
          postPatch = "patchShebangs frontend/tests";
          buildPhase = ''
            runHook preBuild
            cmake --build . --target unbiased-strata engine_test literals_test picture_cache_test hy4_sampling_test sampling_defaults_test --parallel 4
            runHook postBuild
          '';
          doCheck = true;
          checkPhase = ''
            runHook preCheck
            ./engine_test "$PWD/../frontend/tests/fake-engine.py"
            ./literals_test
            ./picture_cache_test
            ./hy4_sampling_test
            ./sampling_defaults_test
            python3 ../frontend/tests/sampling-defaults-e2e.py "$PWD/unbiased-strata"
            bash ../frontend/tests/e2e.sh "$PWD/unbiased-strata"
            runHook postCheck
          '';
          installPhase = "touch $out";
        });
      };
    };
}
