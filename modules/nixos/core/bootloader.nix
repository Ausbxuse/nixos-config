{
  hostDef,
  lib,
  pkgs,
  inputs,
  ...
}: let
  installDef = hostDef.install or {};
in {
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  boot.loader = {
    systemd-boot.enable = false;
    efi = {
      canTouchEfiVariables = lib.mkDefault (installDef.canTouchEfiVariables or true);
      efiSysMountPoint = "/boot"; # ← use the same mount point here.
    };
    grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = lib.mkDefault (installDef.efiInstallAsRemovable or false);
      useOSProber = true;
      # Keep the EFI partition from filling up with old kernel/initrd copies.
      configurationLimit = 1;
      # enableCryptodisk= true;
      #efiInstallAsRemovable = true; # in case canTouchEfiVariables doesn't work for your system
      device = "nodev";
    };
  };
}
