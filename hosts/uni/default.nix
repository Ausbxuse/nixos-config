# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{pkgs, ...}: {
  imports = [
    ./disk.nix
    ./hardware-configuration.nix
    ../../modules/common/system/minimal-gui.nix
    ../../modules/nixos/hardware/nvidia.nix
    ../../modules/nixos/grub.nix
    ../../modules/nixos/silent-boot.nix
    ../../modules/nixos/vm.nix
    ../../modules/nixos/gui/gaming.nix
  ];

  environment.systemPackages = with pkgs; [
    sof-firmware
  ];
}
