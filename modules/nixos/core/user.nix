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
    extraGroups = ["wheel" "networkmanager" "video"];
    home = "/home/${const.username}";
    initialHashedPassword = "";
    createHome = true;
  };

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
