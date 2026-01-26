{
  pkgs,
  lib,
}: let
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
  gnome = mkTest {
    name = "gnome";
    modules = [
      ../modules/nixos/gui/gnome.nix
    ];
    testScript = ''
      machine.wait_for_unit("display-manager.service")
      machine.wait_for_unit("graphical.target")
      machine.succeed("systemctl is-active display-manager.service")
    '';
  };

  printing = mkTest {
    name = "printing";
    modules = [
      ../modules/nixos/hardware/printing.nix
    ];
    testScript = ''
      machine.wait_for_unit("cups.service")
      machine.succeed("systemctl is-active cups.service")
    '';
  };

  pipewire = mkTest {
    name = "pipewire";
    modules = [
      ../modules/nixos/hardware/sound.nix
      ({...}: {
        users.users.alice = {
          isNormalUser = true;
          uid = 1000;
          extraGroups = ["audio" "video"];
        };
      })
    ];
    testScript = ''
      machine.wait_for_unit("multi-user.target")
      machine.succeed("loginctl enable-linger alice")
      machine.succeed("su - alice -c 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user start pipewire.service'")
      machine.succeed("su - alice -c 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user is-active pipewire.service'")
    '';
  };
}
