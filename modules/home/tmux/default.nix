{
  pkgs,
  lib,
  ...
}: {
  programs.tmux = {
    enable = true;
  };

  home.packages = with pkgs; [
    lm_sensors
  ];

  xdg.configFile."tmux/theme-dark.conf".source = ./theme-dark.conf;
  xdg.configFile."tmux/theme-light.conf".source = ./theme-light.conf;
  programs.tmux = {
    extraConfig = builtins.readFile ./tmux.conf;
    shortcut = lib.mkDefault "f";
    keyMode = "vi";
    baseIndex = 1;
    escapeTime = 20;
    historyLimit = 30000;
    aggressiveResize = true;
    clock24 = true;
    terminal = "tmux-256color";
    mouse = true;

    plugins = with pkgs.tmuxPlugins; [
      sensible
      {
        plugin = resurrect;
        extraConfig = ''

          resurrect_dir="$HOME/.local/share/tmux/resurrect"
          set -g @resurrect-dir $resurrect_dir
          set -g @resurrect-hook-post-save-all 'target=$(readlink -f $HOME/.local/share/tmux/resurrect/last); sed "s|\(.*bin/nvim\) .*|\1|; s|/etc/profiles/per-user/$USER/bin/||g; s|/home/$USER/.nix-profile/bin/||g" $target | sponge $target'
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-processes '"~nvim"'
        '';
      }
      {
        plugin = continuum; # needs resurrect present
        extraConfig = ''
            set -g status-interval 60         # update the status bar every 10 seconds
            set -g status-justify centre
            set -g status-position top
            set -g status-style 'bg=default'  # transparent background
            set -g status-left-length 50
            set -g status-right-length 70
            set -g status-bg 'default'
            if-shell 'command -v gsettings >/dev/null 2>&1 && gsettings get org.gnome.desktop.interface color-scheme | grep -q prefer-dark' \
              'source-file ~/.config/tmux/theme-dark.conf' \
              'source-file ~/.config/tmux/theme-light.conf'


            set -g @continuum-restore 'on'
            set -g @continuum-save-interval '5'
            set -g @continuum-boot 'on'
            set -g @continuum-boot-options 'ghostty'
          # set -g @continuum-systemd-start-cmd 'start-server'
        '';
      }
    ];
  };
}
