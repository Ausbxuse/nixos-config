{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./minimal-gui.nix
    ../../home/sops.nix
    ../../home/programs.nix
    ../../home/gaming.nix
  ];

  home.packages = with pkgs; [
    jupyter
    gnome-graphs
    thunderbird-bin
    brave
    spotify-tray
    libreoffice
    texliveFull
    gimp
    foliate
    obs-studio
    calibre
    quickemu
    discord
    spotify
    codex
  ] ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [pkgs.sct];

  services.syncthing.enable = true;
  my.display.profile = lib.mkDefault "gnome-default";
}
