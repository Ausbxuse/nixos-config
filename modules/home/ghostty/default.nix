{
  config,
  lib,
  pkgs,
  ...
}: {
  programs = {
    ghostty = {
      # TODO: finish configs
      enable = true;
    };
  };

  home.activation.installGhosttyConfigs = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.rsync}/bin/rsync -avz --chmod=D2755,F744 ${./ghostty}/ ${config.xdg.configHome}/ghostty/
  '';

  # home.file."${config.xdg.configHome}/ghostty/config" = {
  #   text = ''
  #     palette = 0=#444444
  #     palette = 1=#ff2740
  #     palette = 2=#9ece6a
  #     palette = 3=#f4bf75
  #     palette = 4=#4fc1ff
  #     palette = 5=#fc317e
  #     palette = 6=#62d8f1
  #     palette = 7=#a5adce
  #     palette = 8=#626880
  #     palette = 9=#ff2740
  #     palette = 10=#93c36a
  #     palette = 11=#f4bf75
  #     palette = 12=#4fc1ff
  #     palette = 13=#fc317e
  #     palette = 14=#62d8f1
  #     palette = 15=#b5bfe2
  #
  #     background = #121212
  #     foreground = #dfdcd8
  #     cursor-color = #dfdcd8
  #     cursor-text = #000000
  #     # cursor-invert-fg-bg = true
  #     selection-background = #626880
  #     selection-foreground = #c6d0f5
  #
  #     font-family = JetBrainsMono NF
  #     font-family-italic = Operator Mono Book
  #     font-size = 11
  #     font-thicken = true
  #
  #     shell-integration-features = no-cursor,no-sudo,title
  #     cursor-style-blink = false
  #     adjust-cursor-thickness = 2
  #     cursor-style = bar
  #     gtk-adwaita = false
  #
  #     window-decoration = false
  #     background-opacity = 0.7
  #   '';
  #   executable = false;
  # };
}
