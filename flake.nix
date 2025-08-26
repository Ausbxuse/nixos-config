{
  inputs = {
    grub2-theme.url = "github:vinceliuice/grub2-themes";
    minegrub.url = "github:Lxtharia/minegrub-theme";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    wallpapers.url = "github:ausbxuse/wallpapers";
    stardict.url = "github:ausbxuse/stardict";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";

      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-secrets = {
      url = "git+ssh://git@zhenyuzhao.com/var/lib/git-server/nix-secrets";
      flake = false;
    };
  };

  outputs = {nixpkgs, ...} @ inputs: let
    inherit (nixpkgs) lib;

    const = import ./constants.nix;
    mkNixos = modules: hostname:
      nixpkgs.lib.nixosSystem {
        inherit modules;
        specialArgs = {inherit inputs hostname const;};
      };

    mkHome = modules: pkgs: hostname:
      inputs.home-manager.lib.homeManagerConfiguration {
        inherit modules pkgs;
        extraSpecialArgs = {inherit inputs hostname const;};
      };

    system = const.system;
    pkgs = import nixpkgs {inherit system;};

    nixosHosts = lib.attrNames (builtins.readDir ./hosts);
    homeHosts = lib.attrNames (builtins.readDir ./home);
  in {
    templates = import ./templates;

    devShells.${system} = import ./shell.nix {inherit pkgs;};

    packages.${system} = import ./isos {inherit pkgs inputs;};

    nixosConfigurations = builtins.listToAttrs (map (host: {
        name = host;
        value = mkNixos [./hosts/${host}] host;
      })
      nixosHosts);

    homeConfigurations = builtins.listToAttrs (map (host: {
        name = "${const.username}@" + host;
        value = mkHome [./home/${host}] pkgs host;
      })
      homeHosts);
  };
}
