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
    nixpkgs,
    ...
  } @ inputs: let
    inherit (nixpkgs) lib;

    publicConst = import ./globals.nix;
    privateConstPath = inputs.nix-secrets + "/globals.nix";
    privateConst =
      if builtins.pathExists privateConstPath
      then import privateConstPath
      else {};
    const = lib.recursiveUpdate publicConst privateConst;
    adminAccessPath = inputs.nix-secrets + "/admin-access.nix";
    adminAccess =
      if builtins.pathExists adminAccessPath
      then import adminAccessPath
      else {};
    repo = import ./lib {
      inherit lib inputs nixpkgs const adminAccess;
    };
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
    # Keep install media out of the default package/app surfaces so common
    # flake queries do not pay for image evaluation.
    images = lib.optionalAttrs (builtins.elem "x86_64-linux" repo.supportedSystems) {
      x86_64-linux = import ./isos {
        pkgs = repo.pkgsFor "x86_64-linux";
        inherit inputs;
      };
    };
    packages = repo.forEachSystem ({pkgs, ...}:
      import ./pkgs {
        inherit lib pkgs const;
        inherit (repo) hostDefs;
      });
    apps = repo.forEachSystem ({system, ...}:
      import ./apps.nix {
        packages = packages.${system};
      });
    checks = repo.forEachSystem ({
      system,
      pkgs,
    }: let
      systemPackages = packages.${system};
    in
      (import ./tests {inherit pkgs lib;})
      // lib.optionalAttrs (system == "x86_64-linux") {inherit (systemPackages) nvim;}
      // repo.mkChecks "home" (
        host: homeConfigurations."${repo.userFor host}@${host}".activationPackage
      ) (repo.hostsForSystem system repo.homeHosts)
      // repo.mkChecks "nixos" (
        host: nixosConfigurations.${host}.config.system.build.toplevel
      ) (repo.hostsForSystem system repo.nixosHosts));
  in {
    templates = import ./templates;

    devShells = repo.forEachSystem ({pkgs, ...}: {
      default = (import ./shell.nix {inherit pkgs;}).default;
    });

    inherit apps checks homeConfigurations images nixosConfigurations packages;
  };
}
