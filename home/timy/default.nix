{
  pkgs,
  config,
  ...
}: {
  imports = [
    ../../modules/common/home/bloat.nix
    ../../modules/common/home/minimal-gui
    ../../modules/home/sops.nix
    ./dconf.nix
  ];

  home.packages = with pkgs; [
    xournalpp
    wl-clipboard
  ];

  nixpkgs.config.allowUnfree = true;

  home.file."${config.home.homeDirectory}/.local/bin/startup" = {
    text = ''
      #!/usr/bin/env bash

      $HOME/.local/bin/duo set-displays
      $HOME/.local/bin/duo watch-displays &>/dev/null 2>&1 &
      $HOME/.local/bin/duo watch-rotation &>/dev/null 2>&1 &
      $HOME/.local/bin/duo watch-backlight &>/dev/null 2>&1 &
      $HOME/.local/bin/duo bat-limit &>/dev/null 2>&1 &

      tmux new-session -Ad -s main

      $HOME/.local/bin/setlight

      dbus-monitor --session "type='signal',interface='org.gnome.ScreenSaver'" |
              while read x; do
                      case "$x" in
                      *"boolean true"*) echo SCREEN_LOCKED ;;
                      *"boolean false"*) $HOME/.local/bin/duo set-displays &>/dev/null 2>&1 ;;
                      esac
              done &
      sct 3700
    '';
    executable = true;
  };
}
