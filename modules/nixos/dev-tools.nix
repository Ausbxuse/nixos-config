{
  pkgs,
  const,
  ...
}: {
  programs.direnv.enable = true;
  services.locate = {
    enable = true;
    package = pkgs.plocate;
  };

  # systemd.services."tmux-session" = {
  #   description = "tmux default session for user";
  #   wantedBy = ["multi-user.target"];
  #   wants = ["user-runtime-dir@1000.service"];
  #   after = ["user-runtime-dir@1000.service"];
  #
  #   serviceConfig = {
  #     User = "${const.username}";
  #     Group = "wheel";
  #     Type = "forking";
  #
  #     # TODO: fix 1000 uid
  #     Environment = [
  #       "HOME=/home/${const.username}"
  #       "PATH=/home/${const.username}/.local/bin:/run/wrappers/bin:/home/${const.username}/.local/bin/scripts:/home/${const.username}/.local/bin/scripts/statusbar:/home/${const.username}/.nix-profile/bin:/home/${const.username}/.local/state/nix/profile/bin:/etc/profiles/per-user/${const.username}/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
  #       "TMUX_TMPDIR=/run/user/1000"
  #       "DISPLAY=:0"
  #       "XDG_RUNTIME_DIR=/run/user/1000"
  #     ];
  #
  #     ExecStartPre = "${pkgs.runtimeShell} -c 'mkdir -p /run/user/1000/tmux-1000 && chmod 700 /run/user/1000/tmux-1000'";
  #     ExecStart = "${pkgs.tmux}/bin/tmux new-session -d";
  #     ExecStop = [
  #       "/home/${const.username}/.config/tmux/plugins/tmux-resurrect/scripts/save.sh"
  #       "${pkgs.tmux}/bin/tmux kill-server"
  #     ];
  #
  #     Restart = "on-failure";
  #     RestartSec = "2s";
  #   };
  # };
}
