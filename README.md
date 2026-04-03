# NixOS Config

The canonical installation and bring-up guide is:

- [docs/installation.md](/home/zhenyu/src/public/nixos-config/docs/installation.md)

The short version:

```bash
nix run github:ausbxuse/nixos-config#install -- --host <host>
```

For post-install validation:

```bash
nix run .#validate-host
```

Useful local commands:

```bash
nix flake check --no-build
nix build .#gnome-iso
```
