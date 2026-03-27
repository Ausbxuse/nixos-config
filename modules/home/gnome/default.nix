{pkgs, ...}: {
  imports = [
    ./dconf.nix
  ];

  systemd.user.services.tmux-theme-watch = {
    Unit = {
      Description = "Reload tmux theme on GNOME color-scheme changes";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "%h/.local/bin/tmux/theme-watch.sh";
      Restart = "always";
      RestartSec = 1;
    };
    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };

  systemd.user.services.gnome-monitor-profile = {
    Unit = {
      Description = "Apply GNOME monitor profile";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "%h/.local/bin/gnome/apply-monitor-profile.sh";
    };
    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };

  home.file.".local/bin/tmux/theme-watch.sh" = {
    source = ../tmux/theme-watch.sh;
    executable = true;
  };

  home.file.".local/bin/gnome/apply-monitor-profile.sh" = {
    text = ''
      #!/usr/bin/env bash
      set -eu

      # Wait for GNOME display stack to settle after login/resume.
      sleep 2

      GMC='${pkgs.gnome-monitor-config}/bin/gnome-monitor-config'

      monitors="$($GMC list 2>/dev/null || true)"
      if ! printf '%s\n' "$monitors" | grep -Fq 'Monitor [ eDP-1 ] ON'; then
        exit 0
      fi
      if ! printf '%s\n' "$monitors" | grep -Fq 'Monitor [ HDMI-1 ] ON'; then
        exit 0
      fi

      $GMC set --logical-layout-mode \
        -L -M eDP-1 -m '3840x2160@120.043' -x 0 -y 0 -s 3 -t normal \
        -L -M HDMI-1 -m '3840x2160@143.982' -x 1280 -y 0 -s 2 -t normal -p
    '';
    executable = true;
  };

  home.packages = with pkgs; [
    capitaine-cursors
    # pinentry
    gnome-shell-extensions
    gnome-monitor-config
    networkmanager-openvpn
    # gnome-extension-manager
    gnome-tweaks
    gnomeExtensions.astra-monitor
    # gnomeExtensions.colortint
    gnomeExtensions.media-controls
    # gnomeExtensions.gnome-bedtime
    gnomeExtensions.night-light-slider-updated
    # gnomeExtensions.hide-cursor
    gnomeExtensions.unite
    gnomeExtensions.blur-my-shell
    gnomeExtensions.forge
    gnomeExtensions.gsconnect
    gnomeExtensions.caffeine
    # gnomeExtensions.coverflow-alt-tab
    gnomeExtensions.color-picker
    gnomeExtensions.bluetooth-battery-meter
    # gnomeExtensions.just-perfection
    gnomeExtensions.status-area-horizontal-spacing
    gnomeExtensions.no-overview
    gnomeExtensions.another-window-session-manager
    gnomeExtensions.rounded-window-corners-reborn
    amberol
    powertop
    xiccd
    moreutils
    gnome-graphs
    loupe
    mpv
  ];
}
