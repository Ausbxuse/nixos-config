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
            git
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
                  --name 'Test User' \
                  --email 'test@example.com' \
            ''
            + systemArgs
            + ''
              --home \
              --home-profile ${homeProfile} \
            ''
            + displayArgs
            + ''

              test -f /tmp/test-artifacts/defs.nix
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
            git
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
                cp "$PWD/machines/${name}/hardware-configuration.nix" /tmp/test-artifacts/hardware-configuration.nix
                exit 0
                EOF

                chmod +x /tmp/fakebin/sudo /tmp/fakebin/disko /tmp/fakebin/nixos-generate-config /tmp/fakebin/nixos-install

                printf 'secret-pass\n' | PATH=/tmp/fakebin:$PATH ${pkgs.bash}/bin/bash ${installScript} \
                  --host ${name} \
                  --name 'Test User' \
                  --email 'test@example.com' \
            ''
            + systemArgs
            + ''
                --nixos \
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

  "custom-nixos-install-reports-errors" = mkTest {
    name = "custom-nixos-error";
    modules = [
      ({pkgs, ...}: {
        environment.systemPackages = with pkgs; [
          bash
          git
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
    testScript = lib.concatStringsSep "\n" [
      ''machine.wait_for_unit("multi-user.target")''
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
          echo 'installing the boot loader...'
          echo 'ERROR: mkdir /var/lock/dmraid'
          exit 0
          EOF

          chmod +x /tmp/fakebin/sudo /tmp/fakebin/disko /tmp/fakebin/nixos-generate-config /tmp/fakebin/nixos-install

          if printf 'secret-pass\n' | PATH=/tmp/fakebin:$PATH ${pkgs.bash}/bin/bash ${installScript} \
            --host custom-nixos-error \
            --name 'Test User' \
            --email 'test@example.com' \
            --nixos \
            --disk /dev/vda \
            --nixos-profile minimal \
            --swap-size 8G \
            --copy-repo no \
            --yes \
            >/tmp/test-artifacts/install.out 2>/tmp/test-artifacts/install.err; then
            echo 'installer unexpectedly succeeded' >&2
            exit 1
          fi

          grep -F 'ERROR: mkdir /var/lock/dmraid' /tmp/test-artifacts/install.err
          grep -F 'nixos-install reported an installation error' /tmp/test-artifacts/install.err
        """)
      ''
    ];
  };

  "custom-nixos-install-copies-git-repo" = mkTest {
    name = "custom-nixos-copy-repo";
    modules = [
      ({pkgs, ...}: {
        environment.systemPackages = with pkgs; [
          bash
          git
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
    testScript = lib.concatStringsSep "\n" [
      ''machine.wait_for_unit("multi-user.target")''
      ''
        machine.succeed("""
          mkdir -p /tmp/fakebin /tmp/test-artifacts /mnt/etc/nixos /tmp/source-repo
          cp -r ${../.}/. /tmp/source-repo/
          chmod -R u+w /tmp/source-repo

          cd /tmp/source-repo
          git init
          git config user.name 'Fixture User'
          git config user.email 'fixture@example.com'
          git add .
          git commit -m 'fixture'
          git rev-parse HEAD >/tmp/test-artifacts/source-head
          echo '# dirty source file' >> TODO.md

          cat >/tmp/fakebin/sudo <<'EOF'
          #!/usr/bin/env bash
          exec "$@"
          EOF

          cat >/tmp/fakebin/disko <<'EOF'
          #!/usr/bin/env bash
          set -euo pipefail
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
          exit 0
          EOF

          cat >/tmp/fakebin/nixos-enter <<'EOF'
          #!/usr/bin/env bash
          set -euo pipefail
          if [ "$1" = "--root" ]; then
            shift 2
          fi
          if [ "$1" = "-c" ]; then
            shift
            eval "$1"
            exit 0
          fi
          exec "$@"
          EOF

          chmod +x /tmp/fakebin/sudo /tmp/fakebin/disko /tmp/fakebin/nixos-generate-config /tmp/fakebin/nixos-install /tmp/fakebin/nixos-enter

          PATH=/tmp/fakebin:$PATH ${pkgs.bash}/bin/bash ${installScript} \
            --host custom-nixos-copy-repo \
            --name 'Test User' \
            --email 'test@example.com' \
            --nixos \
            --disk /dev/vda \
            --nixos-profile minimal \
            --swap-size 8G \
            --copy-repo yes \
            --yes

          TARGET_REPO=/mnt/home/zhenyu/src/public/nix-config
          test -d "$TARGET_REPO/.git"
          test "$(cat /tmp/test-artifacts/source-head)" = "$(git -C "$TARGET_REPO" rev-parse HEAD)"
          grep -F 'custom-nixos-copy-repo = {' "$TARGET_REPO/machines/defs.nix"
          grep -F 'name = "Test User";' "$TARGET_REPO/globals.nix"
          test -f "$TARGET_REPO/machines/custom-nixos-copy-repo/hardware-configuration.nix"

          git -C "$TARGET_REPO" status --short >/tmp/test-artifacts/target-status
          grep -F ' M globals.nix' /tmp/test-artifacts/target-status
          grep -F ' M machines/defs.nix' /tmp/test-artifacts/target-status
          grep -F '?? machines/custom-nixos-copy-repo/' /tmp/test-artifacts/target-status
          if grep -F 'TODO.md' /tmp/test-artifacts/target-status; then
            echo 'source dirty files leaked into target clone' >&2
            exit 1
          fi
        """)
      ''
    ];
  };
}
