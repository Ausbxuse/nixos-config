# isos/default.nix
{
  pkgs,
  inputs,
  ...
}: {
  gnome-iso = inputs.nixos-generators.nixosGenerate {
    system = pkgs.system;
    format = "iso";
    customFormats = {iso = import ./gnome-graphical.nix;};

    specialArgs = {
      inherit inputs;
    };

    modules = [
      inputs.sops-nix.nixosModules.sops
      ./system.nix
    ];
  };
}
