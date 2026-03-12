{config, pkgs, ...}: {
  home.packages = [pkgs.sioyek];

  home.file.".local/bin/sioyek-run" = {
    executable = true;
    text = ''
      #!${pkgs.bash}/bin/bash
      export QT_QPA_PLATFORM=xcb
      export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
      exec ${pkgs.sioyek}/bin/sioyek "$@"
    '';
  };

  xdg.configFile."sioyek/prefs_user.config".source = ./prefs_user.config;
  xdg.configFile."sioyek/keys_user.config".source = ./keys_user.config;
  xdg.configFile."applications/sioyek.desktop".text = ''
    [Desktop Entry]
    Name=Sioyek
    Comment=PDF viewer for reading research papers and technical books
    Keywords=pdf;viewer;reader;research;
    TryExec=${pkgs.sioyek}/bin/sioyek
    Exec=${config.home.homeDirectory}/.local/bin/sioyek-run %f
    StartupNotify=true
    Terminal=false
    Type=Application
    Icon=sioyek-icon-linux
    Categories=Development;Viewer;
    MimeType=application/pdf;
    StartupWMClass=sioyek
  '';
}
