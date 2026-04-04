{
  modulesPath,
  pkgs,
  ...
}: {
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
  ];

  system.stateVersion = "24.05";

  networking.hostName = "nixos-installer-test";
  networking.firewall.enable = false;

  nix.settings.experimental-features = ["nix-command" "flakes"];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "yes";
    };
  };

  users.users.root.initialPassword = "nixos";
  users.users.zhenyu = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    initialPassword = "nixos";
  };
  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    bash
    curl
    git
    jq
    rsync
    gnugrep
    gnused
    gawk
    perl
    util-linux
    disko
    nixos-install-tools
  ];
}
