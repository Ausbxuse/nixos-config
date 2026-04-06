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
    syncthing.introducer = true;
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
    syncthing.deviceId = "KHY3QCB-3R2BQH6-IMRBWKK-BWHJWSL-66UOSKY-ZJQR3HL-GYHJJ4G-4ALAMAB";
    sops.ageKey = "age12y842jk5ad5lecjuh3s4edlqxffmcmh7lzzkfm39vwl2kfckw3rszewkrm";
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
      disk = "/dev/vda";
      swapSize = "2G";
    };

    system = "x86_64-linux";
    username = const.username;
    platform = "custom";
    visibility = "private";
  };

  newbie = {
    syncthing.deviceId = "J3KIR3G-DW4RV3M-NVPU67N-E6PUS3O-R3JEKOG-BXUU5P3-TVC36PQ-VLIVWQF";
    sops.ageKey = "age1u7r90dr7hpu0kvawsr9lgw89gahklce4ptafsccmp3hgcv7nme3q0q3unp";
    system = "x86_64-linux";
    username = const.username;
    platform = "custom";
    visibility = "private";
  };
}
