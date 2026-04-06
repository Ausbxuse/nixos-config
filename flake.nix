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
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Stub by default; override with --override-input nix-secrets <path-or-url>
    # for real builds. See secrets/nix-secrets/README.md.
    nix-secrets = {
      url = "path:./secrets/nix-secrets";
      flake = true;
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
    repo = import ./lib {
      inherit lib inputs nixpkgs const;
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

    apps = repo.forEachSystem ({system, ...}:
      import ./apps.nix {
        packages = self.packages.${system};
      });

    checks = repo.forEachSystem ({
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
      ) (repo.hostsForSystem system repo.nixosHosts));

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
