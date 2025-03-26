{
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.grub2-theme.nixosModules.default
  ];

  boot.loader = {
    grub2-theme = {
      enable = true;
      screen = "4k";
    };
  };
}
