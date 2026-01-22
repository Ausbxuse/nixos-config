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

  home.file.".local/bin/tmux/theme-watch.sh" = {
    source = ../tmux/theme-watch.sh;
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
    gnomeExtensions.runcat
    gnomeExtensions.bluetooth-battery-meter
    # gnomeExtensions.just-perfection
    gnomeExtensions.status-area-horizontal-spacing
    gnomeExtensions.no-overview
    gnomeExtensions.another-window-session-manager
    amberol
    powertop
    xiccd
    moreutils
    gnome-graphs
    mpv
  ];
}
