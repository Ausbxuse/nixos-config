# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  inputs,
  options,
  pkgs,
  lib,
  hostname,
  ...
}: {
  imports = [
    inputs.disko.nixosModules.disko
    ./env.nix
    ./nix.nix
    ./user.nix
    ./bootloader.nix
  ];
  system.stateVersion = "24.05";

  # time.timeZone = "US/Pacific";
  networking.timeServers = options.networking.timeServers.default ++ ["pool.ntp.org"];
  #services.automatic-timezoned.enable = true;
  i18n.defaultLocale = "en_US.UTF-8";

  services = {
    openssh = {
      enable = true;
      # settings.PasswordAuthentication = true;
    };
  };

  environment.localBinInPath = true;
  environment.systemPackages = with pkgs; [
    # ESSENTIALs
    cachix
    gcc
    rsync
    gnupg
    pciutils
    wirelesstools
    iw
    neovim
    gdu #ncdu alternative
    lsof
    wget
    git
    which
    htop
    # pkg-config
    killall
    unzip
    # pass
    # via
  ];

  networking.hostName = "${hostname}";
  networking.networkmanager.enable = true;
  networking.firewall.enable = lib.mkDefault false;
  # hardware.keyboard.qmk.enable = true;
  # services.udev = {
  #   packages = with pkgs; [
  #     qmk
  #     qmk-udev-rules # the only relevant
  #     qmk_hid
  #     via
  #     vial
  #   ]; # packages
  # }; # udev
}
