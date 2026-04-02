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

  # With the current MUX setting, the internal panel is not reachable through
  # the Intel path alone. Keep a low-power NVIDIA profile instead of an
  # Intel-only profile that boots to a black screen.
  specialisation.nonvidia.configuration = {
    my.hardware.nvidia.enable = lib.mkForce true;
    services.xserver.videoDrivers = lib.mkForce ["nvidia"];
  };

  environment.systemPackages = with pkgs; [
    sof-firmware
  ];
}
