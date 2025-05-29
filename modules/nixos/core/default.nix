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
    ncdu
    lsof
    wget
    git
    which
    htop
    # pkg-config
    killall
    unzip
    # pass
  ];

  networking.hostName = "${hostname}";
  networking.networkmanager.enable = true;
  networking.firewall.enable = lib.mkDefault false;
}
