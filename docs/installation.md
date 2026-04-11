# Installation And Bring-Up

This repo now treats installation as a flake app, not a pile of custom shell scripts.

The primary entrypoint is:

```bash
nix run .#install -- ...
```

Or directly from a remote machine without cloning first:

```bash
nix run github:ausbxuse/nix-config#install -- ...
```

This document covers:

- installing a known NixOS host
- installing a new custom NixOS host
- setting up a new Home Manager-only host
- validating a machine after installation
- common post-install tweaks

## Concepts

There are two sources of truth involved in the new flow.

### Global repo settings

[globals.nix](/home/zhenyu/src/public/nix-config/globals.nix) is for repo-wide values only:

- username
- supported systems

It should not be the place where per-host architecture or per-host role lives.

### Machine registry

[machines/defs.nix](/home/zhenyu/src/public/nix-config/machines/defs.nix) is the public staging registry for hosts that have not been admitted yet.

Canonical admitted hosts live in private `nix-secrets/hosts.nix`, which is merged over the public staging defs at evaluation time.

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
- install behavior for staged or admitted hosts
- default username and profile selection
- host list generation for checks

Use public `machines/defs.nix` for pre-admission bootstrap entries. Once a host is enrolled, its long-term canonical definition belongs in private `nix-secrets/hosts.nix`.

## Quick Start

### Known host install

Use this when the host already exists in the merged host registry and has corresponding files under [machines](/home/zhenyu/src/public/nix-config/machines).

Example:

```bash
nix run github:ausbxuse/nix-config#install -- --host razy
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

### custom install for a new machine

Use this when the host does not exist in the repo yet and you want to bootstrap fast.

Example:

```bash
nix run github:ausbxuse/nix-config#install -- --host newbox --nixos --home
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

This path is meant for fast bring-up. After the machine is proven working, keep any pre-admission staging entry in [machines/defs.nix](/home/zhenyu/src/public/nix-config/machines/defs.nix) only until enrollment. The admitted long-term definition should live in private `nix-secrets/hosts.nix`, with machine files committed under [machines](/home/zhenyu/src/public/nix-config/machines).

### Home Manager-only setup

Use this when you only want the home configuration on an existing Linux system.

Example for a known home-capable host:

```bash
nix run github:ausbxuse/nix-config#install -- --host earthy --home
```

Example for a brand new custom machine:

```bash
nix run github:ausbxuse/nix-config#install -- --host laptop-work --home
```

In Home Manager-only mode the installer:

- skips disk formatting and `nixos-install`
- generates an custom home config when necessary
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
  - [machines/<name>/nixos.nix](/home/zhenyu/src/public/nix-config/machines)
  - [machines/defs.nix](/home/zhenyu/src/public/nix-config/machines/defs.nix) entry

Recommended command:

```bash
nix run github:ausbxuse/nix-config#install -- --host uni
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
nix run github:ausbxuse/nix-config#install -- --host uni --disk /dev/nvme1n1
```

This is the safest pattern for repeatability.

### Failure Mode: Dirty Checkout Changes The Installed System

Symptom:

- install succeeds, but the installed machine boots differently from what you expect
- debugging becomes confusing because `nix run .#install` and the resulting system do not seem to match

Cause:

- if the installer copies from your live working tree instead of the packaged flake snapshot, any local dirty changes can silently change what gets installed

Why it is subtle:

- the install command itself still looks normal
- the boot failure can show up much later, for example as initrd waiting for the wrong LUKS path

Quick check:

- if removing `.git` from the copied repo suddenly makes the install behave correctly, you were probably installing from the live checkout instead of the packaged source

Current expected behavior:

- the installer always installs from the packaged `REPO_SOURCE` snapshot
- the repo copied into the target is that same snapshot, not your dirty checkout

## Installing A New NixOS Host

This is the fast bootstrap path for a machine that is not yet committed to the repo.

Example:

```bash
nix run github:ausbxuse/nix-config#install -- --host razer-test --nixos --home
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
custom NixOS profile: portable-nvidia-gnome
custom home profile: personal-gnome
custom display profile: razy-current
Available disks:
  /dev/nvme0n1  1.8T  Samsung SSD  NVMe
Target disk: /dev/nvme0n1
custom swap size: 32G
Enter LUKS disk password:
```

The installer auto-detects:

- architecture via `uname -m`

For custom hosts, the installer does not infer a mode. Pass `--home`, `--nixos`, or both explicitly.

Examples:

```bash
nix run github:ausbxuse/nix-config#install -- --host earthy
# fails with: Nothing to do: pass --home and/or --nixos.

nix run github:ausbxuse/nix-config#install -- --host earthy --home
nix run github:ausbxuse/nix-config#install -- --host razer-test --nixos --home
```

The installer may suggest defaults for:

- NixOS profile
- disk

For example, if an NVIDIA GPU is visible via `lspci`, it currently suggests:

```text
portable-nvidia-gnome
```

For the display profile prompt, the value should match one of the profiles in [modules/home/display-profile.nix](/home/zhenyu/src/public/nix-config/modules/home/display-profile.nix), for example:

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

- `machines/defs.nix` overlaying the custom host entry
- `machines/<host>/hardware-configuration.nix`

The temporary host inventory overlay is for the install run only. It is not written back into your real repo automatically.

When the install succeeds, you should convert the custom host into a real host definition:

1. Add or keep a staging entry in [machines/defs.nix](/home/zhenyu/src/public/nix-config/machines/defs.nix) if you want to bootstrap admission from the public repo.
2. Create:
   - [machines/<host>/nixos.nix](/home/zhenyu/src/public/nix-config/machines) if needed
   - [machines/<host>/home.nix](/home/zhenyu/src/public/nix-config/machines) if needed
3. Move the generated hardware configuration into:
   - [machines/<host>/hardware-configuration.nix](/home/zhenyu/src/public/nix-config/machines)
4. Enroll the host so its canonical admitted entry lands in private `nix-secrets/hosts.nix`.
5. Rebuild from the committed repo afterward.

This custom path is for speed, not for long-term configuration ownership.

## Installing A New Home Manager-Only Host

For machines where you do not want NixOS installation, run Home Manager-only mode.

Known host:

```bash
nix run github:ausbxuse/nix-config#install -- --host earthy --home
```

custom host:

```bash
nix run github:ausbxuse/nix-config#install -- --host office-laptop --home
```

The installer will prompt for:

- home profile
- display profile

This is useful for:

- non-NixOS Linux
- temporary machines
- new cross-platform personal environments

If the machine should become a long-term tracked host later, stage it in [machines/defs.nix](/home/zhenyu/src/public/nix-config/machines/defs.nix), then enroll it so its canonical entry lands in private `nix-secrets/hosts.nix`, and create a real [machines/<host>/home.nix](/home/zhenyu/src/public/nix-config/machines) entry.

## Installer CLI Reference

The current help output is:

```text
Usage:
  nix run .#install -- [options]

Options:
  --host NAME              Known host name or a new custom host name
  --disk PATH              Target disk for NixOS installation
  --system SYSTEM          Override detected system, e.g. x86_64-linux
  --username NAME          Override the host user name
  --nixos      Enable or disable NixOS installation mode
  --home       Enable or disable Home Manager mode
  --nixos-profile NAME     Profile file basename under modules/profiles/nixos/
  --home-profile NAME      Profile file basename under modules/profiles/home/
  --display-profile NAME   Display profile for custom home configs
  --swap-size SIZE         Swapfile size for custom disk configs, e.g. 32G
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
nix run github:ausbxuse/nix-config#validate-host
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
sudo nixos-rebuild switch --flake ~/src/public/nix-config#<host>
```

And if needed:

```bash
home-manager switch --flake ~/src/public/nix-config#<username>@<host>
```

### Verify committed host metadata

Known-host installs and custom installs now override host metadata by writing a temporary `machines/defs.nix` in the installer worktree.

That means:

- the live install works immediately
- but you should still make sure the long-term host definition in `nix-secrets/hosts.nix` (or the temporary staging entry in [machines/defs.nix](/home/zhenyu/src/public/nix-config/machines/defs.nix) before enrollment) matches the intended username, profiles, disk path, and swap size

For permanent hosts, prefer committed host inventory data over relying on custom runtime overrides forever.

### Promote an custom host into the repo

If you installed an unknown machine interactively and want to keep it:

1. Add or keep a staging entry in [machines/defs.nix](/home/zhenyu/src/public/nix-config/machines/defs.nix) if you want to enroll from a public bootstrap record.
2. Create real host files.
3. Save and review `hardware-configuration.nix`.
4. Ensure the admitted canonical entry in private `nix-secrets/hosts.nix` carries the final `home` / `nixos` / `install` fields.
5. Run:

```bash
nix flake check --no-build
```

### Run host-specific bring-up notes

Some machines need manual verification beyond the generic validator.

For `razy`, see:

- [docs/razy-bringup.md](/home/zhenyu/src/public/nix-config/docs/razy-bringup.md)

That document covers the real debugging path and the machine-specific issues for the Razer Blade.

## Migration From The Old Install Scripts

The old scripts under [scripts](/home/zhenyu/src/public/nix-config/scripts):

- `install.sh`
- `install_home.sh`

should now be considered legacy. `install_portable.sh` has been folded into the
main installer as `--portable` mode:

```bash
NP_RUNTIME=bwrap nix-portable nix run .#install -- --portable --host earthy
```

The intended path is:

- `nix run github:ausbxuse/nix-config#install -- ...`
- `nix run .#validate-host`

The goal is to eliminate the old scripts entirely once the new flow has been exercised enough.
