{
  config,
  lib,
  pkgs,
  ...
}: let
  hasBtrfs = lib.any (fs: fs.fsType == "btrfs") (builtins.attrValues config.fileSystems);
in {
  # CLI helpers and nicer rebuild UX
  programs.nix-index.enable = true;
  programs.nix-index-database.comma.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  environment.systemPackages = with pkgs; [
    nh
    nvd
    nix-output-monitor
  ];
  #    - Point your just recipes at nh os switch -- --flake .#${HOST} (and nh home switch -- --flake .#${USER}@${HOST}) so you get nom logs and nice diffs automatically.
  #  - Use nvd diff /run/current-system ./result (or nh os diff) before switching to catch surprises.
  #  - With nix-index + comma, you can run commands you don’t have installed as , <cmd> and they’re fetched on the fly.
  #

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

  # Laptop-friendly defaults
  services.auto-cpufreq.enable = true;
  services.power-profiles-daemon.enable = false; # avoid conflicts with auto-cpufreq
  powerManagement.cpuFreqGovernor = lib.mkDefault "schedutil";
}
