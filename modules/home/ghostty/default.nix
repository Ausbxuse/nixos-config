{...}: {
  programs = {
    ghostty = {
      enable = true;
      themes = {
        snappy = {
          palette = [
            "0=#444444"
            "1=#ff2740"
            "2=#9ece6a"
            "3=#f4bf75"
            "4=#4fc1ff"
            "5=#fc317e"
            "6=#62d8f1"
            "7=#a5adce"
            "8=#626880"
            "9=#ff2740"
            "10=#93c36a"
            "11=#f4bf75"
            "12=#4fc1ff"
            "13=#fc317e"
            "14=#62d8f1"
            "15=#b5bfe2"
          ];

          background = "#121212";
          foreground = "#dfdcd8";
          cursor-color = "#dfdcd8";
          cursor-text = "#000000";
          # cursor-invert-fg-bg = true;
          selection-background = "#626880";
          selection-foreground = "#c6d0f5";
        };
      };
      settings = {
        theme = "snappy";

        font-family = "JetBrainsMono NF";
        font-family-italic = "Operator Mono Book";
        font-size = 10;
        font-thicken = true;

        shell-integration-features = "no-cursor,no-sudo,title";
        cursor-style-blink = false;
        adjust-cursor-thickness = 2;
        cursor-style = "bar";

        gtk-adwaita = false;
        resize-overlay = "never";

        window-decoration = false;
        background-opacity = 0.7;
        link-url = true;
      };
    };
  };
}
