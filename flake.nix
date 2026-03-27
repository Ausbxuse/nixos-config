{
  inputs = {
    grub2-theme.url = "github:vinceliuice/grub2-themes";
    minegrub.url = "github:Lxtharia/minegrub-theme";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
    bootstrap-keys = {
      url = "path:/home/zhenyu/.local/src/secrets";
      flake = false;
    };
    zsh-better-prompt = {
      url = "github:ausbxuse/zsh-better-prompt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    de = {
      url = "github:ausbxuse/de";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    inherit (nixpkgs) lib;

    const = import ./globals.nix;
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

    mkNixosWithHome = modules: hostname:
      nixpkgs.lib.nixosSystem {
        modules =
          modules
          ++ [
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager.users.${const.username} = import (./home + "/${hostname}");
              home-manager.extraSpecialArgs = {inherit inputs hostname const;};
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
          ];
        specialArgs = {inherit inputs hostname const;};
      };

    system = const.system;
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    minecraft = pkgs.callPackage ./pkgs/minecraft {};

    nixosHosts = lib.attrNames (builtins.readDir ./hosts);
    homeHosts = lib.attrNames (builtins.readDir ./home);
  in {
    templates = import ./templates;

    devShells.${system} = import ./shell.nix {inherit pkgs;};

    packages.${system} =
      (import ./isos {
        inherit pkgs inputs;
        nixosConfigurations = self.nixosConfigurations;
        seedHostNames = nixosHosts;
      })
      // {
        minecraftClient = minecraft.mrpack;
        minecraftDeploy = minecraft.deploy;
        minecraftBootstrap = minecraft.bootstrap;
        minecraftSync = minecraft.sync;
      };

    apps.${system} = {
      minecraft = {
        type = "app";
        program = "${minecraft.sync}/bin/sync-minecraft-client";
      };
      "minecraft-bootstrap" = {
        type = "app";
        program = "${minecraft.bootstrap}/bin/bootstrap-minecraft-client";
      };
      "minecraft-deploy" = {
        type = "app";
        program = "${minecraft.deploy}/bin/deploy-minecraft-client";
      };
      default = {
        type = "app";
        program = "${minecraft.sync}/bin/sync-minecraft-client";
      };
    };

    checks.${system} = import ./tests {inherit pkgs lib;};

    nixosConfigurations = builtins.listToAttrs (map (host: {
        name = "${host}";
        value = mkNixosWithHome [./hosts/${host}] host;
      })
      nixosHosts);

    homeConfigurations = builtins.listToAttrs (map (host: {
        name = "${const.username}@" + host;
        value = mkHome [./home/${host}] pkgs host;
      })
      homeHosts);
  };
}
