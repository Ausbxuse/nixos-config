# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./disk.nix
    ./hardware-configuration.nix
    ./power.nix
    ../../modules/common/system/minimal-gui.nix
    ../../modules/nixos/hardware/nvidia.nix
    ../../modules/nixos/grub.nix
    ../../modules/nixos/silent-boot.nix
    ../../modules/nixos/vm.nix
    ../../modules/nixos/gui/gaming.nix
  ];

  my.hardware.nvidia.enable = true;
  services.xserver.videoDrivers = ["modesetting"];

  # Optional boot profile without NVIDIA enabled.
  specialisation.nonvidia.configuration = {
    my.hardware.nvidia.enable = lib.mkForce false;
  };

  environment.systemPackages = with pkgs; [
    sof-firmware
  ];
}
