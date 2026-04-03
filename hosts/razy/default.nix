{
  lib,
  pkgs,
  ...
}: let
  kernel = pkgs.linux_latest.override {
    kernelPatches = with pkgs.linuxKernel.kernelPatches; [
      bridge_stp_helper
      request_key_helper
      {
        name = "ptl-razer-blade16-rt721-rt1320";
        patch = ./patches/ptl-razer-blade16-rt721-rt1320.patch;
      }
    ];
  };
in {
  imports = [
    ./disk.nix
    ./hardware-configuration.nix
    ./power.nix
    ../../modules/common/system/minimal-gui.nix
    ../../modules/nixos/hardware/nvidia.nix
    ../../modules/nixos/grub.nix
    ../../modules/nixos/silent-boot.nix
    ../../modules/nixos/vm.nix
    ../../modules/nixos/gui/gaming.nix
  ];

  my.hardware.nvidia.enable = true;
  boot.kernelPackages = pkgs.linuxPackagesFor kernel;
  services.xserver.videoDrivers = ["modesetting" "nvidia"];
  boot.kernelParams = ["xe.enable_dpcd_backlight=1"];
  hardware.nvidia.prime = {
    sync.enable = lib.mkForce false;
    offload.enable = lib.mkForce true;
    offload.enableOffloadCmd = lib.mkForce true;
  };
  hardware.nvidia.powerManagement.finegrained = lib.mkForce false;

  hardware.firmware = with pkgs; [
    linux-firmware
    sof-firmware
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/gdm/.config 0755 gdm gdm -"
  ];

  system.activationScripts.razy-gdm-monitors = lib.stringAfter ["users" "groups"] ''
    install -d -m 0755 -o gdm -g gdm /var/lib/gdm/.config
    install -m 0644 -o gdm -g gdm ${./gdm-monitors.xml} /var/lib/gdm/.config/monitors.xml
  '';
}
