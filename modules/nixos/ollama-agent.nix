{lib, ...}: {
  environment.etc."ollama/base".text = "1\n";
  environment.etc."nixos/base".text = "1\n";

  specialisation.docked.configuration = {
    # Avoid GRUB's fallback to the Nix store symlink mtime for specialisations.
    boot.loader.grub.configurationName = lib.mkDefault "docked";

    environment.etc."nixos/docked".text = "1\n";
  };
}
