# Recovery USB drive

## What it does

One USB drive, two partitions:

| Partition | Format | Label           | Contents                                        |
| --------- | ------ | --------------- | ----------------------------------------------- |
| 1 (8 GiB) | FAT32  | `NIXOS_INSTALL` | Bootable NixOS installer ISO                    |
| 2 (rest)  | ext4   | `RECOVERY`      | Recovery bundle + restic backups + media mirror |

Backups are manual — run `just backup-bundle` with the drive plugged in.
No auto-trigger on plug-in, so you can safely mount and restore without
risking corrupted files overwriting good backups.

## Setup

### 1. Partition the drive

```bash
sudo nix run .#setup-recovery-usb
```

Follow the prompts. It will print a UUID at the end.

### 2. Configure

Edit the target host entry in private `nix-secrets/hosts.nix`:

```nix
razy = {
  recovery.partUuid = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx";  # from step 1
};
```

Add the restic password to nix-secrets:

```bash
cd ~/src/private/nix-secrets
sops set secrets.yaml '["recovery-restic-password"]' '"your-restic-password"'
```

### 3. Rebuild

```bash
sudo nixos-rebuild switch --flake .#$(hostname)
```

Done. The udev rule is now active.

### 4. Write the installer ISO (optional)

```bash
just refresh-installer-usb /dev/sdX1
```

## Running a backup

Plug in the drive, then:

```bash
just backup-bundle
```

The service:

1. Mounts the RECOVERY partition
2. Creates `recovery-bundle.tar` containing:
   - Host SSH keys (your sops trust anchor)
   - Git mirror of nix-config
   - Git mirror of nix-secrets
   - Entire `~/vault/` (KeePassXC database + keyfile + notes)
3. Runs `restic backup ~/` (excludes caches, build artifacts, media)
4. Rsyncs `~/Media/{Pictures,Videos,Music,Audio}/` to the drive
5. Sends a desktop notification when done
6. Unmounts

Check status: `journalctl -u recovery-backup.service`

## Restoring

### Extract the bundle

```bash
tar xvf /mnt/recovery/recovery-bundle.tar -C /tmp
```

### Scenario: reinstall an existing host

The host's SSH key is in the bundle. Restore it before the first boot so sops-nix can decrypt secrets:

1. Boot from the installer (partition 1)
2. Run `nix run .#install`
3. Before rebooting, restore the host key:
   ```bash
   mount /dev/sdX2 /mnt/recovery
   tar xvf /mnt/recovery/recovery-bundle.tar -C /tmp
   sudo cp /tmp/recovery-bundle/host-keys/$(hostname)/ssh_host_ed25519_key* /mnt/etc/ssh/
   sudo chmod 600 /mnt/etc/ssh/ssh_host_ed25519_key
   ```
4. Reboot. The host inherits its prior identity. No re-admission needed.

### Scenario: all hosts lost, bootstrap from scratch

1. Boot any machine from the installer
2. Extract the bundle (see above)
3. Install NixOS, restoring that host's SSH key onto the new hardware
4. The new machine takes over the old host's sops identity
5. Rebuild, then rotate to a fresh key:
   ```bash
   admit-host --set-host-key $(hostname) $(ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub)
   ```

### Scenario: file corruption on laptop

Restic keeps versioned snapshots of `~/`. Media is rsynced as-is.

**Restore specific files from restic:**

```bash
sudo mount UUID=<recovery-uuid> /mnt/recovery
export RESTIC_REPOSITORY=/mnt/recovery/restic
export RESTIC_PASSWORD=<your-restic-password>

# List snapshots
restic snapshots

# Browse a snapshot
restic ls latest

# Restore specific files
restic restore latest --target /tmp/restore --include "Documents/important.pdf"

# Restore everything
restic restore latest --target /tmp/restore
```

**Restore media directly** (no restic needed — plain files):

```bash
sudo mount UUID=<recovery-uuid> /mnt/recovery
cp /mnt/recovery/media/Pictures/photo.jpg ~/Media/Pictures/
# or restore all media:
rsync -a /mnt/recovery/media/ ~/Media/
```

**What about corrupted files overwriting good backups?**

Since backups are manual, you're in control. If you suspect corruption,
mount the drive and restore _before_ running `just backup-bundle`:

```bash
sudo mount UUID=<recovery-uuid> /mnt/recovery
# restore what you need, then unmount
sudo umount /mnt/recovery
```

If you do run a backup with corrupted files:

- **Restic**: safe. Append-only with versioned snapshots. Use `restic restore <older-snapshot-id>` to get the good version.
- **Media rsync**: not safe. Rsync mirrors the current state — a corrupted file replaces the good copy.
- **Recovery bundle**: mostly safe. Git mirrors have full history. Vault has syncthing versioning on other hosts as a safety net.

## What's backed up where

| Data                                    | Backup method        | Versioned?                           | Safe from corruption?                           |
| --------------------------------------- | -------------------- | ------------------------------------ | ----------------------------------------------- |
| `~/` (minus Media, caches)              | restic snapshots     | Yes (10 last + daily/weekly/monthly) | Yes                                             |
| `~/Media/{Pictures,Videos,Music,Audio}` | rsync mirror         | No (latest only)                     | No                                              |
| Host SSH keys                           | recovery bundle      | No (latest only)                     | N/A (keys don't corrupt)                        |
| nix-config                              | git mirror in bundle | Yes (full git history)               | Yes                                             |
| nix-secrets                             | git mirror in bundle | Yes (full git history)               | Yes                                             |
| `~/vault/`                              | copy in bundle       | No (latest only)                     | Partially (syncthing versioning on other hosts) |
