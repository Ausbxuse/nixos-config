{
  pkgs,
  lib,
  inputs,
  ...
}: {
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = ["nix-command" "flakes"];

  i18n.defaultLocale = "en_US.UTF-8";

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # services.xserver.videoDrivers = ["amd" "nvidia"];

  networking = {
    hostName = "nixos-iso";
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages32 = with pkgs; [libvdpau-va-gl vaapiVdpau];
  };

  services.logind = {
    settings.Login.HandleLidSwitch = "suspend";
  };

  networking.firewall = {
    enable = false;
    # allowedTCPPorts = [80 8080];
  };

  system.stateVersion = "24.05";

  environment.etc."age/keys.txt".source = "${inputs.bootstrap-keys}/age.txt";
  environment.etc."ssh/id_ed25519".source = "${inputs.bootstrap-keys}/id_ed25519";

  sops.age.keyFile = "/etc/age/keys.txt";
}
