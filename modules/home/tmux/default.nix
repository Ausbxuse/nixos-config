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
            set -g status-left ' #{?client_prefix,^ ,}#{?#{==:#{env:SSH_CONNECTION},},#[fg=#9ece6a]local,#[fg=#f4bf75]#(whoami)#[fg=#9ece6a]@#[fg=#62d8f1]#H} #[fg=#2b2a30,bg=default]#[fg=#b4befe,bg=default]#S'
            set -g status-left ' #{?client_prefix,^ ,}#{?#{==:#{env:SSH_CONNECTION},},#[fg=#9ece6a]local,#[fg=#f4bf75]#(whoami)#[fg=#9ece6a]@#[fg=#62d8f1]#H} #[fg=#2b2a30,bg=default]#[fg=#b4befe,bg=default]#S#[fg=#2b2a30,bg=default] #[fg=#dfdcd8,bg=default]#(~/.local/bin/tmux/truncate_path.sh #{pane_current_path})'

            set -g status-right '#[fg=#4fc1ff,bg=default,bold]#{?window_zoomed_flag,+, }#[fg=#b4befe,bold]#[nobold] #[nobold]#(duo status)#(cpu) #(memory) #[bg=default]#(battery) #[fg=#daeafa,nobold]%H:%M #[bg=default]'
            # set -g status-right '#[fg=#4fc1ff,bg=default,bold]#{?window_zoomed_flag,+, }#[fg=#daeafa,nobold]%H:%M #[bg=default]'
            # set -g status-right '#[fg=#4fc1ff,bg=default,bold]#{?window_zoomed_flag,+, }#[fg=#b4befe,bold]#[nobold] #[nobold]#(duo status)#(cpu) #(memory) #[bg=default]#(battery) #[fg=#a9b1d6,bg=default,nobold,noitalics]#(forecast) #[fg=#daeafa,nobold]%H:%M #[bg=default]'
            #set -g status-right '#[fg=#4fc1ff,bg=default,bold]#{?window_zoomed_flag,+, }#[fg=#b4befe,bold]#[nobold] #[nobold]#(duo status)#(cpu) #(memory) #[bg=default]#(battery) #[fg=#a9b1d6,bg=default,nobold,noitalics]#(forecast) #[fg=#daeafa,nobold]%H:%M #[bg=default]'
            set -g window-status-current-style 'fg=#89ddff,bg=default'
            set -g window-status-format '#[fg=#5c626e,bg=default,italics]#I: #[fg=#5c626e,bg=default,noitalics,bold]#W#[fg=#2b2a30,bg=default] '
            set -g window-status-current-format '#[fg=#ae81ff,bg=default,]#[italics]#I: #[fg=#dfdcd8,bg=default]#[bold,noitalics]#W#[fg=#2b2a30,bg=default] '
            set -g window-status-last-style 'fg=#a9b1d6,bg=default'
            set -g window-status-activity-style 'fg=#9ece6a,bg=default'
            set -g pane-border-style 'fg=#b4befe'
            set -g pane-active-border-style 'fg=#b4befe'
            set -g message-command-style "bg=default,fg=#a9b1d6"
            set -g message-style "bg=default,fg=#a9b1d6"
            set -g mode-style "bg=#292e42"


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
