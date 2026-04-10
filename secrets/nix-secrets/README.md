Public stub for the `nix-secrets` flake input.

This directory is a no-op flake so public builds of `nix-config` evaluate
without access to the private secrets repository. The real `nix-secrets` flake
lives on a private git server and exposes:

- `nixosModules.default` — NixOS-level sops-nix module (host SSH-derived age keys)
- `homeManagerModules.default` — home-manager-level sops-nix module (user age key file)
- `hosts.nix` — canonical admitted host registry merged over public staging defs
- `globals.nix` — private override for repo-wide values that should not live in the public repo
- `admin-access.nix` — private SSH authorized keys for the default admin user

To use real secrets, override the flake input at build time:

```bash
# Local development
nix build .#nixosConfigurations.razy.config.system.build.toplevel \
  --override-input nix-secrets path:$HOME/src/private/nix-secrets

# Deployment from a remote git server
nix build .#nixosConfigurations.razy.config.system.build.toplevel \
  --override-input nix-secrets git+ssh://git@zhenyuzhao.com/var/lib/git-server/nix-secrets
```

To add a new host:

1. On the new host: `cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age`
2. Record the host in `nix-secrets/hosts.nix`, for example:

```nix
{...}: {
  my-host = {
    system = "x86_64-linux";
    username = "zhenyu";
    sops.ageKey = "age1...";
    syncthing.deviceId = "ABCDEFG-HIJKLMN-...";
  };
}
```

3. Add the resulting age public key to `nix-secrets/.sops.yaml` under `keys:` and in the relevant `creation_rules`
4. Re-encrypt: `cd nix-secrets && sops updatekeys secrets.yaml`
5. Commit and push `nix-secrets`
