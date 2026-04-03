{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./minimal.nix
    ../../home/display-profile.nix
    ../../home/zathura
    ../../home/firefox
    ../../home/ghostty
    ../../home/dev-tools.nix
    ../../home/gnome
    ../../home/autostart
    ../../home/xdg.nix
    ../../home/de
  ];

  home.pointerCursor = {
    name = "capitaine-cursors-white";
    package = pkgs.bibata-cursors;
    size = lib.mkDefault 24;
    gtk.enable = true;
    x11.enable = true;
    x11.defaultCursor = "capitaine-cursors-white";
  };

}
