# apps.nix
{packages}: let
  mkApp = description: program: {
    type = "app";
    inherit program;
    meta.description = description;
  };
in {
  minecraft =
    mkApp "Sync the Minecraft client assets."
    "${packages.minecraftSync}/bin/sync-minecraft-client";

  "minecraft-bootstrap" =
    mkApp "Bootstrap the Minecraft client installation."
    "${packages.minecraftBootstrap}/bin/bootstrap-minecraft-client";

  "minecraft-deploy" =
    mkApp "Deploy the Minecraft client artifacts."
    "${packages.minecraftDeploy}/bin/deploy-minecraft-client";

  "validate-host" =
    mkApp "Validate a host definition from this flake."
    "${packages."validate-host"}/bin/validate-host";

  "admit-host" =
    mkApp "Promote staged hosts into nix-secrets/hosts.nix, regenerate nix-secrets/.sops.yaml, and re-encrypt secrets.yaml."
    "${packages."admit-host"}/bin/admit-host";

  enroll =
    mkApp "Remote-drive a fresh NixOS host into the secrets trust mesh (admit + rsync secrets + nixos-rebuild switch)."
    "${packages.enroll}/bin/enroll";

  install =
    mkApp "Install this configuration onto a target host."
    "${packages.install}/bin/install-config";

  "ubuntu-home-install-test" =
    mkApp "Run the Ubuntu home-only install test harness."
    "${packages."ubuntu-home-install-test"}/bin/ubuntu-home-install-test";

  "nixos-system-install-test" =
    mkApp "Run the NixOS system install test harness."
    "${packages."nixos-system-install-test"}/bin/nixos-system-install-test";

  default =
    mkApp "Sync the Minecraft client assets."
    "${packages.minecraftSync}/bin/sync-minecraft-client";
}
