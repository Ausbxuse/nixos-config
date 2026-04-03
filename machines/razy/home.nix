{lib, ...}: {
  imports = [
    ../uni/home.nix
  ];

  programs.firefox.profiles.betterfox.extraConfig = lib.mkAfter ''
    user_pref("browser.uidensity", 1);
  '';
}
