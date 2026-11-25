{ pkgs, strata }:
let
  inherit (strata) llamaSource;
  packSource = strata.src;
  launcherCommon = ../launcher-common.sh;
  serviceCommon = ../service-launcher.sh;
  python = pkgs.python3.withPackages (ps: [
    ps.numpy
    ps.regex
    ps.pyyaml
    ps.tqdm
  ]);
  # Keep the two full source trees out of the image's runtime closure.
  packAssets = pkgs.runCommand "qwen38-pack-assets" { } ''
    mkdir -p "$out"/{tools,data,gguf-py}
    cp ${packSource}/tools/{_paths,gguf_reader,iq_pack,mtp_pack,mtp_rt,strata_tokenizer}.py "$out/tools/"
    cp ${packSource}/data/{expert-profile,draft_vocab}.bin "$out/data/"
    cp ${packSource}/LICENSE "$out/LICENSE.strata"
    cp -r ${llamaSource}/gguf-py/{gguf,LICENSE} "$out/gguf-py/"
  '';
  prepare = pkgs.writeShellApplication {
    name = "strata-prepare-qwen38";
    extraShellCheckFlags = [ "-x" ];
    runtimeInputs = [
      python
      pkgs.coreutils
    ];
    text = ''
      export STRATA_GGUF_PY=${packAssets}/gguf-py
      qwen38_pack_tools=${packAssets}/tools
      qwen38_pack_data=${packAssets}/data
      source ${launcherCommon}
      source ${./qwen38-inputs.sh}
      ${builtins.readFile ./qwen38-prepare.sh}
    '';
  };
  mkServe =
    {
      supervised ? false,
    }:
    pkgs.writeShellApplication {
      name = "strata-qwen38";
      extraShellCheckFlags = [ "-x" ];
      runtimeInputs = [
        pkgs.coreutils
        pkgs.jq
      ]
      ++ pkgs.lib.optionals supervised [
        pkgs.systemd
        pkgs.nix
      ];
      text = ''
        source ${launcherCommon}
        source ${./qwen38-inputs.sh}
        qwen38_run() {
          ${
            if supervised then
              ''
                source ${serviceCommon}
                export STRATA_SERVICE_ROOT="''${STRATA_SERVICE_ROOT:-''${0%/bin/*}}"
                strata_service_run strata-qwen38.service \
                  -p "MemoryMax=''${STRATA_QWEN38_MEMORY_MAX:-48G}" -p MemorySwapMax=0 \
                  ${pkgs.bash}/bin/bash ${./memory-preflight.sh} "$@"
              ''
            else
              ''
                if [[ -n ''${STRATA_QWEN38_MEMORY_MAX:-} ]]; then
                  qwen38_warn 'INFERENIX_MEMORY_MAX applies only to the systemd launcher. Set a Podman memory limit instead.'
                fi
                exec "$@"
              ''
          }
        }
        qwen38_frontend=${strata}/bin/unbiased-strata
        ${builtins.readFile ./qwen38-serve.sh}
      '';
    };
in
{
  inherit prepare mkServe python;
}
