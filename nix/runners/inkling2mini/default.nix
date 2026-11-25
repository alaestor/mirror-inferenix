{
  perSystem =
    { config, pkgs, ... }:
    let
      frontend = config.packages.strata-unbiased-frontend;
      engine = config.packages.strata;
      launcher = import ./launcher.nix { inherit pkgs frontend engine; };
    in
    {
      packages.inkling2mini = launcher;
      apps.inkling2mini = {
        type = "app";
        program = "${launcher}/bin/inkling2mini";
        meta.description = "Serve Inkling 2 Mini with Niko Strata on AMD HIP";
      };
      checks.inkling2mini-runner = launcher;
      checks.inkling2mini-launcher = pkgs.runCommand "inkling2mini-launcher-tests" { } ''
        bash ${./launch-test.sh} ${../launcher-common.sh} ${./launch.sh}
        touch "$out"
      '';
    };
}
