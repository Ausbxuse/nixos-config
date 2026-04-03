{
  ...
}: {
  imports = [
    ../../nixos/hardware/nvidia.nix
  ];

  my.hardware.nvidia.enable = true;
}
