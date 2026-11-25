{
  imports = [
    ./inkling2mini
    ./qwen36
    ./qwen38
  ];

  perSystem = { pkgs, ... }: {
    checks.launcher-config =
      pkgs.runCommand "strata-launcher-config-tests"
        {
          nativeBuildInputs = [ pkgs.bash ];
        }
        ''
          bash ${./launcher-common-test.sh} ${./launcher-common.sh}
          bash ${./qwen38/memory-preflight-test.sh} ${./qwen38/memory-preflight.sh}
          touch "$out"
        '';
    checks.service-launcher =
      pkgs.runCommand "strata-service-launcher-tests"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.gnugrep
          ];
        }
        ''
          bash ${./service-launcher-test.sh} ${./service-launcher.sh}
          touch "$out"
        '';
  };
}
