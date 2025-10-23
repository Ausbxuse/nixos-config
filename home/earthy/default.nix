{
  inputs,
  hostname,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/common/home/minimal.nix
    inputs.de.homeManagerModules.default
  ];
  myHost = "${hostname}";
  myScripts.enable = true;
}
