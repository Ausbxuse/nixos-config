{lib, ...}: {
  # Keep the live installer focused on storage/network setup. Some recent Intel
  # SOF/SoundWire audio stacks can spam the console or hold udev workers during
  # hardware probing, which can make unrelated installer steps fail at
  # `udevadm settle`.
  boot.kernelParams = lib.mkAfter [
    "quiet"
    "loglevel=1"
    "udev.log_level=3"
    "module_blacklist=snd_sof_pci_intel_tgl,snd_sof_pci_intel_mtl,snd_sof_pci_intel_lnl,snd_sof_pci_intel_ptl,snd_sof_intel_hda_common,snd_sof_intel_hda,snd_soc_sof_sdw,soundwire_intel"
  ];

  boot.blacklistedKernelModules = [
    "snd_sof_pci_intel_tgl"
    "snd_sof_pci_intel_mtl"
    "snd_sof_pci_intel_lnl"
    "snd_sof_pci_intel_ptl"
    "snd_sof_intel_hda_common"
    "snd_sof_intel_hda"
    "snd_soc_sof_sdw"
    "soundwire_intel"
  ];
}
