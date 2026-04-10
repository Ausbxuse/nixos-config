# Digital Asset Management Plan

## Goal

A declarative, reproducible system for managing all personal digital assets,
robust enough to recover from any single device loss with minimal manual effort.

## Threat Model

| Threat                 | Protection                                       |
| ---------------------- | ------------------------------------------------ |
| Lose one device        | Syncthing mesh — data on 2+ devices at all times |
| Lose all devices       | Master age key on paper/USB + external drive     |
| Stolen device          | LUKS full-disk encryption                        |
| Locked out of accounts | TOTP seeds + passwords backed up                 |
| Accidental deletion    | Syncthing versioning + external drive backup     |

## Architecture

```
        Phone (Android)
       ╱       ╲
      ╱         ╲
   razy ─────── timy
      ╲         ╱
       ╲       ╱
        VPS
    (critical + important only,
     encrypted via Syncthing
     untrusted device)
```

All devices form a full Syncthing mesh. No chains — every device syncs directly
with every other. Losing any one device leaves data intact on the rest.

The VPS is an always-on "blind" node: it stores encrypted blobs via Syncthing's
untrusted device feature. It can relay data but never read it.

External drive backup (rsync, periodic) provides cold disaster recovery.

## Data Classification

| Tier          | Examples                                         | Sync                            | Backup          |
| ------------- | ------------------------------------------------ | ------------------------------- | --------------- |
| **Critical**  | Age key, TOTP seeds, API keys, app passwords     | sops-nix in git                 | VPS + ext drive |
| **Important** | Documents, notes, KeePassXC vault, private repos | Syncthing (all + VPS)           | ext drive       |
| **Media**     | Phone photos/video (~200GB), music               | Syncthing (razy + timy + phone) | ext drive       |
| **Ephemeral** | Game saves, downloads, caches                    | Syncthing (optional)            | none            |

## Tools

| Tool          | Platform        | Purpose                                      |
| ------------- | --------------- | -------------------------------------------- |
| **sops-nix**  | Laptops (NixOS) | Infrastructure secrets: API keys, TOTP seeds |
| **KeePassXC** | Laptops + Phone | Day-to-day passwords (website logins, apps)  |
| **Aegis**     | Phone           | TOTP 2FA code generator                      |
| **Syncthing** | All devices     | File sync mesh                               |
| **rsync**     | Laptops         | External drive cold backup                   |
| **gh**        | Laptops         | Auto-add SSH keys to GitHub on rebuild       |

## Syncthing Folder Layout

```
~/sync/
├── phone-media/     # Phone camera roll (phone + razy + timy)
├── music/           # Music library (all devices)
├── documents/       # Notes, docs, KeePassXC vault, Aegis backup (all + VPS)
└── archive/         # Archived media (razy + timy, too big for VPS/phone)
```

Phone sends `phone-media/`, receives `music/` + `documents/`.
VPS only syncs `documents/` (encrypted, within 72GB limit).

## Secrets Management

### Public/Private Split

```
nix-config (public)                    nix-secrets (private)
├── modules/                             ├── secrets.yaml           # sops-encrypted
│   ├── home/                            ├── syncthing/
│   │   ├── syncthing/                   │   ├── devices.nix        # device IDs
│   │   │   └── default.nix  ◄─imports── │   └── folders.nix        # folder config
│   │   └── sops.nix                     ├── backup/
│   └── nixos/                           │   └── targets.nix        # VPS address, paths
│       └── backup.nix       ◄─imports── │
```

Public repo: module logic, options, defaults.
Private repo (nix-secrets): device IDs, addresses, credentials.

### Age Key Strategy

Per-host SSH-derived age keys + one offline master key:

```yaml
# .sops.yaml
keys:
  - &razy age1... # derived from razy's SSH host key
  - &timy age1... # derived from timy's SSH host key
  - &master age1... # offline master key (paper + USB)
creation_rules:
  - path_regex: secrets\.yaml$
    key_groups:
      - age:
          - *razy
          - *timy
          - *master
```

sops-nix config:

```nix
sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
sops.age.keyFile = "/var/lib/sops-nix/key.txt";
sops.age.generateKey = true;
```

### What Goes in secrets.yaml

- API keys (anthropic, gemini, github, huggingface)
- TOTP seeds (GitHub, email, any 2FA-enabled services)
- Application passwords
- GitHub personal access token (for automated gh auth)
- Syncthing encryption password (for VPS untrusted device)

## External Drive Backup

- NixOS module: udev rule + systemd service
- Plug in drive → auto-detects → rsync runs → notification on completion
- Backs up: `~/sync/` (all media + documents) + nix-config + nix-secrets repos
- Periodic reminder if drive hasn't been connected recently

## Recovery Scenarios

### Lost Phone

1. Buy new phone
2. Call carrier → SIM replacement (same number)
3. Install Syncthing → scan QR from razy → folders resync
4. Install KeePassXC → vault arrives via Syncthing → all passwords available
5. Install Aegis → restore from encrypted backup in Syncthing
6. Re-login to apps using passwords + TOTP codes
7. Bank apps: re-install, authenticate via SMS + password

**Time: ~30 min hands-on, hours for media resync in background.**

### Lost Laptop (e.g. razy)

1. Install NixOS on new machine (SSH host key auto-generated)
2. Get new age public key: `cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age`
3. On timy: add new key to `.sops.yaml`, run `sops updatekeys`, git push
4. On new machine: `git pull && sudo nixos-rebuild switch --flake .#razy`
5. Syncthing reconnects → accept new device on timy + phone → data resyncs
6. `gh auth login --with-token` → `gh ssh-key add` → GitHub access restored

**Time: ~30 min hands-on, hours for media resync.**

### Lost VPS

1. enroll new VPS, install NixOS
2. Syncthing rejoins mesh → razy/timy re-encrypt and resync to it
3. Restore git server from local repo copies

**Time: ~1 hour.**

### Lost Everything Except External Drive

1. Age key from paper/USB
2. rsync restore from external drive to new machine
3. Rebuild NixOS: `nix run .#install -- --host razy`
4. Place master age key → sops decrypts → secrets available
5. Add new SSH-derived key to `.sops.yaml`, remove master key from disk
6. Set up Syncthing on new phone + devices

**Time: ~1-2 hours.**

### Lost Everything Including External Drive

1. Age key from paper/USB
2. VPS still has critical + important tiers (encrypted)
3. Rebuild machine → decrypt VPS data → documents + secrets recovered
4. **Media (200GB) is lost** — this is the one unrecoverable scenario

## Implementation Order

1. **nix-secrets** — SSH-derived age keys, API keys, TOTP seeds, app passwords, public/private split
2. **Syncthing mesh** — declarative module, full mesh, VPS as encrypted node
3. **Auto-backup to external drive** — udev + systemd rsync, notifications
4. **Reproducible phone setup** — Aegis, KeePassXC, Syncthing on Android, document steps

## Future Considerations (Not Now)

- **Secure Boot (Lanzaboote)** — protects against evil maid attacks, but loses GRUB theming
- **Impermanence** — wipe root on every boot for full reproducibility, high setup cost
- **Second external drive at separate location** — closes the "lose everything" gap for media
- **VPS block storage upgrade** — ~$5-15/mo for full media backup on VPS
