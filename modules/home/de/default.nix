{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.de.homeManagerModules.default
  ];
  myFonts.enable = true;
  myThemes.enable = true;
  myApps.enable = true;
  myScripts.enable = true;
  home.packages = with pkgs; [
    # (nerdfonts.override {fonts = ["JetBrainsMono"];})
    nerd-fonts.jetbrains-mono
  ];
}
