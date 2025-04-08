{pkgs, ...}: {
  imports = [
    ./dconf.nix
  ];

  home.packages = with pkgs; [
    # pinentry
    gnome-shell-extensions
    networkmanager-openvpn
    # gnome-extension-manager
    gnome-tweaks
    gnomeExtensions.astra-monitor
    # gnomeExtensions.colortint
    gnomeExtensions.media-controls
    # gnomeExtensions.gnome-bedtime
    gnomeExtensions.night-light-slider-updated
    gnomeExtensions.hide-cursor
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
    amberol
    powertop
    xiccd
    moreutils
    gnome-graphs
    mpv
  ];
}
