{pkgs, ...}: {
  programs.direnv.enable = true;
  services.locate = {
    enable = true;
    package = pkgs.plocate;
  };
  # systemd.services."tmux-save" = {
  #   description = "tmux saving upon shutdown";
  #   wantedBy = ["shutdown.target"];
  #   before = ["shutdown.target" "user-runtime-dir@1000.service"];
  #
  #   serviceConfig = {
  #     Type = "oneshot";
  #     User = "zhenyu";
  #     Environment = [
  #       "HOME=/home/zhenyu"
  #       "PATH=/run/current-system/sw/bin:/home/zhenyu/.nix-profile/bin:/home/zhenyu/.local/bin:$PATH"
  #       #       "PATH=/home/zhenyu/.local/bin:/run/wrappers/bin:/home/zhenyu/.local/bin/scripts:/home/zhenyu/.local/bin/scripts/statusbar:/home/zhenyu/.nix-profile/bin:/home/zhenyu/.local/state/nix/profile/bin:/etc/profiles/per-user/zhenyu/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/home/zhenyu/.local/bin"
  #       "TMUX_TMPDIR=/run/user/1000"
  #       "XDG_RUNTIME_DIR=/run/user/1000"
  #       "_RESURRECT_DIR=/home/zhenyu/.local/share/tmux/resurrect"
  #     ];
  #
  #     ExecStart = "/home/zhenyu/.config/tmux/plugins/tmux-resurrect/scripts/save.sh";
  #   };
  # };
  systemd.services."tmux-session" = {
    description = "tmux default session for user";
    wantedBy = ["multi-user.target"];
    wants = ["user-runtime-dir@1000.service"];
    after = ["network.target" "user-runtime-dir@1000.service"];

    serviceConfig = {
      User = "zhenyu";
      Type = "forking";
      # WorkingDirectory = "/home/zhenyu";

      Environment = [
        "HOME=/home/zhenyu"
        "PATH=/run/current-system/sw/bin:/home/zhenyu/.nix-profile/bin:/home/zhenyu/.local/bin:$PATH"
        "TMUX_TMPDIR=/run/user/1000"
        "XDG_RUNTIME_DIR=/run/user/1000"
        "_RESURRECT_DIR=/home/zhenyu/.local/share/tmux/resurrect"
      ];

      ExecStartPre = "${pkgs.runtimeShell} -c 'mkdir -p /run/user/1000/tmux-1000 && chmod 700 /run/user/1000/tmux-1000'";
      ExecStart = "${pkgs.tmux}/bin/tmux -S /run/user/1000/tmux-1000/default new-session -d";
      ExecStop = [
        "/home/zhenyu/.config/tmux/plugins/tmux-resurrect/scripts/save.sh"
        "${pkgs.tmux}/bin/tmux -S /run/user/1000/tmux-1000/default kill-server"
      ];

      Restart = "on-failure";
      RestartSec = "2s";
    };
  };

  # systemd.user.services.tmux-session = {
  #   description = "tmux default session for user";
  #   after = ["default.target"];
  #   wantedBy = ["default.target"];
  #
  #   serviceConfig = {
  #     Type = "forking";
  #     WorkingDirectory = "%h"; # expands to /home/zhenyu
  #
  #     Environment = [
  #       "_RESURRECT_DIR=%h/.local/share/tmux/resurrect"
  #       "PATH=/home/zhenyu/.local/bin:/run/wrappers/bin:/home/zhenyu/.local/bin/scripts:/home/zhenyu/.local/bin/scripts/statusbar:/home/zhenyu/.nix-profile/bin:/home/zhenyu/.local/state/nix/profile/bin:/etc/profiles/per-user/zhenyu/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/home/zhenyu/.local/bin"
  #     ];
  #
  #     ExecStartPre = "${pkgs.runtimeShell} -c 'mkdir -p /run/user/%U/tmux-%U && chmod 700 /run/user/%U/tmux-%U'";
  #
  #     ExecStart = "/run/current-system/sw/bin/tmux -S /run/user/%U/tmux-%U/default new-session -d";
  #
  #     ExecStop = [
  #       "/run/current-system/sw/bin/bash %h/.config/tmux/plugins/tmux-resurrect/scripts/save.sh"
  #       "/run/current-system/sw/bin/tmux -S /run/user/%U/tmux-%U/default kill-server"
  #     ];
  #
  #     Restart = "on-failure";
  #     RestartSec = "2s";
  #   };
  # };
}
