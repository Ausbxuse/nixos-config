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

          background = "#1a1b26";
          foreground = "#dfdcd8";
          cursor-color = "#dfdcd8";
          cursor-text = "#000000";
          # cursor-invert-fg-bg = true;
          selection-background = "#626880";
          selection-foreground = "#c6d0f5";
        };
        snappy_light = {
          palette = [
            "0=#2B2D33" # black (primary ink on light bg)
            "1=#D81E34" # red (errors, deletions)
            "2=#2E8B57" # green (success, additions)
            "3=#C47A00" # yellow/orange (warnings, highlights)
            "4=#0077CC" # blue (links, keywords, primary accents)
            "5=#D63384" # magenta (special, annotations)
            "6=#0E9BB7" # cyan (info, types, secondary accents)
            "7=#5B6272" # white (light-theme “white” becomes a dark-neutral for ANSI white text)

            "8=#8B93A7" # bright black (comments / muted)
            "9=#E02A3F" # bright red
            "10=#3A9B64" # bright green
            "11=#D18A12" # bright yellow/orange
            "12=#1487D6" # bright blue
            "13=#E14A96" # bright magenta
            "14=#19A9C5" # bright cyan
            "15=#1F2430" # bright white (highest-contrast “ink” for headings / strong emphasis)
          ];

          background = "#F7F6F3"; # warm paper: reduces glare vs pure white
          foreground = "#1F2430"; # main text (near-ink, not pure black)
          cursor-color = "#1F2430"; # visible against light background
          cursor-text = "#F7F6F3"; # invert inside cursor for legibility

          selection-background = "#D8DEEA"; # soft blue-gray highlight
          selection-foreground = "#1F2430"; # keep readable while selected
        };
      };
      settings = {
        theme = "dark:snappy,light:snappy_light";

        font-family = "JetBrainsMono NF";
        font-family-italic = "Operator Mono Book";
        font-size = 12;
        font-thicken = true;

        shell-integration-features = "no-cursor,no-sudo,title";
        cursor-style-blink = false;
        adjust-cursor-thickness = 2;
        cursor-style = "bar";

        # gtk-adwaita = false;
        resize-overlay = "never";

        window-decoration = false;
        background-opacity = 1;
        link-url = true;
      };
    };
  };
}
