{lib, ...}: {
  services.power-profiles-daemon.enable = false;
  services.auto-cpufreq.enable = lib.mkForce false;

  services.thermald.enable = true;
  powerManagement.powertop.enable = true;

  networking.networkmanager.wifi.powersave = true;
  hardware.bluetooth.powerOnBoot = false;

  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "schedutil";
      CPU_SCALING_GOVERNOR_ON_BAT = "schedutil";
      CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_power";
      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 1;
      PLATFORM_PROFILE_ON_AC = "balanced";
      PLATFORM_PROFILE_ON_BAT = "balanced";

      RUNTIME_PM_ON_AC = "on";
      RUNTIME_PM_ON_BAT = "auto";
      PCIE_ASPM_ON_AC = "default";
      PCIE_ASPM_ON_BAT = "default";

      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "on";
      USB_AUTOSUSPEND = 1;
      SOUND_POWER_SAVE_ON_BAT = 1;
    };
  };
}
