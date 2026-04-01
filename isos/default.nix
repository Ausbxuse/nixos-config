# isos/default.nix
{
  pkgs,
  inputs,
  bootstrap-keys,
  ...
}: {
  gnome-iso = inputs.nixos-generators.nixosGenerate {
    system = pkgs.stdenv.hostPlatform.system;
    format = "iso";
    customFormats = {iso = import ./gnome-graphical.nix;};

    specialArgs = {
      inherit inputs bootstrap-keys;
    };

    modules = [
      inputs.sops-nix.nixosModules.sops
      ./system.nix
    ];
  };
}
