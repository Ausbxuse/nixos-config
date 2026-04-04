# isos/default.nix
{
  pkgs,
  inputs,
  nixosConfigurations,
  ...
}: let
  isoConfig = inputs.nixpkgs.lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    specialArgs = {
      inherit inputs nixosConfigurations;
    };
    modules = [
      inputs.sops-nix.nixosModules.sops
      ./system.nix
      ./gnome-graphical.nix
    ];
  };
in {
  gnome-iso = isoConfig.config.system.build.isoImage;
}
