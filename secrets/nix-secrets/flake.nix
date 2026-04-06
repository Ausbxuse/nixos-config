{
  description = "Public stub for nix-secrets. Override with a real nix-secrets flake for private builds.";

  outputs = _: {
    # No-op modules so public builds evaluate without access to real secrets.
    # Override with:
    #   --override-input nix-secrets path:/path/to/private/nix-secrets
    # or a git+ssh:// URL for CI/deployment.
    nixosModules.default = {lib, ...}: {
      options.sops.secrets = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options.path = lib.mkOption {
            type = lib.types.str;
            default = "/dev/null";
          };
        });
        default = {};
        description = "Stub: accepts secret declarations and provides dummy paths.";
      };
    };
    homeManagerModules.default = {lib, ...}: {
      # Declare a minimal sops.secrets option so modules like syncthing.nix
      # can unconditionally set sops.secrets without gating on whether the
      # real sops-nix module is loaded. In real builds this is shadowed by
      # the actual sops-nix home-manager module.
      options.sops.secrets = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options.path = lib.mkOption {
            type = lib.types.str;
            default = "/dev/null";
          };
        });
        default = {};
        description = "Stub: accepts secret declarations and provides dummy paths.";
      };
    };
  };
}
