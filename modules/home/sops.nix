{
  inputs,
  config,
  ...
}: let
  secretspath = builtins.toString inputs.nix-secrets.outPath;
in {
  imports = [
    inputs.sops-nix.homeManagerModules.sops
  ];
  sops = {
    age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt"; # must have no password!
    defaultSopsFile = "${secretspath}/secrets.yaml";
    defaultSymlinkPath = "/run/user/1000/secrets";
    defaultSecretsMountPoint = "/run/user/1000/secrets.d";
    # secrets.github = {};
    secrets.anthropic = {};
  };
}
