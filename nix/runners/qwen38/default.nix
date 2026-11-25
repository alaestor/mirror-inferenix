{ inputs, ... }:
{
  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    let
      rocm = pkgs.rocmPackages;
      strata = config.packages.strata-unbiased;
      inherit (strata) llamaSource;
      packSource = strata.src;
      qwen38 = import ./launcher.nix { inherit pkgs strata; };
      inherit (qwen38) python;
      launcherCommon = ../launcher-common.sh;
      mkServiceLauncher = import ../service-launcher.nix { inherit inputs pkgs system; };
      qwen38Launcher = mkServiceLauncher {
        modelName = "qwen38";
        foregroundService = true;
      };
      prepareQwen38 = qwen38.prepare;
      serveQwen38 = qwen38.mkServe { supervised = true; };
    in
    {
      packages = {
        prepare-qwen38 = prepareQwen38;
        qwen38 = qwen38Launcher;
      };
      apps.prepare-qwen38 = {
        type = "app";
        program = "${prepareQwen38}/bin/strata-prepare-qwen38";
        meta.description = "Prepare Qwen3.8 packs from local model and draft inputs";
      };
      apps.qwen38 = {
        type = "app";
        program = "${qwen38Launcher}/bin/strata-qwen38";
        meta.description = "Serve Qwen3.8 from local weights and prepared packs";
      };
      legacyPackages.qwen38 = serveQwen38;
      checks.pack-validation =
        pkgs.runCommand "strata-pack-validation-tests"
          {
            nativeBuildInputs = [ python ];
            STRATA_GGUF_PY = "${llamaSource}/gguf-py";
          }
          ''
            python -m unittest discover -s ${packSource}/tools -p test_iq_pack.py
            touch "$out"
          '';
      checks.qwen38-runner =
        pkgs.runCommand "qwen38-runner-tests"
          {
            nativeBuildInputs = [
              pkgs.bash
              pkgs.gnugrep
              pkgs.coreutils
              pkgs.jq
            ];
          }
          ''
            bash ${./qwen38-test.sh} ${launcherCommon} ${./qwen38-inputs.sh} \
              ${./qwen38-prepare.sh} ${./qwen38-serve.sh} \
              ${prepareQwen38}/bin/strata-prepare-qwen38
            touch "$out"
          '';
      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.cmake
          pkgs.ninja
          python
          rocm.clr
          rocm.hipblas
          rocm.rocblas
        ];
        STRATA_GGUF_PY = "${llamaSource}/gguf-py";
      };
    };
}
