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
      url = "git+ssh://git@zhenyuzhao.com/var/lib/git-server/nix-secrets";
      flake = false;
    };
    bootstrap-keys = {
      url = "path:/home/zhenyu/.local/src/secrets";
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
    supportedSystems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = lib.genAttrs supportedSystems;
    pkgsFor = system:
      import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    mkNixos = system: modules: hostname:
      nixpkgs.lib.nixosSystem {
        inherit system;
        inherit modules;
        specialArgs = {inherit inputs hostname const;};
      };

    mkHome = system: modules: hostname:
      inputs.home-manager.lib.homeManagerConfiguration {
        inherit modules;
        pkgs = pkgsFor system;
        extraSpecialArgs = {inherit inputs hostname const nix-secrets;};
      };

    mkNixosWithHome = system: modules: hostname:
      nixpkgs.lib.nixosSystem {
        inherit system;
        modules =
          modules
          ++ [
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager.users.${const.username} = import (./home + "/${hostname}");
              home-manager.extraSpecialArgs = {inherit inputs hostname const nix-secrets;};
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
          ];
        specialArgs = {inherit inputs hostname const;};
      };

    nixosHosts = lib.attrNames (builtins.readDir ./hosts);
    homeHosts = lib.attrNames (builtins.readDir ./home);

    nix-secrets = inputs.nix-secrets;
    bootstrap-keys = inputs.bootstrap-keys;
  in {
    templates = import ./templates;

    devShells = forAllSystems (system: let
      pkgs = pkgsFor system;
    in {
      default = (import ./shell.nix {inherit pkgs;}).default;
    });

    packages = forAllSystems (system: let
      pkgs = pkgsFor system;
      minecraft = pkgs.callPackage ./pkgs/minecraft {};
      mkBootstrap = import ./bootstrap.nix {
        inherit pkgs system;
        home-manager = inputs.home-manager.packages.${system}.default;
      };
    in
      (lib.optionalAttrs (system == "x86_64-linux") (import ./isos {
        inherit pkgs inputs bootstrap-keys;
        nixosConfigurations = self.nixosConfigurations;
        seedHostNames = nixosHosts;
      }))
      // {
        bootstrap_home = mkBootstrap "earthy";
        bootstrap_home_gui = mkBootstrap "spacy";
        minecraftClient = minecraft.mrpack;
        minecraftDeploy = minecraft.deploy;
        minecraftBootstrap = minecraft.bootstrap;
        minecraftSync = minecraft.sync;
        nvim = let
          nvimConfig = ./modules/home/nvim/nvim;
          deps = with pkgs; [nodejs tree-sitter fd ripgrep gcc git];
          depsPath = pkgs.lib.makeBinPath deps;
        in
          pkgs.writeShellScriptBin "nvim" ''
            NVIM_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
            if [ ! -e "$NVIM_DIR" ]; then
              mkdir -p "$(dirname "$NVIM_DIR")"
              ln -s ${nvimConfig} "$NVIM_DIR"
            fi
            export PATH="${depsPath}:$PATH"
            exec ${pkgs.neovim}/bin/nvim "$@"
          '';
      });

    apps = forAllSystems (system: let
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
      default = {
        type = "app";
        program = "${minecraft}/bin/sync-minecraft-client";
      };
    });

    checks = forAllSystems (system: let
      pkgs = pkgsFor system;
    in
      (import ./tests {inherit pkgs lib;})
      // lib.optionalAttrs (system == "x86_64-linux") {
        nvim = self.packages.${system}.nvim;
        inherit (self.packages.${system}) gnome-iso;
      }
      // {
        nvim = self.packages.${system}.nvim;
        home-earthy = (mkHome system [./home/earthy] "earthy").activationPackage;
        home-spacy = (mkHome system [./home/spacy] "spacy").activationPackage;
        home-timy = (mkHome system [./home/timy] "timy").activationPackage;
        home-uni = (mkHome system [./home/uni] "uni").activationPackage;
        nixos-spacy = (mkNixosWithHome system [./hosts/spacy] "spacy").config.system.build.toplevel;
        nixos-timy = (mkNixosWithHome system [./hosts/timy] "timy").config.system.build.toplevel;
        nixos-uni = (mkNixosWithHome system [./hosts/uni] "uni").config.system.build.toplevel;
      }
      );

    nixosConfigurations = builtins.listToAttrs (map (host: {
        name = "${host}";
        value = mkNixosWithHome const.system [./hosts/${host}] host;
      })
      nixosHosts);

    homeConfigurations = builtins.listToAttrs (map (host: {
        name = "${const.username}@" + host;
        value = mkHome const.system [./home/${host}] host;
      })
      homeHosts);
  };
}
