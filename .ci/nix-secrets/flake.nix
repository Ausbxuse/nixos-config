{
  description = "CI stub for nix-secrets.";

  outputs = _: {
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
