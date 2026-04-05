{
  description = "Public stub for nix-secrets. Override with a real nix-secrets flake for private builds.";

  outputs = _: {
    # No-op modules so public builds evaluate without access to real secrets.
    # Override with:
    #   --override-input nix-secrets path:/path/to/private/nix-secrets
    # or a git+ssh:// URL for CI/deployment.
    nixosModules.default = {...}: {};
    homeManagerModules.default = {...}: {};
  };
}
