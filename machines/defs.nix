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
}
