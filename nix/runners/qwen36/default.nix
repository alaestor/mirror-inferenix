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
      strata = config.packages.strata-unbiased;
      launcherCommon = ../launcher-common.sh;
      serviceCommon = ../service-launcher.sh;
      mkServiceLauncher = import ../service-launcher.nix { inherit inputs pkgs system; };
      localLauncher = mkServiceLauncher {
        modelName = "qwen36";
        foregroundService = false;
      };
      serveLocal = pkgs.writeShellApplication {
        name = "strata-qwen36";
        runtimeInputs = [
          pkgs.systemd
          pkgs.nix
        ];
        extraShellCheckFlags = [ "-x" ];
        text = ''
          export STRATA_SERVICE_ROOT="''${STRATA_SERVICE_ROOT:-''${0%/bin/*}}"
          source ${launcherCommon}
          source ${serviceCommon}
          strata_parse_env_args "$@"
          set -- "''${strata_launch_args[@]}"
          load_strata_env
          if [ "$#" -ge 1 ] && [[ "$1" != -* ]]; then
            STRATA_MODEL=$1
            shift
          fi
          if [ -z "$STRATA_MODEL" ]; then
            echo "Set INFERENIX_MODEL_QWEN36 in .env or pass MODEL.gguf" >&2
            exit 2
          fi
          strata_configure_args "$@"
          strata_service_or_exec strata-qwen36.service ${strata}/bin/unbiased-strata --engine strata-poly --model "$STRATA_MODEL" \
            "''${strata_server_args[@]}" -- --model "$STRATA_MODEL" "''${strata_engine_args[@]}"
        '';
      };
    in
    {
      packages.qwen36 = localLauncher;
      apps.qwen36 = {
        type = "app";
        program = "${localLauncher}/bin/strata-qwen36";
        meta.description = "Serve Qwen3.6 from a local GGUF";
      };
      legacyPackages.qwen36 = serveLocal;
    };
}
