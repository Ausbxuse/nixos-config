{lib, ...}: {
  imports = [
    ../../modules/home/slimevr.nix
    ../../modules/home/gnome-tweaks.nix
  ];

  programs.firefox.profiles.betterfox.extraConfig = lib.mkAfter ''
    user_pref("browser.uidensity", 1);
  '';
}
