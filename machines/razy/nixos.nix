{
  config,
  lib,
  pkgs,
  const,
  inputs,
  ...
}: let
  pkgs619 = import inputs.nixpkgs619 {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
    config.nvidia.acceptLicense = true;
  };
  kernel619 = pkgs619.linux_6_19.override {
    kernelPatches = with pkgs619.linuxKernel.kernelPatches; [
      bridge_stp_helper
      request_key_helper
      {
        name = "ptl-razer-blade16-rt721-rt1320";
        patch = ./patches/ptl-razer-blade16-rt721-rt1320.patch;
      }
    ];
  };
  kernelPackages619 = pkgs.linuxPackagesFor kernel619;
in {
  imports = [
    ../../modules/nixos/hardware/tlp-laptop.nix
    ../../modules/nixos/hardware/rotate-sensor.nix
    ../../modules/nixos/ollama-agent.nix
  ];

  boot.kernelPackages = kernelPackages619;
  services.xserver.videoDrivers = ["modesetting" "nvidia"];
  boot.kernelParams = [
    # # This platform can hang before resume from s2idle. Prefer S3/deep sleep.
    # "mem_sleep_default=deep"
    # Hide the blinking VT cursor during the resume handoff back to GNOME.
    "xe.enable_dpcd_backlight=1"
    "vt.global_cursor_default=0"
  ];
  # hardware.nvidia.prime = {
  #   sync.enable = lib.mkForce true;
  #   offload.enable = lib.mkForce false;
  #   offload.enableOffloadCmd = lib.mkForce false;
  # }; # already set in nvidia.nix

  # Try NVIDIA 595+ suspend notifiers to avoid the old nvidia-sleep.sh path,
  # which switches to VT 63 during suspend/resume. Revert these two lines to
  # go back to the previous driver/service behavior:
  #   hardware.nvidia.package = lib.mkForce config.boot.kernelPackages.nvidiaPackages.new_feature;
  #   hardware.nvidia.powerManagement.kernelSuspendNotifier = lib.mkForce false;
  hardware.nvidia.package = lib.mkForce config.boot.kernelPackages.nvidiaPackages.production;
  hardware.nvidia.powerManagement.enable = lib.mkForce true;
  hardware.nvidia.powerManagement.finegrained = lib.mkForce true;
  hardware.nvidia.powerManagement.kernelSuspendNotifier = lib.mkForce true;
  hardware.nvidia.dynamicBoost.enable = true;

  # BIOS 2.01 still exposes broken INTC10D6 fan status devices:
  # reading TFN1/TFN2 cur_state calls \_SB.DPTF.GFNS, which fails on
  # \_SB.PC00.LPCB.HEC.RCFS and spams the kernel log. Keep the normal
  # PNP0C0B fan devices bound; only hide the broken status devices from
  # userspace pollers such as thermald.
  systemd.services.razy-unbind-broken-acpi-fan-status = {
    description = "Unbind broken Razer ACPI fan status devices";
    before = ["thermald.service"];
    requiredBy = ["thermald.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      driver=/sys/bus/platform/drivers/acpi-fan
      for device in INTC10D6:00 INTC10D6:01; do
        if [ -e "$driver/$device" ]; then
          echo "$device" > "$driver/unbind" || true
        fi
      done
    '';
  };

  # Force mutter to use the NVIDIA GPU as primary renderer on Wayland.
  # Without this, mutter picks Intel (card0) and does a cross-GPU copy to
  # NVIDIA for HDMI output, causing periodic cursor lag.

  # Battery-friendly profile: offload rendering to iGPU, use dGPU on demand.
  hardware.nvidia.prime = {
    sync.enable = lib.mkForce false;
    offload.enable = lib.mkForce true;
    offload.enableOffloadCmd = lib.mkForce true;
  };

  # Select at boot from the grub menu.
  specialisation.docked.configuration = {
    # # Let mutter pick the default (Intel) primary GPU in offload mode.
    # TODO: make it only do so for external monitor. make internal monitor still rendered by intel

    services.udev.extraRules = ''
      SUBSYSTEM=="drm", ENV{DEVTYPE}=="drm_minor", ENV{DEVNAME}=="/dev/dri/card[0-9]", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x10de", TAG+="mutter-device-preferred-primary"
    '';
  };

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
