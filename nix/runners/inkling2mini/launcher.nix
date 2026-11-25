{
  pkgs,
  frontend,
  engine,
}:
pkgs.writeShellApplication {
  name = "inkling2mini";
  extraShellCheckFlags = [ "-x" ];
  text = ''
    inkling2mini_frontend=${frontend}/bin/unbiased-strata
    inkling2mini_engine=${engine}/bin/strata-inkling
    source ${../launcher-common.sh}
    ${builtins.readFile ./launch.sh}
  '';
}
