{
  lib,
  pkgs,
  const,
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
    ../../modules/nixos/hardware/tlp-laptop.nix
    ../../modules/nixos/hardware/rotate-sensor.nix
    ../../modules/nixos/ollama-agent.nix
  ];

  boot.kernelPackages = pkgs.linuxPackagesFor kernel;
  services.xserver.videoDrivers = ["modesetting" "nvidia"];
  boot.kernelParams = [
    "xe.enable_dpcd_backlight=1"
    # Hide the blinking VT cursor during the resume handoff back to GNOME.
    "vt.global_cursor_default=0"
  ];
  # hardware.nvidia.prime = {
  #   sync.enable = lib.mkForce true;
  #   offload.enable = lib.mkForce false;
  #   offload.enableOffloadCmd = lib.mkForce false;
  # }; # already set in nvidia.nix
  hardware.nvidia.powerManagement.enable = lib.mkForce true;
  hardware.nvidia.powerManagement.finegrained = lib.mkForce false;
  hardware.nvidia.dynamicBoost.enable = true;
  # Force mutter to use the NVIDIA GPU as primary renderer on Wayland.
  # Without this, mutter picks Intel (card0) and does a cross-GPU copy to
  # NVIDIA for HDMI output, causing periodic cursor lag.

  # Battery-friendly profile: offload rendering to iGPU, use dGPU on demand.
  hardware.nvidia.prime = {
    sync.enable = lib.mkForce false;
    offload.enable = lib.mkForce true;
    offload.enableOffloadCmd = lib.mkForce true;
  };

  # Select at boot from the systemd-boot menu.
  specialisation.docked.configuration = {
    # # Let mutter pick the default (Intel) primary GPU in offload mode.
    # TODO: make it only do so for external monitor. make internal monitor still rendered by intel

    services.udev.extraRules = ''
      SUBSYSTEM=="drm", ENV{DEVTYPE}=="drm_minor", ENV{DEVNAME}=="/dev/dri/card[0-9]", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x10de", TAG+="mutter-device-preferred-primary"
    '';
  };

  # Work around a Mutter/Intel Xe (Panther Lake) bug where the desktop
  # wallpaper texture is lost after s2idle resume, leaving a solid-colour
  # fallback.  A quick VT round-trip forces a full GPU redraw.
  # FIXME:
  # powerManagement.resumeCommands = ''
  #   ${pkgs.kbd}/bin/chvt 3
  #   sleep 1
  #   ${pkgs.kbd}/bin/chvt 2
  # '';

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

  hardware.openrazer.enable = true;
  hardware.openrazer.users = [const.username];
  users.users.${const.username}.linger = true;

  environment.systemPackages = with pkgs; [
    openrazer-daemon
    razergenie
  ];
}
