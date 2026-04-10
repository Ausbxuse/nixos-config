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
      # Default to a firmware-independent EFI install path. Hosts can opt back
      # into NVRAM boot entry management if they need it.
      canTouchEfiVariables = lib.mkDefault (installDef.canTouchEfiVariables or false);
      efiSysMountPoint = "/boot"; # ← use the same mount point here.
    };
    grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = lib.mkDefault (installDef.efiInstallAsRemovable or true);
      # os-prober pulls in dmraid-based probing that is fragile in installer
      # environments and unnecessary for single-OS installs. Opt in per host.
      useOSProber = lib.mkDefault (installDef.useOSProber or false);
      # Keep the EFI partition from filling up with old kernel/initrd copies.
      configurationLimit = 1;
      # enableCryptodisk= true;
      #efiInstallAsRemovable = true; # in case canTouchEfiVariables doesn't work for your system
      device = "nodev";
    };
  };
}
