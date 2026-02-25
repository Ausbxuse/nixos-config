{...}: {
  imports = [
    ../../../modules/home/env
    ../../../modules/home/zsh
    ../../../modules/home/nvim
    ../../../modules/home/tmux
  ];
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
