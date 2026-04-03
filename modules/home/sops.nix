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
  warnings =
    lib.optional (!hasSecretsFile)
    "No nix-secrets/secrets.yaml found; SOPS-managed home secrets are disabled for this build.";
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
