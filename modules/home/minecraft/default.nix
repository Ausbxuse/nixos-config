{
  config,
  lib,
  pkgs,
  ...
}: let
  sources = import ./sources.nix;
  missingPins =
    (lib.optional (sources.baseMrpack.url == "" || sources.baseMrpack.hash == "") "baseMrpack")
    ++ (lib.optional (sources.dependencies."fabric-loader" == "") "dependencies.fabric-loader")
    ++ (map (file: "${file.path}${file.filename}") (
      lib.filter (file: file.url == "" || file.hash == "" || file.filename == "") sources.files
    ));
  hasPins = missingPins == [];

  mrpack =
    if hasPins
    then (pkgs.callPackage ../../../pkgs/minecraft/mk-mrpack.nix {}) {
      inherit sources;
    }
    else null;
in {
  warnings =
    lib.optional (!hasPins)
    ''
      Declarative Minecraft instance is configured, but some Minecraft source pins are missing in
      ${toString ./sources.nix}.
      Fill exact URLs and hashes for:
      ${lib.concatStringsSep "\n" (map (entry: "  - ${entry}") missingPins)}
    '';
    ++ lib.optional hasPins ''
      Declarative Minecraft now builds a pinned .mrpack instead of syncing a handcrafted Prism instance.
      Use `nix run .#minecraft` to refresh/import ${sources.instanceName} into Prism Launcher.
      Built pack: ${mrpack}
    '';
}
