{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ../../home/env
    ../../home/zsh
    ../../home/nvim
    ../../home/tmux
  ];
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  # CLI helpers and nicer rebuild UX
  # programs.nix-index.enable = true;

  programs.command-not-found.enable = true;

  home.packages = with pkgs; [
    comma
    nh
    nvd
    nix-output-monitor
  ];
  #    - Point your just recipes at nh os switch -- --flake .#${HOST} (and nh home switch -- --flake .#${USER}@${HOST}) so you get nom logs and nice diffs automatically.
  #  - Use nvd diff /run/current-system ./result (or nh os diff) before switching to catch surprises.
  #  - With nix-index + comma, you can run commands you don’t have installed as , <cmd> and they’re fetched on the fly.
  #
}
