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
      typing-booster-unwrapped
    ];
  };
}
