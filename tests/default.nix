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

  mkcustomHomeInstallTest = {
    name,
    systemOverride ? null,
    homeProfile ? "personal-gnome",
    displayProfile ? "gnome-default",
  }:
    mkTest {
      inherit name;
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
      testScript = let
        systemArgs =
          if systemOverride == null
          then ""
          else "          --system ${systemOverride} \\\n";
        displayArgs =
          if displayProfile == null
          then ""
          else "          --display-profile ${displayProfile} \\\n";
        systemAsserts =
          if systemOverride == null
          then ""
          else "        grep -F 'system = \"${systemOverride}\";' /tmp/test-artifacts/defs.nix\n";
        displayAsserts =
          if displayProfile == null
          then ""
          else "        grep -F 'displayProfile = \"${displayProfile}\";' /tmp/test-artifacts/defs.nix\n";
      in
        lib.concatStringsSep "\n" [
          ''machine.wait_for_unit("multi-user.target")''
          (
            ''
              machine.succeed("""
                mkdir -p /tmp/fakebin /tmp/test-artifacts
                cat >/tmp/fakebin/nix <<'EOF'
                #!/usr/bin/env bash
                set -euo pipefail
                printf '%s\n' "$@" > /tmp/test-artifacts/home-nix-args
                for arg in "$@"; do
                  case "$arg" in
                    *'#zhenyu@${name}')
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
                  --host ${name} \
            ''
            + systemArgs
            + ''
              --home \
              --no-nixos \
              --home-profile ${homeProfile} \
            ''
            + displayArgs
            + ''

              test -f /tmp/test-artifacts/defs.nix
              test -f /tmp/test-artifacts/defs-known.nix
              grep -F '${name} = {' /tmp/test-artifacts/defs.nix
              grep -F 'username = "zhenyu";' /tmp/test-artifacts/defs.nix
              grep -F 'profile = "${homeProfile}";' /tmp/test-artifacts/defs.nix
            ''
            + displayAsserts
            + systemAsserts
            + ''
                grep -F '#zhenyu@${name}' /tmp/test-artifacts/home-nix-args
                grep -F 'ID=ubuntu' /etc/os-release
              """)
            ''
          )
        ];
    };

  mkcustomNixosInstallTest = {
    name,
    systemOverride ? null,
    nixosProfile ? "portable-gnome",
  }:
    mkTest {
      inherit name;
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
      testScript = let
        systemArgs =
          if systemOverride == null
          then ""
          else "          --system ${systemOverride} \\\n";
        systemAsserts =
          if systemOverride == null
          then ""
          else "        grep -F 'system = \"${systemOverride}\";' /tmp/test-artifacts/defs.nix\n";
      in
        lib.concatStringsSep "\n" [
          ''machine.wait_for_unit("multi-user.target")''
          (
            ''
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
                cp "$PWD/machines/${name}/hardware-configuration.nix" /tmp/test-artifacts/hardware-configuration.nix
                exit 0
                EOF

                chmod +x /tmp/fakebin/sudo /tmp/fakebin/disko /tmp/fakebin/nixos-generate-config /tmp/fakebin/nixos-install

                printf 'secret-pass\n' | PATH=/tmp/fakebin:$PATH ${pkgs.bash}/bin/bash ${installScript} \
                  --host ${name} \
            ''
            + systemArgs
            + ''
                --nixos \
                --no-home \
                --disk /dev/vda \
                --nixos-profile ${nixosProfile} \
                --swap-size 8G \
                --copy-repo no \
                --yes

              test -f /tmp/test-artifacts/defs.nix
              test -f /tmp/test-artifacts/hardware-configuration.nix
              grep -F '${name} = {' /tmp/test-artifacts/defs.nix
              grep -F 'profile = "${nixosProfile}";' /tmp/test-artifacts/defs.nix
              grep -F 'layout = "luks-btrfs";' /tmp/test-artifacts/defs.nix
              grep -F 'disk = "/dev/vda";' /tmp/test-artifacts/defs.nix
              grep -F 'swapSize = "8G";' /tmp/test-artifacts/defs.nix
            ''
            + systemAsserts
            + ''
                grep -F '.#${name}' /tmp/test-artifacts/disko-args
                grep -F '.#${name}' /tmp/test-artifacts/nixos-install-args
              """)
            ''
          )
        ];
    };
in {
  "custom-home-install" = mkcustomHomeInstallTest {
    name = "custom-home";
  };

  "custom-home-install-aarch64" = mkcustomHomeInstallTest {
    name = "custom-home-aarch64";
    systemOverride = "aarch64-linux";
  };

  "custom-nixos-install" = mkcustomNixosInstallTest {
    name = "custom-nixos";
  };

  "custom-nixos-install-aarch64" = mkcustomNixosInstallTest {
    name = "custom-nixos-aarch64";
    systemOverride = "aarch64-linux";
    nixosProfile = "minimal";
  };
}
