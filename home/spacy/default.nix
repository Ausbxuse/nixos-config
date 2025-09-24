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

  nixGL.packages = import inputs.nixgl {inherit pkgs;};
  nixGL.defaultWrapper = "mesa";
  nixGL.installScripts = ["mesa"];
  programs.ghostty.package = config.lib.nixGL.wrap pkgs.ghostty;
}
