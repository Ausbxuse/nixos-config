{
  inputs,
  nix-secrets,
  config,
  ...
}: let
  secretspath = builtins.toString nix-secrets;
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
    secrets.gemini = {};
  };
}
