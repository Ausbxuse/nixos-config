# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{inputs, ...}: {
  imports = [
    ./kernel.nix
    ./hardware-configuration.nix
    ./disk.nix
    ../../modules/common/system/minimal-gui.nix
    ../../modules/nixos/grub.nix
    ../../modules/nixos/silent-boot.nix
    ../../modules/nixos/hardware/rotate-sensor.nix
    ../../modules/nixos/vm.nix
    ../../modules/nixos/gui/gaming.nix
  ];

  # nixpkgs.overlays = [(import ../../overlays/mutter.nix)]; # NOTE: gnome 47 fix, should be fixed in 49
}
