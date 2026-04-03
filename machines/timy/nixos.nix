# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{inputs, ...}: {
  imports = [
    ./kernel.nix
    ../../modules/nixos/hardware/rotate-sensor.nix
  ];

  # nixpkgs.overlays = [(import ../../overlays/mutter.nix)]; # NOTE: gnome 47 fix, should be fixed in 49
}
