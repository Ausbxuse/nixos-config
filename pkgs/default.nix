{
  lib,
  pkgs,
  const,
  hostDefs,
}: let
  repoSource = builtins.path {
    path = ../.;
    name = "nix-config";
  };
  hostDefsFile = pkgs.writeText "host-defs.json" (builtins.toJSON hostDefs);
  shLib = builtins.readFile ../scripts/lib.sh;

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

  enroll = mkScriptApp {
    name = "enroll";
    src = ../scripts/enroll.sh;
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
    replacements = {
      "@source_lib@" = shLib;
    };
  };

  install = mkScriptApp {
    name = "install-config";
    src = ../scripts/install-flake.sh;
    runtimeInputs = with pkgs; [
      coreutils
      git
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
      "@source_lib@" = shLib;
      "@repoSource@" = toString repoSource;
      "@hostDefsFile@" = toString hostDefsFile;
      "@username@" = const.username;
    };
  };

  setupRecoveryUsb = mkScriptApp {
    name = "setup-recovery-usb";
    src = ../scripts/setup-recovery-usb.sh;
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
      gptfdisk
      dosfstools
      e2fsprogs
      restic
      gnused
    ];
    replacements = {
      "@source_lib@" = shLib;
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
  {
    minecraftClient = minecraft.mrpack;
    minecraftDeploy = minecraft.deploy;
    minecraftBootstrap = minecraft.bootstrap;
    minecraftSync = minecraft.sync;
    "validate-host" = hostValidation;
    "admit-host" = admitHost;
    "enroll" = enroll;
    "setup-recovery-usb" = setupRecoveryUsb;
    inherit install nvim;
  }
