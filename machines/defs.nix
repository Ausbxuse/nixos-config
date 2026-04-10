{
  lib,
  const,
  ...
}: {
  # Public staging registry for hosts that have not been admitted into the
  # private trust mesh yet. Canonical admitted host definitions live in the
  # private nix-secrets checkout at hosts.nix.

  nix2 = {
    system = "x86_64-linux";
    username = const.username;
    nixos = {
      enable = true;
      profile = "minimal";
    };
    install = {
      layout = "luks-btrfs";
      disk = "/dev/vda";
      swapSize = "8G";
      canTouchEfiVariables = false;
      efiInstallAsRemovable = true;
    };
    platform = "custom";
    visibility = "private";
  };
}
