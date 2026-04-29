{
  pkgs,
  config,
  lib,
  ...
}: {
  imports = [
    ./dconf.nix
  ];

  home.packages = with pkgs; [
    xournalpp
    wl-clipboard
  ];

  programs.tmux.extraConfig = lib.mkAfter ''
    set -g status-right-length 120
  '';

  xdg.configFile."tmux/theme-dark.conf".source = lib.mkForce (
    pkgs.writeText "tmux-theme-dark-timy.conf" (
      builtins.readFile ../../modules/home/tmux/theme-dark.conf
      + "\nset -g status-right '#[fg=#4fc1ff,bg=default,bold]#{?window_zoomed_flag,+, }#[fg=#b4befe,nobold] #(duo status)#(cpu) #[fg=#b4befe]#(memory) #[bg=default]#(battery) #[fg=#daeafa,nobold]%H:%M'\n"
    )
  );

  xdg.configFile."tmux/theme-light.conf".source = lib.mkForce (
    pkgs.writeText "tmux-theme-light-timy.conf" (
      builtins.readFile ../../modules/home/tmux/theme-light.conf
      + "\nset -g status-right \"#[fg=#4c4f69,bg=default,bold]#{?window_zoomed_flag,+, }#[fg=#1487d6] #(duo status)#(cpu) #[fg=#1487d6]#(memory) #[bg=default]#(battery) #[fg=#1f232e,nobold]%H:%M\"\n"
    )
  );

  # nixpkgs.config.allowUnfree = true;

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
