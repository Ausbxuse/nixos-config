{config, ...}: {
  imports = [
    ./dconf.nix
  ];

  home.file."${config.home.homeDirectory}/.local/bin/slimevr-safe" = {
    text = ''
      #!/usr/bin/env bash
      export WEBKIT_DISABLE_DMABUF_RENDERER=1
      export WAYLAND_DISPLAY=0
      exec slimevr "$@"
    '';
    executable = true;
  };

  xdg.desktopEntries.slimevr = {
    name = "SlimeVR";
    genericName = "Full-body tracking";
    comment = "An app for facilitating full-body tracking in virtual reality";
    exec = "${config.home.homeDirectory}/.local/bin/slimevr-safe";
    icon = "slimevr";
    terminal = false;
    type = "Application";
    categories = ["Game" "GTK"];
    settings = {
      Keywords = "FBT;VR;Steam;VRChat;IMU;";
    };
  };
}
