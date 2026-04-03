{
  pkgs,
  lib,
}: let
  const = import ../globals.nix;
  hostDefsJson = pkgs.writeText "host-defs.json" (
    builtins.toJSON (import ../machines/defs.nix {
      inherit lib const;
    })
  );
  installScript = pkgs.writeText "install-flake-test.sh" (
    lib.replaceStrings
      ["@repoSource@" "@hostDefsFile@" "@username@"]
      [(toString ../.) (toString hostDefsJson) "zhenyu"]
      (builtins.readFile ../scripts/install-flake.sh)
  );

  mkTest = {
    name,
    modules,
    testScript,
  }:
    pkgs.testers.nixosTest {
      inherit name testScript;
      nodes.machine = {config, ...}: {
        imports = modules;
        system.stateVersion = "24.05";
        networking.hostName = name;
      };
    };
in {
  "adhoc-home-install" = mkTest {
    name = "adhoc-home-install";
    modules = [
      ({pkgs, ...}: {
        environment.systemPackages = with pkgs; [
          bash
          jq
          rsync
          gnugrep
          gnused
          gawk
          perl
          util-linux
        ];

        # Simulate a generic Linux target rather than relying on NixOS-specific host identity.
        environment.etc."os-release".text = ''
          NAME="Ubuntu"
          ID=ubuntu
          PRETTY_NAME="Ubuntu 24.04"
        '';
      })
    ];
    testScript = ''
      machine.wait_for_unit("multi-user.target")
      machine.succeed("""
        mkdir -p /tmp/fakebin /tmp/test-artifacts
        cat >/tmp/fakebin/nix <<'EOF'
        #!/usr/bin/env bash
        set -euo pipefail
        printf '%s\n' "$@" > /tmp/test-artifacts/home-nix-args
        for arg in "$@"; do
          case "$arg" in
            *'#zhenyu@adhoc-home')
              worktree="''${arg%%#*}"
              cp "$worktree/machines/defs.nix" /tmp/test-artifacts/defs.nix
              cp "$worktree/machines/defs-known.nix" /tmp/test-artifacts/defs-known.nix
              ;;
          esac
        done
        exit 0
        EOF

        cat >/tmp/fakebin/sudo <<'EOF'
        #!/usr/bin/env bash
        echo "sudo should not be used in home-only mode" >&2
        exit 99
        EOF

        cat >/tmp/fakebin/disko <<'EOF'
        #!/usr/bin/env bash
        echo "disko should not be used in home-only mode" >&2
        exit 99
        EOF

        cat >/tmp/fakebin/nixos-generate-config <<'EOF'
        #!/usr/bin/env bash
        echo "nixos-generate-config should not be used in home-only mode" >&2
        exit 99
        EOF

        cat >/tmp/fakebin/nixos-install <<'EOF'
        #!/usr/bin/env bash
        echo "nixos-install should not be used in home-only mode" >&2
        exit 99
        EOF

        chmod +x /tmp/fakebin/sudo /tmp/fakebin/disko /tmp/fakebin/nixos-generate-config /tmp/fakebin/nixos-install
        chmod +x /tmp/fakebin/nix

        PATH=/tmp/fakebin:$PATH ${pkgs.bash}/bin/bash ${installScript} \
          --host adhoc-home \
          --home \
          --no-nixos \
          --home-profile personal-gnome \
          --display-profile gnome-default

        test -f /tmp/test-artifacts/defs.nix
        test -f /tmp/test-artifacts/defs-known.nix
        grep -F 'adhoc-home = {' /tmp/test-artifacts/defs.nix
        grep -F 'username = "zhenyu";' /tmp/test-artifacts/defs.nix
        grep -F 'profile = "personal-gnome";' /tmp/test-artifacts/defs.nix
        grep -F 'displayProfile = "gnome-default";' /tmp/test-artifacts/defs.nix
        grep -F '#zhenyu@adhoc-home' /tmp/test-artifacts/home-nix-args
        grep -F 'ID=ubuntu' /etc/os-release
      """)
    '';
  };

  "adhoc-nixos-install" = mkTest {
    name = "adhoc-nixos-install";
    modules = [
      ({pkgs, ...}: {
        environment.systemPackages = with pkgs; [
          bash
          jq
          rsync
          gnugrep
          gnused
          gawk
          perl
          util-linux
          coreutils
        ];
      })
    ];
    testScript = ''
      machine.wait_for_unit("multi-user.target")
      machine.succeed("""
        mkdir -p /tmp/fakebin /tmp/test-artifacts /mnt/etc/nixos

        cat >/tmp/fakebin/sudo <<'EOF'
        #!/usr/bin/env bash
        exec "$@"
        EOF

        cat >/tmp/fakebin/disko <<'EOF'
        #!/usr/bin/env bash
        set -euo pipefail
        printf '%s\n' "$@" > /tmp/test-artifacts/disko-args
        exit 0
        EOF

        cat >/tmp/fakebin/nixos-generate-config <<'EOF'
        #!/usr/bin/env bash
        set -euo pipefail
        mkdir -p /mnt/etc/nixos
        cat >/mnt/etc/nixos/hardware-configuration.nix <<'EOC'
        { ... }: { boot.loader.grub.enable = false; }
        EOC
        EOF

        cat >/tmp/fakebin/nixos-install <<'EOF'
        #!/usr/bin/env bash
        set -euo pipefail
        printf '%s\n' "$@" > /tmp/test-artifacts/nixos-install-args
        cp "$PWD/machines/defs.nix" /tmp/test-artifacts/defs.nix
        cp "$PWD/machines/defs-known.nix" /tmp/test-artifacts/defs-known.nix
        cp "$PWD/machines/adhoc-nixos/hardware-configuration.nix" /tmp/test-artifacts/hardware-configuration.nix
        exit 0
        EOF

        chmod +x /tmp/fakebin/sudo /tmp/fakebin/disko /tmp/fakebin/nixos-generate-config /tmp/fakebin/nixos-install

        printf 'secret-pass\n' | PATH=/tmp/fakebin:$PATH ${pkgs.bash}/bin/bash ${installScript} \
          --host adhoc-nixos \
          --nixos \
          --no-home \
          --disk /dev/vda \
          --nixos-profile portable-gnome \
          --swap-size 8G \
          --copy-repo no \
          --yes

        test -f /tmp/test-artifacts/defs.nix
        test -f /tmp/test-artifacts/hardware-configuration.nix
        grep -F 'adhoc-nixos = {' /tmp/test-artifacts/defs.nix
        grep -F 'profile = "portable-gnome";' /tmp/test-artifacts/defs.nix
        grep -F 'layout = "luks-btrfs";' /tmp/test-artifacts/defs.nix
        grep -F 'disk = "/dev/vda";' /tmp/test-artifacts/defs.nix
        grep -F 'swapSize = "8G";' /tmp/test-artifacts/defs.nix
        grep -F '.#adhoc-nixos' /tmp/test-artifacts/disko-args
        grep -F '.#adhoc-nixos' /tmp/test-artifacts/nixos-install-args
      """)
    '';
  };
}
