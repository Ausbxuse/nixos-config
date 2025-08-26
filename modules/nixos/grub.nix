{
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    # inputs.grub2-theme.nixosModules.default
    inputs.minegrub.nixosModules.default
  ];

  # boot.loader = {
  #   grub2-theme = {
  #     enable = false;
  #     screen = "4k";
  #   };
  # };

  boot.loader.grub.minegrub-theme = {
    enable = true;
    splash = "Welcome to the End"; # your custom splash text
    boot-options-count = 4; # if you have 6 entries in your menu
  };
}
