{
  inputs,
  config,
  lib,
  ...
}: let
  secretspath = builtins.toString ../../secrets/nix-secrets;
  hasSecretsFile = builtins.pathExists "${secretspath}/secrets.yaml";
in
  {
    imports = [
      inputs.sops-nix.homeManagerModules.sops
    ];
  }
  // lib.optionalAttrs hasSecretsFile {
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
