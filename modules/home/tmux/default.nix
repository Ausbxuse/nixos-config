{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.tmux = {
    enable = true;
  };

  home.packages = with pkgs; [
    lm_sensors
  ];

  # home.activation.installTmux = lib.hm.dag.entryAfter ["writeBoundary"] ''
  #   ${pkgs.rsync}/bin/rsync -avz --chmod=D2755,F744 ${./tmux}/ ${config.xdg.configHome}/tmux/
  # '';

  programs.tmux = {
    extraConfig = builtins.readFile ./tmux.conf;
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
        plugin = prefix-highlight;
        extraConfig = ''

          set -g @prefix_highlight_show_copy_mode 'on'
          set -g @prefix_highlight_copy_mode_attr 'fg=#f4bf75,bg=default,bold' # default is 'fg=default,bg=yellow'
          set -g @prefix_highlight_show_sync_mode 'on'
          set -g @prefix_highlight_sync_mode_attr 'fg=black,bg=green' # default is 'fg=default,bg=yellow'

          set -g @prefix_highlight_fg '#62d8f1' # default is 'colour231'
          set -g @prefix_highlight_bg 'default'  # default is 'colour04'
          set -g @prefix_highlight_empty_prompt ' #[fg=#9ece6a,bg=default,bold]TMUX '
          set -g @prefix_highlight_prefix_prompt '#[bold]PREV'
          set -g @prefix_highlight_copy_prompt '#[bold]COPY'
          set -g @prefix_highlight_sync_prompt '#[bold]SYNC'
        '';
      }
      {
        plugin = fingers;
        extraConfig = ''
          set -g @fingers-key y
        '';
      }
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
