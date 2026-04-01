{
  config,
  const,
  lib,
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/common/home/minimal-gui
  ];

  home.activation.make-zsh-default-shell = lib.hm.dag.entryAfter ["writeBoundary"] ''
    PATH="/usr/bin:/bin:$PATH"
    ZSH_PATH="/home/${const.username}/.nix-profile/bin/zsh"

    # only run if current shell is not ZSH_PATH
    if [[ $(getent passwd ${const.username}) != *"$ZSH_PATH" ]]; then
      echo "setting zsh as default shell (using chsh). password might be necessary."

      # add to /etc/shells if missing
      if ! grep -q "$ZSH_PATH" /etc/shells; then
        echo "adding $ZSH_PATH to /etc/shells"
        run sudo tee -a /etc/shells <<<"$ZSH_PATH"
      fi

      echo "running chsh to make zsh the default shell"
      run chsh -s "$ZSH_PATH" ${const.username}
      echo "zsh is now set as default shell!"
    fi
  '';

  targets.genericLinux.nixGL.packages = lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 (import inputs.nixgl {inherit pkgs;});
  targets.genericLinux.nixGL.defaultWrapper = lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 "mesa";
  targets.genericLinux.nixGL.installScripts = lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 ["mesa"];
  programs.ghostty.package =
    if pkgs.stdenv.hostPlatform.isx86_64
    then config.lib.nixGL.wrap pkgs.ghostty
    else pkgs.ghostty;
}
