{...}: {
  imports = [
    ../../modules/common/home/bloat.nix
    ../../modules/common/home/minimal-gui
    ../../modules/home/sops.nix
    ./dconf.nix
  ];
}
