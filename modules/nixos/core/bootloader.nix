{
  lib,
  pkgs,
  inputs,
  ...
}: {
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  boot.loader = {
    systemd-boot.enable = false;
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot"; # ← use the same mount point here.
    };
    grub = {
      enable = true;
      efiSupport = true;
      useOSProber = true;
      # Keep the EFI partition from filling up with old kernel/initrd copies.
      configurationLimit = 1;
      # enableCryptodisk= true;
      #efiInstallAsRemovable = true; # in case canTouchEfiVariables doesn't work for your system
      device = "nodev";
    };
  };
}
