{pkgs, ...}: {
  environment.systemPackages = with pkgs;
    [
      # Hardware
      usbutils
    ]
    ++ [
    ];

  services.udev.extraRules = ''
    # MANUS HIDAPI/libusb
    SUBSYSTEM=="usb", ATTR{idVendor}=="3325", MODE:="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="1915", ATTR{idProduct}=="83fd", MODE:="0666"

    # MANUS HIDAPI/hidraw
    KERNEL=="hidraw*", ATTRS{idVendor}=="3325", MODE:="0666"
  '';
}
