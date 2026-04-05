# What?

- This is my nix configuration aimed to get deployed on my personal machines:
  - Asus Zenbook duo 2024 (Timy)
  - Alienware X17 R1 (Uni)
  - Lenovo Yoga 720 (Spacy)
  - A home configuration that can be used universally on other generic machines (Earthy)
    - This is often used with home-manager only for cross OS compatibility.
  - [x] servers (WIP)

# Why?

- Simple deployment. Eventually will support offline installation for local machines, according to [this](https://www.reddit.com/r/NixOS/comments/1co9spe/is_it_possible_to_do_offline_updates_of_nixpkgs/)
- Scalability. You can easily add a new configuration. Along with the first point, it makes configuring and deploying a new host easy as just running a single command.
- Maintenance. Maintaining takes a lot of work. Nix flake with git makes it easy to roll back in case of error.

# Operations

- **New host quick start** (one-page happy path: install → secrets → vault):
  - [docs/new-host-quickstart.md](/home/zhenyu/src/public/nixos-config/docs/new-host-quickstart.md)
- Installation and bring-up guide (detailed):
  - [docs/installation.md](/home/zhenyu/src/public/nixos-config/docs/installation.md)
- Full design / disaster recovery / trust model:
  - [docs/reproducing-from-scratch.md](/home/zhenyu/src/public/nixos-config/docs/reproducing-from-scratch.md)
- Machine-specific notes:
  - [docs/razy-bringup.md](/home/zhenyu/src/public/nixos-config/docs/razy-bringup.md)

# Future work

- [x] Single command remote deployment
- [x] Support servers running useful services
- [ ] remove legacy installation scripts after the new flake installer fully replaces them

# Minecraft notes

- Prism + declarative Minecraft currently builds a pinned `.mrpack` from [`modules/home/minecraft/sources.nix`](/home/zhenyu/src/public/nixos-config/modules/home/minecraft/sources.nix).
- Important failure mode: it is not enough to update `sources.dependencies."fabric-loader"` in Nix. The generated `modrinth.index.json` inside the `.mrpack` must also be rewritten.
- Symptom: Prism imports the pack, but launch fails with Fabric saying mods like `Chat Heads` or `Visible Traders` require `fabric-loader >= 0.17.0` while `0.16.14` is present.
- Root cause: the builder was preserving the base Fabulously Optimized pack's dependency block, so the final `.mrpack` still advertised the old loader even after `sources.nix` was updated.
- Fix: [`pkgs/minecraft/mk-mrpack.nix`](/home/zhenyu/src/public/nixos-config/pkgs/minecraft/mk-mrpack.nix) must rewrite `modrinth.index.json.dependencies`, not just the pack name/version.
