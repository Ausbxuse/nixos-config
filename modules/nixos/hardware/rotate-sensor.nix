{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    iio-sensor-proxy
  ];

  hardware.sensor.iio.enable = true;
  services.dbus.packages = [pkgs.iio-sensor-proxy];
  systemd.packages = [pkgs.iio-sensor-proxy];
  systemd.services.iio-sensor-proxy.aliases = [
    "dbus-net.hadess.SensorProxy.service"
  ];
}
