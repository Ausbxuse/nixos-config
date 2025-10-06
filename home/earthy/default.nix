{
  inputs,
  hostname,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/common/home/minimal.nix
    inputs.de.homeManagerModules.default
  ];
  myHost = "${hostname}";
  myScripts.enable = true;

  programs.tmux = {
    shortcut = "b";
    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = continuum; # needs resurrect present
        extraConfig = ''
          set -g status-position bottom
        '';
      }
    ];
  };
}
