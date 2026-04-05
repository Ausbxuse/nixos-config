{
  lib,
  const,
  ...
}: {
  earthy = {
    system = "x86_64-linux";
    username = const.username;
    platform = "portable-home";
    visibility = "private";
    home = {
      enable = true;
    };
  };

  razy = {
    system = "x86_64-linux";
    username = const.username;
    platform = "razer-blade";
    visibility = "private";
    sops.ageKey = "age1urr0n9fj9wml5n9act8nh6tlp9zjd3p9jyygsk68ux5lahfwsshsq5pl5h";
    # Syncthing device identity — null until bootstrap runs (see
    # docs/reproducing-from-scratch.md §"Phase F: vault bootstrap").
    # When set, modules/home/syncthing.nix pins cert/key via sops.
    syncthing.deviceId = null;
    home = {
      enable = true;
      profile = "personal-gnome";
      displayProfile = "razy-current";
    };
    nixos = {
      enable = true;
      profile = "portable-nvidia-gnome";
    };
    install = {
      layout = "luks-btrfs";
      disk = "/dev/nvme0n1";
      swapSize = "32G";
    };
  };

  spacy = {
    system = "x86_64-linux";
    username = const.username;
    platform = "desktop";
    visibility = "public";
    home = {
      enable = true;
    };
    nixos = {
      enable = true;
    };
    install = {
      layout = "luks-btrfs";
      swapSize = "20M";
    };
  };

  timy = {
    system = "x86_64-linux";
    username = const.username;
    platform = "asus-zenbook-duo-2024";
    visibility = "private";
    home = {
      enable = true;
      profile = "personal-gnome";
      displayProfile = "gnome-default";
    };
    nixos = {
      enable = true;
      profile = "portable-gnome";
    };
    install = {
      layout = "luks-btrfs";
      swapSize = "20M";
    };
  };

  uni = {
    system = "x86_64-linux";
    username = const.username;
    platform = "alienware-x17-r1";
    visibility = "private";
    home = {
      enable = true;
      profile = "personal-gnome";
      displayProfile = "gnome-default";
    };
    nixos = {
      enable = true;
      profile = "portable-nvidia-gnome";
    };
    install = {
      layout = "luks-btrfs";
      disk = "/dev/nvme1n1";
      swapSize = "32G";
    };
  };

  NEWHOST = {
    home = {
      enable = true;
      profile = "personal-gnome";
      displayProfile = "gnome-default";
    };
    nixos = {
      enable = true;
      profile = "portable-nvidia-gnome";
    };
    install = {
      layout = "luks-btrfs";
      disk = "/dev/vda";
      swapSize = "2G";
    };

    syncthing.deviceId = "ZQ7MCCP-U3YSPJM-ISXBFLT-2BAS7K3-SNZTNHZ-LJEZ42N-LD3N2N2-H2W3PA6";
    sops.ageKey = "age1naw7wgtrszdschtjm34hqy28f99k67ryffvpkgrk8f7apw6zxcgs6rey0k";
    system = "x86_64-linux";
    username = const.username;
    platform = "ad-hoc";
    visibility = "private";
  };
}
