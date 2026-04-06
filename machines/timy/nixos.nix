# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{inputs, ...}: {
  imports = [
    ./kernel.nix
    ../../modules/nixos/hardware/rotate-sensor.nix
  ];
}
