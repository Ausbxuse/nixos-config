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
    zsh-better-prompt = {
      url = "github:ausbxuse/zsh-better-prompt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    de = {
      url = "github:ausbxuse/de";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-secrets = {
      url = "path:./secrets/nix-secrets";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    inherit (nixpkgs) lib;

    const = import ./globals.nix;
    nix-secrets = inputs.nix-secrets;
    repo = import ./lib {
      inherit lib inputs nixpkgs const nix-secrets;
    };
  in {
    templates = import ./templates;

    devShells = repo.forEachSystem ({pkgs, ...}: {
      default = (import ./shell.nix {inherit pkgs;}).default;
    });

    packages = repo.forEachSystem ({pkgs, ...}:
      import ./pkgs {
        inherit lib pkgs self inputs const;
        inherit (repo) hostDefs nixosHosts;
        nixosConfigurations = self.nixosConfigurations;
      });

    apps = repo.forEachSystem ({system, ...}: let
      minecraft = self.packages.${system}.minecraftSync;
      bootstrap = self.packages.${system}.minecraftBootstrap;
      deploy = self.packages.${system}.minecraftDeploy;
    in {
      minecraft = {
        type = "app";
        program = "${minecraft}/bin/sync-minecraft-client";
      };
      "minecraft-bootstrap" = {
        type = "app";
        program = "${bootstrap}/bin/bootstrap-minecraft-client";
      };
      "minecraft-deploy" = {
        type = "app";
        program = "${deploy}/bin/deploy-minecraft-client";
      };
      "validate-host" = {
        type = "app";
        program = "${self.packages.${system}."validate-host"}/bin/validate-host";
      };
      install = {
        type = "app";
        program = "${self.packages.${system}.install}/bin/install-config";
      };
      "ubuntu-home-install-test" = {
        type = "app";
        program = "${self.packages.${system}."ubuntu-home-install-test"}/bin/ubuntu-home-install-test";
      };
      default = {
        type = "app";
        program = "${minecraft}/bin/sync-minecraft-client";
      };
    });

    checks = repo.forEachSystem (
      {
        system,
        pkgs,
      }:
        (import ./tests {inherit pkgs lib;})
        // lib.optionalAttrs (system == "x86_64-linux") {
          nvim = self.packages.${system}.nvim;
          inherit (self.packages.${system}) gnome-iso;
        }
        // repo.mkChecks "home" (
          host: (repo.mkHome host).activationPackage
        ) (repo.hostsForSystem system repo.homeHosts)
        // repo.mkChecks "nixos" (
          host: (repo.mkNixosWithHome host).config.system.build.toplevel
        ) (repo.hostsForSystem system repo.nixosHosts)
    );

    nixosConfigurations =
      repo.mkNamedAttrs
      (host: host)
      (host: repo.mkNixosWithHome host)
      repo.nixosHosts;

    homeConfigurations =
      repo.mkNamedAttrs
      (host: "${repo.userFor host}@${host}")
      (host: repo.mkHome host)
      repo.homeHosts;
  };
}
