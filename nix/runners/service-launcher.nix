{
  inputs,
  pkgs,
  system,
}:
let
  serviceCommon = ./service-launcher.sh;
in
{ modelName, foregroundService }:
pkgs.writeShellApplication {
  name = "strata-${modelName}";
  runtimeInputs = [
    pkgs.nix
    pkgs.systemd
  ];
  extraShellCheckFlags = [ "-x" ];
  text = ''
    source ${serviceCommon}
    strata_service_dispatch strata-${modelName}.service \
      ${builtins.toJSON foregroundService} \
      ${inputs.self}#legacyPackages.${system}.${modelName} "$@"
  '';
}
