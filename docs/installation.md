# Installation And Bring-Up

This repo now treats installation as a flake app, not a pile of ad hoc shell scripts.

The primary entrypoint is:

```bash
nix run .#install -- ...
```

Or directly from a remote machine without cloning first:

```bash
nix run github:ausbxuse/nixos-config#install -- ...
```

This document covers:

- installing a known NixOS host
- installing a new ad hoc NixOS host
- setting up a new Home Manager-only host
- validating a machine after installation
- common post-install tweaks

## Concepts

There are two sources of truth involved in the new flow.

### Global repo settings

[globals.nix](/home/zhenyu/src/public/nixos-config/globals.nix) is for repo-wide values only:

- username
- human name
- email
- supported systems

It should not be the place where per-host architecture or per-host role lives.

### Machine registry

[machines/defs.nix](/home/zhenyu/src/public/nixos-config/machines/defs.nix) is the central machine inventory.

Each host definition can declare:

- `system`
- `username`
- `nixos = { enable; profile; }`
- `home = { enable; profile; displayProfile; }`
- `install = { layout; disk; swapSize; }`
- `platform`
- `visibility`

This drives:

- `nixosConfigurations`
- `homeConfigurations`
- install behavior for known hosts
- default username and profile selection
- host list generation for checks

If you are adding a real long-term machine to the repo, add it here first.

## Quick Start

### Known host install

Use this when the host already exists in [machines/defs.nix](/home/zhenyu/src/public/nixos-config/machines/defs.nix) and has corresponding files under [machines](/home/zhenyu/src/public/nixos-config/machines).

Example:

```bash
nix run github:ausbxuse/nixos-config#install -- --host razy
```

The installer will:

- load the host definition from the registry
- use that host's architecture
- ask for destructive confirmation
- ask for the target disk if needed
- ask for the LUKS password
- run `disko`
- generate and save `hardware-configuration.nix`
- run `nixos-install`
- optionally copy the repo into the new system

### Ad hoc install for a new machine

Use this when the host does not exist in the repo yet and you want to bootstrap fast.

Example:

```bash
nix run github:ausbxuse/nixos-config#install -- --host newbox --nixos --home
```

The installer will:

- auto-detect the architecture
- ask whether NixOS and/or Home Manager should be enabled
- ask for a NixOS profile if `--nixos` is enabled
- ask for a home profile if `--home` is enabled
- ask for a display profile if needed
- ask for disk and swap settings if doing NixOS installation
- generate temporary host files inside a worktree under `/tmp`
- install from that generated configuration

This path is meant for fast bring-up. After the machine is proven working, convert it into a real repo machine by adding it to [machines/defs.nix](/home/zhenyu/src/public/nixos-config/machines/defs.nix) and committing the machine files under [machines](/home/zhenyu/src/public/nixos-config/machines).

### Home Manager-only setup

Use this when you only want the home configuration on an existing Linux system.

Example for a known home-capable host:

```bash
nix run github:ausbxuse/nixos-config#install -- --host earthy --home --no-nixos
```

Example for a brand new ad hoc machine:

```bash
nix run github:ausbxuse/nixos-config#install -- --host laptop-work --home --no-nixos
```

In Home Manager-only mode the installer:

- skips disk formatting and `nixos-install`
- generates an ad hoc home config when necessary
- runs:

```bash
nix run nixpkgs#home-manager -- switch --flake '<worktree>#<user>@<host>'
```

## Detailed Flows

## Installing A Known NixOS Host

Prerequisites:

- booted into a NixOS live environment or another environment with Nix installed
- network access
- access to the target disk
- this repo must already contain:
  - [machines/<name>/nixos.nix](/home/zhenyu/src/public/nixos-config/machines)
  - [machines/defs.nix](/home/zhenyu/src/public/nixos-config/machines/defs.nix) entry

Recommended command:

```bash
nix run github:ausbxuse/nixos-config#install -- --host uni
```

What happens:

1. The installer reads the known host definition.
2. It uses the registered `system`, `username`, profiles, and install layout.
3. It prompts for the target disk if you did not pass `--disk`.
4. It writes a temporary `machines/defs.nix` overlay in the worktree with any runtime overrides.
5. It asks for the LUKS password and writes it temporarily to `/tmp/secret.key`.
6. It runs:

```bash
sudo disko --mode destroy,format,mount --flake .#<host>
sudo nixos-generate-config --no-filesystems --root /mnt
sudo nixos-install --root /mnt --flake .#<host>
```

7. It offers to copy the repo into the installed system.

Recommended explicit-disk variant:

```bash
nix run github:ausbxuse/nixos-config#install -- --host uni --disk /dev/nvme1n1
```

This is the safest pattern for repeatability.

## Installing A New NixOS Host

This is the fast bootstrap path for a machine that is not yet committed to the repo.

Example:

```bash
nix run github:ausbxuse/nixos-config#install -- --host razer-test --nixos --home
```

The installer will ask for:

- target disk
- NixOS profile
- home profile
- display profile
- swap size
- LUKS password

Typical interactive answers for a new laptop might look like:

```text
Host name for install or bootstrap: razer-test
Ad hoc NixOS profile: portable-nvidia-gnome
Ad hoc home profile: personal-gnome
Ad hoc display profile: razy-current
Available disks:
  /dev/nvme0n1  1.8T  Samsung SSD  NVMe
Target disk: /dev/nvme0n1
Ad hoc swap size: 32G
Enter LUKS disk password:
```

The installer auto-detects:

- architecture via `uname -m`

For ad hoc hosts, the installer does not infer a mode. Pass `--home`, `--nixos`, or both explicitly.

Examples:

```bash
nix run github:ausbxuse/nixos-config#install -- --host earthy
# fails with: Nothing to do: pass --home and/or --nixos.

nix run github:ausbxuse/nixos-config#install -- --host earthy --home --no-nixos
nix run github:ausbxuse/nixos-config#install -- --host razer-test --nixos --home
```

The installer may suggest defaults for:

- NixOS profile
- disk

For example, if an NVIDIA GPU is visible via `lspci`, it currently suggests:

```text
portable-nvidia-gnome
```

For the display profile prompt, the value should match one of the profiles in [modules/home/display-profile.nix](/home/zhenyu/src/public/nixos-config/modules/home/display-profile.nix), for example:

- `gnome-default`
- `razy-current`
- `laptop-2_5k`
- `external-4k`
- `docked-dual`

For disk and swap prompts:

- disk should be a whole-disk device like `/dev/nvme0n1`
- swap should be a Nix size string like `16G`, `32G`, or `8G`

The temporary worktree is created under:

```text
/tmp/nixos-installer.XXXXXX
```

Inside that worktree, the installer may generate:

- `machines/defs.nix` overlaying the ad hoc host entry
- `machines/<host>/hardware-configuration.nix`

The temporary host inventory overlay is for the install run only. It is not written back into your real repo automatically.

When the install succeeds, you should convert the ad hoc host into a real host definition:

1. Add the host to [machines/defs.nix](/home/zhenyu/src/public/nixos-config/machines/defs.nix).
2. Create:
   - [machines/<host>/nixos.nix](/home/zhenyu/src/public/nixos-config/machines) if needed
   - [machines/<host>/home.nix](/home/zhenyu/src/public/nixos-config/machines) if needed
3. Move the generated hardware configuration into:
   - [machines/<host>/hardware-configuration.nix](/home/zhenyu/src/public/nixos-config/machines)
4. Rebuild from the committed repo afterward.

This ad hoc path is for speed, not for long-term configuration ownership.

## Installing A New Home Manager-Only Host

For machines where you do not want NixOS installation, run Home Manager-only mode.

Known host:

```bash
nix run github:ausbxuse/nixos-config#install -- --host earthy --home --no-nixos
```

Ad hoc host:

```bash
nix run github:ausbxuse/nixos-config#install -- --host office-laptop --home --no-nixos
```

The installer will prompt for:

- home profile
- display profile

This is useful for:

- non-NixOS Linux
- temporary machines
- new cross-platform personal environments

If the machine should become a long-term tracked host later, add it to [machines/defs.nix](/home/zhenyu/src/public/nixos-config/machines/defs.nix) and create a real [machines/<host>/home.nix](/home/zhenyu/src/public/nixos-config/machines) entry.

## Installer CLI Reference

The current help output is:

```text
Usage:
  nix run .#install -- [options]

Options:
  --host NAME              Known host name or a new ad hoc host name
  --disk PATH              Target disk for NixOS installation
  --system SYSTEM          Override detected system, e.g. x86_64-linux
  --username NAME          Override the host user name
  --nixos / --no-nixos     Enable or disable NixOS installation mode
  --home / --no-home       Enable or disable Home Manager mode
  --nixos-profile NAME     Profile file basename under modules/profiles/nixos/
  --home-profile NAME      Profile file basename under modules/profiles/home/
  --display-profile NAME   Display profile for ad hoc home configs
  --swap-size SIZE         Swapfile size for ad hoc disk configs, e.g. 32G
  --copy-repo yes|no       Copy the resulting repo into the installed system
  --repo-dest PATH         Destination for copied repo inside the target root
  -y, --yes                Accept destructive prompts
```

## Post-Install Validation

After the first boot, run:

```bash
nix run .#validate-host
```

Or directly from GitHub if the repo is not yet copied locally:

```bash
nix run github:ausbxuse/nixos-config#validate-host
```

The validator currently checks:

- `systemctl is-system-running`
- PipeWire sink presence
- ALSA playback device enumeration
- ALSA capture device enumeration
- V4L2 camera enumeration
- brightness device exposure
- `nvidia-smi` when an NVIDIA GPU is present

This is not a full bring-up test suite. It is a fast sanity pass after install.

## Suggested Validation Workflow

After installation and first boot:

1. Run:

```bash
nix run .#validate-host
```

2. Check flake evaluation:

```bash
nix flake check --no-build
```

3. Check that the expected host outputs evaluate:

```bash
nix build .#checks.x86_64-linux.nixos-<host>
nix build .#checks.x86_64-linux.home-<host>
```

4. Confirm:

- internal audio works
- suspend/resume works
- Wi-Fi and Bluetooth work
- webcam works
- brightness keys work
- GPU path matches expectations
- GNOME scaling and monitors look correct

## Post-Install Tweaks

These are the common follow-up tasks after the base install succeeds.

### Copy or restore secrets

The current secret flow is intentionally minimal:

- the repo optionally consumes a private `nix-secrets` checkout via the `nix-secrets` flake input
- Home Manager enables `sops-nix` only if `nix-secrets/secrets.yaml` exists
- decryption expects an age key at `~/.config/sops/age/keys.txt`
- the repo does not currently bootstrap SSH keys or clone private secrets for you

So after a fresh install, secret-backed configuration only works if you manually provide:

- SSH access to your private Git remote
- your private `nix-secrets` checkout or flake override
- your age key file at `~/.config/sops/age/keys.txt`

If Home Manager warns that `nix-secrets/secrets.yaml` is missing, secret-backed Home Manager config was skipped for that build.

### Rebuild from the local checkout

If you copied the repo into the target system, switch again from the local tree once the machine is up:

```bash
sudo nixos-rebuild switch --flake ~/src/public/nixos-config#<host>
```

And if needed:

```bash
home-manager switch --flake ~/src/public/nixos-config#<username>@<host>
```

### Verify committed host metadata

Known-host installs and ad hoc installs now override host metadata by writing a temporary `machines/defs.nix` in the installer worktree.

That means:

- the live install works immediately
- but you should still make sure the committed [machines/defs.nix](/home/zhenyu/src/public/nixos-config/machines/defs.nix) entry matches the long-term intended username, profiles, disk path, and swap size

For permanent hosts, prefer committed host inventory data over relying on ad hoc runtime overrides forever.

### Promote an ad hoc host into the repo

If you installed an unknown machine interactively and want to keep it:

1. Add a real entry to [machines/defs.nix](/home/zhenyu/src/public/nixos-config/machines/defs.nix).
2. Create real host files.
3. Save and review `hardware-configuration.nix`.
4. Move any ad hoc profile choice into the committed `home` / `nixos` / `install` fields.
5. Run:

```bash
nix flake check --no-build
```

### Run host-specific bring-up notes

Some machines need manual verification beyond the generic validator.

For `razy`, see:

- [docs/razy-bringup.md](/home/zhenyu/src/public/nixos-config/docs/razy-bringup.md)

That document covers the real debugging path and the machine-specific issues for the Razer Blade.

## Migration From The Old Install Scripts

The old scripts under [scripts](/home/zhenyu/src/public/nixos-config/scripts):

- `install.sh`
- `install_home.sh`
- `install_portable.sh`

should now be considered legacy.

The intended path is:

- `nix run github:ausbxuse/nixos-config#install -- ...`
- `nix run .#validate-host`

The goal is to eliminate the old scripts entirely once the new flow has been exercised enough.
