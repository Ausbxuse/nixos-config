{
  inputs,
  hostname,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/profiles/home/minimal.nix
    inputs.de.homeManagerModules.default
  ];
  myHost = "${hostname}";
  myScripts.enable = true;
}
