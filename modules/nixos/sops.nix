{inputs, ...}: {
  # Forwards to the nix-secrets flake input's NixOS module.
  # - In public builds the stub at ./secrets/nix-secrets is a no-op.
  # - Override nix-secrets at build time to inject real secrets. See
  #   secrets/nix-secrets/README.md.
  imports = [inputs.nix-secrets.nixosModules.default];
}
