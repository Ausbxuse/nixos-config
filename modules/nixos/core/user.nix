{
  pkgs,
  const,
  ...
}: {
  programs.zsh.enable = true;
  programs.tmux.enable = true;

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  users.defaultUserShell = pkgs.zsh;
  users.users.${const.username} = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager" "video" "dialout"];
    home = "/home/${const.username}";
    initialHashedPassword = "";
    createHome = true;
  };
  services.udev.extraRules = ''
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1209", ATTRS{idProduct} =="7690", MODE="0660", GROUP="dialout", TAG+="uaccess"
  '';

  security.sudo = {
    enable = true;
    extraRules = [
      {
        commands = [
          {
            command = "/usr/bin/env";
            options = ["NOPASSWD"];
          }
        ];
        groups = ["wheel"];
      }
    ];
  };
}
