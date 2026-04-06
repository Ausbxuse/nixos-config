{
  config,
  lib,
  pkgs,
  ...
}: let
  hasBtrfs = lib.any (fs: fs.fsType == "btrfs") (builtins.attrValues config.fileSystems);
in {
  # Disk care (gated on presence of Btrfs filesystems)
  services.btrfs.autoScrub = lib.mkIf hasBtrfs {
    enable = true;
    interval = "weekly";
  };
  services.fstrim = {
    enable = true;
    interval = "weekly";
  };

  # Memory QoL
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  # Laptop-friendly defaults. Machines using TLP override these via
  # hardware/tlp-laptop.nix (which uses mkForce to beat both this and GNOME).
  services.auto-cpufreq.enable = lib.mkDefault true;
  services.power-profiles-daemon.enable = false;
  powerManagement.cpuFreqGovernor = lib.mkDefault "schedutil";
}
