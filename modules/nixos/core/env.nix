{config, ...}: {
  xdg.autostart.enable = true;
  # Keep system-wide session variables free of $HOME/XDG overrides so the GDM
  # greeter can start cleanly on Wayland. User-scoped XDG paths already live in
  # Home Manager.
  environment.sessionVariables = {
    EDITOR = "nvim";
    XCURSOR_THEME = "capitaine-cursors-white";
    LESSHISTFILE = "-";
    DICS = "/usr/share/stardict/dic/";
    TERM = "xterm-256color";
  };
}
