{pkgs, ...}: {
  imports = [
    ../../modules/common/home/bloat.nix
    ../../modules/common/home/minimal-gui
    ../../modules/home/sops.nix
    ./dconf.nix
  ];

  home.packages = with pkgs; [
    xournalpp
    wl-clipboard
  ];

  nixpkgs.config.allowUnfree = true;
}
