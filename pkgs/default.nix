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

  nvidiaPrimeBusIds = pkgs.writeShellApplication {
    name = "nvidia-prime-bus-ids";
    runtimeInputs = with pkgs; [
      coreutils
      gnused
      pciutils
    ];
    text = ''
      set -euo pipefail

      hex_to_dec() {
        printf '%d' "0x$1"
      }

      format_bus_id() {
        local pci_addr="$1"
        local domain bus device function rest

        domain="''${pci_addr%%:*}"
        rest="''${pci_addr#*:}"
        bus="''${rest%%:*}"
        rest="''${rest#*:}"
        device="''${rest%%.*}"
        function="''${rest#*.}"

        printf 'PCI:%d@%d:%d:%d' \
          "$(hex_to_dec "$bus")" \
          "$(hex_to_dec "$domain")" \
          "$(hex_to_dec "$device")" \
          "$(hex_to_dec "$function")"
      }

      device_name() {
        local pci_addr="$1"

        if command -v lspci >/dev/null 2>&1; then
          lspci -s "$pci_addr" 2>/dev/null | sed 's/^[^ ]* //'
        fi
      }

      nvidia_bus_id=""
      intel_bus_id=""
      amd_bus_id=""

      for devpath in /sys/bus/pci/devices/*; do
        [ -e "$devpath/class" ] || continue
        [ -e "$devpath/vendor" ] || continue

        class="$(cat "$devpath/class")"
        case "$class" in
          0x030000 | 0x030200 | 0x038000) ;;
          *) continue ;;
        esac

        vendor="$(cat "$devpath/vendor")"
        pci_addr="''${devpath##*/}"
        bus_id="$(format_bus_id "$pci_addr")"

        case "$vendor" in
          0x10de)
            if [ -z "$nvidia_bus_id" ]; then
              nvidia_bus_id="$bus_id"
            fi
            ;;
          0x8086)
            if [ -z "$intel_bus_id" ]; then
              intel_bus_id="$bus_id"
            fi
            ;;
          0x1002)
            if [ -z "$amd_bus_id" ]; then
              amd_bus_id="$bus_id"
            fi
            ;;
        esac

        name="$(device_name "$pci_addr")"
        if [ -n "$name" ]; then
          printf '# %s -> %s\n' "$pci_addr" "$name"
        else
          printf '# %s vendor=%s class=%s\n' "$pci_addr" "$vendor" "$class"
        fi
      done

      if [ -z "$nvidia_bus_id" ]; then
        printf 'error: no NVIDIA display controller found under /sys/bus/pci/devices\n' >&2
        exit 1
      fi

      if [ -z "$intel_bus_id" ] && [ -z "$amd_bus_id" ]; then
        printf 'error: no Intel or AMD integrated display controller found under /sys/bus/pci/devices\n' >&2
        exit 1
      fi

      printf '\nhardware.nvidia.prime = {\n'
      printf '  nvidiaBusId = "%s";\n' "$nvidia_bus_id"
      if [ -n "$intel_bus_id" ]; then
        printf '  intelBusId = "%s";\n' "$intel_bus_id"
      else
        printf '  amdgpuBusId = "%s";\n' "$amd_bus_id"
      fi
      printf '};\n'
    '';
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
in {
  minecraftClient = minecraft.mrpack;
  minecraftDeploy = minecraft.deploy;
  minecraftBootstrap = minecraft.bootstrap;
  minecraftSync = minecraft.sync;
  "validate-host" = hostValidation;
  "admit-host" = admitHost;
  "enroll" = enroll;
  "setup-recovery-usb" = setupRecoveryUsb;
  inherit install nvidiaPrimeBusIds nvim;
}
