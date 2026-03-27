{
  lib,
  pkgs,
}: let
  sources = import ../../modules/home/minecraft/sources.nix;

  missingPins =
    (lib.optional (sources.baseMrpack.url == "" || sources.baseMrpack.hash == "") "baseMrpack")
    ++ (lib.optional (sources.dependencies."fabric-loader" == "") "dependencies.fabric-loader")
    ++ (map (file: "${file.path}${file.filename}") (
      lib.filter (file: file.url == "" || file.hash == "" || file.filename == "") sources.files
    ));

  hasPins = missingPins == [];

  mrpack =
    if hasPins
    then (pkgs.callPackage ./mk-mrpack.nix {}) {inherit sources;}
    else pkgs.writeText "minecraft-client-missing-pins" ''
      Missing Minecraft source pins in modules/home/minecraft/sources.nix:
      ${lib.concatStringsSep "\n" (map (entry: "- ${entry}") missingPins)}
    '';

  deploy = pkgs.writeShellApplication {
    name = "deploy-minecraft-client";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      xdg-utils
    ];
    text = ''
      set -euo pipefail

      if [ -f "${mrpack}" ]; then
        printf '%s\n' "Cannot deploy ${sources.instanceName}: source pins are missing."
        printf '%s\n' "Fill modules/home/minecraft/sources.nix first."
        cat "${mrpack}"
        exit 1
      fi

      mrpack_path="$(find "${mrpack}" -maxdepth 1 -type f -name '*.mrpack' | head -n 1)"
      if [ -z "$mrpack_path" ]; then
        printf '%s\n' "Built Minecraft pack is missing its .mrpack artifact."
        exit 1
      fi

      printf '%s\n' "Built ${sources.instanceName}: $mrpack_path"
      exec xdg-open "$mrpack_path"
    '';
  };

  bootstrap = pkgs.writeShellApplication {
    name = "bootstrap-minecraft-client";
    runtimeInputs = with pkgs; [
      python3
    ];
    text = ''
      set -euo pipefail
      target=''${1:-modules/home/minecraft/sources.nix}
      exec python3 ${./bootstrap.py} "$target"
    '';
  };

  sync = pkgs.writeShellApplication {
    name = "sync-minecraft-client";
    runtimeInputs = with pkgs; [
      nix
    ];
    text = ''
      set -euo pipefail
      repo_root=${lib.escapeShellArg (toString ../..)}
      nix --extra-experimental-features 'nix-command flakes' run "path:$repo_root"#minecraft-bootstrap
      exec nix --extra-experimental-features 'nix-command flakes' run "path:$repo_root"#minecraft-deploy
    '';
  };
in {
  inherit sources missingPins hasPins mrpack deploy bootstrap sync;
}
