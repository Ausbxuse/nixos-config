{pkgs, lib, ...}: {
  imports = [
    ../../home/wezterm
    ../../home/ghostty
    ../../home/programs.nix
    ../../home/gaming.nix
  ];
  home.packages =
    builtins.filter (pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg)
    (with pkgs; [
      # Non essentials
      jupyter
      gnome-graphs
      thunderbird-bin
      brave
      spotify-tray
      libreoffice
      texliveFull
      gimp
      # font-manager
      foliate
      obs-studio
      # scrcpy
      calibre
      quickemu
      discord
      spotify
      codex
      # wechat-uos
    ])
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [pkgs.sct];

  services.syncthing = {
    enable = true;
    # tray.enable = true;
  };
}
