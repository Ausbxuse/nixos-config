{...}: {
  programs = {
    firefox = {
      enable = true;
      configPath = ".mozilla/firefox";
      profiles.betterfox = {
        extraConfig = builtins.readFile ./user.js;
      };
    };
  };
}
