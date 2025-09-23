{pkgs, ...}: {
  imports = [
    ../../home/wezterm
    ../../home/ghostty
    ../../home/programs.nix
    ../../home/gaming.nix
  ];
  home.packages = with pkgs; [
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
    sct
    discord
    spotify
    # wechat-uos
  ];

  services.syncthing = {
    enable = true;
    # tray.enable = true;
  };
}
