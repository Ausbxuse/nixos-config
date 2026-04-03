{
  config,
  lib,
  ...
}: let
  inherit (lib) mkIf mkMerge mkOption types;

  profiles = {
    none = {};
    gnome-default = {
      scale = 2;
      textScale = 1.0;
      cursor = 24;
      ghostty = 12;
    };
    razy-current = {
      scale = 2;
      textScale = 1.0;
      cursor = 24;
      ghostty = 10;
      firefox = "-1.0";
    };
    laptop-2_5k = {
      scale = 2;
      textScale = 1.0;
      cursor = 32;
      ghostty = 10;
      firefox = "0.9";
    };
    external-4k = {
      scale = 2;
      textScale = 1.0;
      cursor = 40;
      ghostty = 11;
      firefox = "0.95";
    };
    docked-dual = {
      scale = 1;
      textScale = 1.0;
      cursor = 24;
      ghostty = 12;
      firefox = "1.0";
    };
  };

  profile = profiles.${config.my.display.profile};
in {
  options.my.display.profile = mkOption {
    type = types.enum (builtins.attrNames profiles);
    default = "none";
    description = "Named display profile that tunes GNOME, Ghostty, Firefox, and cursor sizing together.";
  };

  config = mkIf (config.my.display.profile != "none") (mkMerge [
    {
      home.pointerCursor.size = lib.mkForce profile.cursor;
      programs.ghostty.settings.font-size = profile.ghostty;
      dconf.settings."org/gnome/desktop/interface" = {
        scaling-factor = lib.hm.gvariant.mkUint32 profile.scale;
        text-scaling-factor = profile.textScale;
        cursor-size = profile.cursor;
      };
    }
    (mkIf (profile ? firefox) {
      programs.firefox.profiles.betterfox.extraConfig = lib.mkAfter ''
        user_pref("layout.css.devPixelsPerPx", "${profile.firefox}");
      '';
    })
  ]);
}
