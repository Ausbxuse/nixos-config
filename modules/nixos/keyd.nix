{...}: {
  services.keyd = {
    enable = false;

    keyboards.default = {
      ids = ["*"]; # apply to all keyboards

      settings = {
        global = {
          # overload_tap_timeout = "200";
          layer_indicator = true;
        };

        main = {
          capslock = "overloadt2(control, esc, 200)";
          leftalt = "overloadt2(alt, backspace, 200)";
          space = "overloadt2(num, space, 200)";
          # rightalt = "overload(alt, enter)";
        };

        num = {
          q = "1";
          w = "2";
          e = "3";
          r = "4";
          t = "5";
          y = "6";
          u = "7";
          i = "8";
          o = "9";
          p = "0";

          h = "left";
          j = "down";
          k = "up";
          l = "right";

          # symbols/others
          n = "S-minus"; # _
          m = "minus"; # -
          comma = "equal"; # =
          period = "S-equal"; # +
          slash = "S-rightbrace"; # {
          semicolon = "backslash"; # ; → \
          apostrophe = "S-backslash"; # ' → |
          tab = "grave"; # `  (backtick key)
          leftshift = "S-grave"; # ~  (shift + `)

          # zxcvb -> ! @ # $ %
          z = "S-1";
          x = "S-2";
          c = "S-3";
          v = "S-4";
          b = "S-5";

          # asdfg -> ^ & * ( )
          a = "S-6";
          s = "S-7";
          d = "S-8";
          f = "S-9";
          g = "S-0";
        };
      };
    };
  };
}
