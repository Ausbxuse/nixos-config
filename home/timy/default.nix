{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/common/home/bloat.nix
    ../../modules/common/home/minimal-gui
    ../../modules/home/sops.nix
    ./dconf.nix
  ];

  #### Extra configs

  home.activation.installTimyScripts = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.rsync}/bin/rsync -avz --chmod=D2755,F744 ${./bin}/ ${config.home.homeDirectory}/.local/bin/
  '';

  #### extra packages
  home.packages = with pkgs; [
    xournalpp
    wl-clipboard
  ];
}
