# Common GNOME dconf tweaks shared across machines.
{lib, ...}:
with lib.hm.gvariant; {
  dconf.settings."org/gnome/shell/extensions/caffeine" = {
    indicator-position-max = 2;
    toggle-state = true;
  };

  dconf.settings."org/gnome/mutter".experimental-features = ["scale-monitor-framebuffer" "xwayland-native-scaling"];
}
