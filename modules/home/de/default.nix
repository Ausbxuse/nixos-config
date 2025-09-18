{
  pkgs,
  inputs,
  hostname,
  ...
}: {
  imports = [
    inputs.de.homeManagerModules.default
  ];
  myHost = "${hostname}";
  myFonts.enable = true;
  myThemes.enable = true;
  myApps.enable = true;
  myScripts.enable = true;
  myDict.enable = true;
  myWallpapers.enable = true;

  home.packages = with pkgs; [
    # (nerdfonts.override {fonts = ["JetBrainsMono"];})
    nerd-fonts.jetbrains-mono
  ];
}
