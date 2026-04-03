{lib, ...}: {
  imports = [
    ../uni
  ];

  programs.ghostty.settings.font-size = lib.mkForce 10;
  programs.firefox.profiles.betterfox.extraConfig = lib.mkAfter ''
    user_pref("browser.uidensity", 1);
    user_pref("layout.css.devPixelsPerPx", "-1.0");
  '';
}
