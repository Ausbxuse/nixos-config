{
  lib,
  pkgs,
  self,
  inputs,
  const,
  hostDefs,
  nixosHosts,
  nixosConfigurations,
}: let
  hostDefsFile = pkgs.writeText "host-defs.json" (builtins.toJSON hostDefs);
  nixosInstallerVmImage =
    (inputs.nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        ../tests/nixos-installer-vm.nix
        ({modulesPath, ...}: {
          imports = [
            "${modulesPath}/virtualisation/disk-image.nix"
          ];
          image.format = "qcow2";
          image.baseName = "nixos-installer";
        })
      ];
    }).config.system.build.image;

  minecraft = pkgs.callPackage ./minecraft {};

  mkScriptApp = {
    name,
    src,
    runtimeInputs,
    replacements ? {},
  }:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text =
        lib.replaceStrings
        (builtins.attrNames replacements)
        (builtins.attrValues replacements)
        (builtins.readFile src);
    };

  hostValidation = mkScriptApp {
    name = "validate-host";
    src = ../scripts/validate-host.sh;
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
      systemd
      wireplumber
      alsa-utils
      v4l-utils
      brightnessctl
      pciutils
    ];
  };

  admitHost = mkScriptApp {
    name = "admit-host";
    src = ../scripts/admit-host.sh;
    runtimeInputs = with pkgs; [
      coreutils
      jq
      sops
      ssh-to-age
      git
    ];
  };

  provision = mkScriptApp {
    name = "provision";
    src = ../scripts/provision.sh;
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
      jq
      openssh
      rsync
      sops
      ssh-to-age
      syncthing
      admitHost
    ];
  };

  install = mkScriptApp {
    name = "install-config";
    src = ../scripts/install-flake.sh;
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
      gawk
      jq
      perl
      rsync
      util-linux
      disko
      nixos-install-tools
      nix
    ];
    replacements = {
      "@repoSource@" = toString self.outPath;
      "@hostDefsFile@" = toString hostDefsFile;
      "@username@" = const.username;
    };
  };

  ubuntuHomeInstallTest = mkScriptApp {
    name = "ubuntu-home-install-test";
    src = ../tests/run-ubuntu-home-install.sh;
    runtimeInputs = with pkgs; [
      coreutils
      curl
      openssh
      qemu_kvm
      cloud-utils
      rsync
    ];
  };

  nixosSystemInstallTest = mkScriptApp {
    name = "nixos-system-install-test";
    src = ../tests/run-nixos-system-install.sh;
    runtimeInputs = with pkgs; [
      coreutils
      openssh
      OVMF
      qemu_kvm
      rsync
      sshpass
    ];
    replacements = {
      "@vmImage@" = "${nixosInstallerVmImage}/nixos-installer.qcow2";
      "@ovmfCode@" = builtins.toString pkgs.OVMF.firmware;
      "@ovmfVarsTemplate@" =
        lib.replaceStrings ["OVMF_CODE.fd"] ["OVMF_VARS.fd"] (builtins.toString pkgs.OVMF.firmware);
    };
  };

  nvim = let
    nvimConfig = ../modules/home/nvim/nvim;
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
in
  (lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") (import ../isos {
    inherit pkgs inputs nixosConfigurations;
    seedHostNames = nixosHosts;
  }))
  // {
    minecraftClient = minecraft.mrpack;
    minecraftDeploy = minecraft.deploy;
    minecraftBootstrap = minecraft.bootstrap;
    minecraftSync = minecraft.sync;
    "validate-host" = hostValidation;
    "admit-host" = admitHost;
    "provision" = provision;
    "nixos-system-install-test" = nixosSystemInstallTest;
    "ubuntu-home-install-test" = ubuntuHomeInstallTest;
    inherit install nvim;
  }
