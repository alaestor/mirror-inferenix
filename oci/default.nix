{
  perSystem =
    { pkgs, config, ... }:
    let
      imageTargets = [
        "gfx1100"
        "gfx1201"
      ];
      release = pkgs.writeShellApplication {
        name = "inferenix-release";
        runtimeInputs = with pkgs; [
          coreutils
          gzip
          gnutar
        ];
        runtimeEnv = {
          qwenArchive = "${config.packages.qwen38-oci-gfx1201-slim}";
          inkling2miniArchive = "${config.packages.inkling2mini-oci-gfx1201}";
          usageGuide = "${./USAGE.md}";
        };
        text = builtins.readFile ./release.sh;
      };
      mkEntrypoint =
        name: servePath: preparePath:
        pkgs.writeShellApplication {
          name = "inferenix-${name}";
          text = ''
            usage() { echo 'Usage: ${name} ${
              if preparePath == null then "serve" else "{prepare|serve}"
            } [OPTIONS]'; }
            case "''${1:-serve}" in
              serve) if (( $# )); then shift; fi; exec ${servePath} "$@" ;;
              ${pkgs.lib.optionalString (preparePath != null) ''
                prepare) shift; exec ${preparePath} "$@" ;;
              ''}
              -h|--help|help) usage ;;
              *) usage >&2; exit 2 ;;
            esac
          '';
        };
      mkImage =
        {
          name,
          model,
          servePath,
          preparePath ? null,
          tag,
        }:
        let
          entrypoint = mkEntrypoint name servePath preparePath;
        in
        (pkgs.dockerTools.buildLayeredImage {
          name = "localhost/inferenix/${name}";
          inherit tag;
          extraCommands = ''
            mkdir -p tmp
            chmod 1777 tmp
          '';
          config = {
            Entrypoint = [ "${entrypoint}/bin/inferenix-${name}" ];
            Cmd = [ "serve" ];
            Env = [
              "INFERENIX_HOST=0.0.0.0"
              "INFERENIX_PREPARED_DIR=/packs"
              "HOME=/tmp"
            ];
            ExposedPorts."8080/tcp" = { };
          };
        }).overrideAttrs
          { name = "inferenix-${model}-${tag}.tar.gz"; };
      mkQwenImage =
        strata: tag:
        let
          qwen38 = import ../nix/runners/qwen38/launcher.nix { inherit pkgs strata; };
          qwenServe = qwen38.mkServe { };
        in
        mkImage {
          inherit tag;
          name = "qwen38";
          model = "qwen38-swift";
          servePath = "${qwenServe}/bin/strata-qwen38";
          preparePath = "${qwen38.prepare}/bin/strata-prepare-qwen38";
        };
      mkImagesFor =
        gpuArch:
        let
          strata = config.packages.strata-unbiased.override { inherit gpuArch; };
          inkling2mini = import ../nix/runners/inkling2mini/launcher.nix {
            inherit pkgs;
            frontend = config.packages.strata-unbiased-frontend;
            engine = import ../pkgs/strata { inherit pkgs gpuArch; };
          };
        in
        {
          "qwen38-oci-${gpuArch}" = mkQwenImage strata gpuArch;
          "inkling2mini-oci-${gpuArch}" = mkImage {
            tag = gpuArch;
            name = "inkling2mini";
            model = "inkling-2-mini-text";
            servePath = "${inkling2mini}/bin/inkling2mini";
          };
        }
        // pkgs.lib.optionalAttrs (gpuArch == "gfx1201") {
          qwen38-oci-gfx1201-slim = mkQwenImage (strata.override {
            rocmPackages = pkgs.rocmPackages.${gpuArch};
          }) "${gpuArch}-slim";
        };
    in
    {
      packages = pkgs.lib.mergeAttrsList (map mkImagesFor imageTargets);
      apps.release = {
        type = "app";
        program = "${release}/bin/inferenix-release";
        meta.description = "Bundle the slim Tumbleweed images and quickstart for gfx1201";
      };
    };
}
