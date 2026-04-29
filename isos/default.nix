# isos/default.nix
{
  pkgs,
  inputs,
  ...
}: let
  isoConfig = inputs.nixpkgs.lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    specialArgs = {inherit inputs;};
    modules = [
      inputs.sops-nix.nixosModules.sops
      ./system.nix
      ./installer-workarounds.nix
      ./gnome-graphical.nix
    ];
  };
in {
  gnome-iso = isoConfig.config.system.build.isoImage;
}
