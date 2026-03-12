{pkgs, ...}: {
  imports = [
    ./minimal.nix
    ../../nixos/gui/gnome.nix
    ../../nixos/keyd.nix
    ../../nixos/hardware/sound.nix
    ../../nixos/hardware/printing.nix
    ../../nixos/hardware/usb.nix
  ];
  environment.systemPackages = with pkgs; [
    openvpn
  ];

  i18n.inputMethod = {
    enable = true;
    type = "ibus";
    ibus.engines = with pkgs.ibus-engines; [
      libpinyin
      # Disabled: typing-booster-unwrapped caused ~25s GNOME login stalls here by
      # delaying IBus readiness, which also delayed org.gnome.Shell.Screencast,
      # xdg-desktop-portal, Ghostty startup, and hid GNOME screen recording.
      # typing-booster-unwrapped
    ];
  };
}
