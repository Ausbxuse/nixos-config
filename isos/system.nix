{
  pkgs,
  lib,
  inputs,
  ...
}: {
  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
  };

  i18n.defaultLocale = "en_US.UTF-8";

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages32 = with pkgs; [libvdpau-va-gl vaapiVdpau];
  };

  networking.firewall = {
    enable = false;
  };

  system.stateVersion = "24.05";

  environment.etc."ssh/id_ed25519".source = "${inputs.bootstrap-keys}/id_ed25519";
}
