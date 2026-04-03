# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{inputs, ...}: {
  imports = [
    ../../modules/profiles/nixos/minimal-gui.nix
  ];
}
