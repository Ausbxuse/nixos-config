{modulesPath, lib, ...}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = lib.mkAfter [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
  ];

  # QEMU in ~/src/public/vm/nix2 presents the target disk as vda. Using the
  # raw partition path avoids initrd waiting on a by-partlabel symlink that is
  # not appearing reliably early enough during boot there.
  boot.initrd.luks.devices.crypted.device = lib.mkForce "/dev/vda2";
}
