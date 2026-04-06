#!/usr/bin/env bash
# recovery-backup: create recovery bundle, restic backup, and media sync.
#
# Called by the recovery-backup systemd service (triggered by udev on USB
# plug-in) or manually via `just backup-bundle`.
#
# Expected environment (set by the systemd unit):
#   RECOVERY_MOUNT      mount point for RECOVERY partition
#   RECOVERY_UUID       UUID of the RECOVERY partition
#   USERNAME            user to back up
#   HOME_DIR            /home/$USERNAME
#   RESTIC_REPOSITORY   path to restic repo on drive
#   RESTIC_PASSWORD_FILE  sops-decrypted restic password
#   EXCLUDE_FILE        path to restic exclude patterns

set -euo pipefail

RECOVERY_MOUNT="${RECOVERY_MOUNT:-/mnt/recovery}"
MOUNTED=0

cleanup() {
  if [[ $MOUNTED -eq 1 ]]; then
    umount "$RECOVERY_MOUNT" 2>/dev/null || true
  fi
  if [[ -n "${BUNDLE_TMP:-}" && -d "${BUNDLE_TMP:-}" ]]; then
    rm -rf "$BUNDLE_TMP"
  fi
}
trap cleanup EXIT

die()  { printf 'recovery-backup: %s\n' "$*" >&2; exit 1; }
info() { printf ':: %s\n' "$*"; }

notify() {
  local uid
  uid=$(id -u "$USERNAME" 2>/dev/null) || return 0
  runuser -u "$USERNAME" -- env \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
    notify-send -a "Recovery Backup" "$@" 2>/dev/null || true
}

# ------------------------------------------------------------------ preflight

[[ -n "${RECOVERY_UUID:-}" ]]       || die "RECOVERY_UUID not set"
[[ -n "${USERNAME:-}" ]]            || die "USERNAME not set"
[[ -n "${HOME_DIR:-}" ]]            || die "HOME_DIR not set"
[[ -n "${RESTIC_REPOSITORY:-}" ]]   || die "RESTIC_REPOSITORY not set"
[[ -n "${RESTIC_PASSWORD_FILE:-}" ]] || die "RESTIC_PASSWORD_FILE not set"
[[ -n "${EXCLUDE_FILE:-}" ]]        || die "EXCLUDE_FILE not set"

# ------------------------------------------------------------------ mount

info "mounting RECOVERY partition"
mkdir -p "$RECOVERY_MOUNT"
mount -o rw "UUID=$RECOVERY_UUID" "$RECOVERY_MOUNT"
MOUNTED=1

notify "Backup starting..."

# ------------------------------------------------------------------ bundle

info "creating recovery bundle"
BUNDLE_TMP=$(mktemp -d)
BUNDLE_DIR="$BUNDLE_TMP/recovery-bundle"
mkdir -p "$BUNDLE_DIR/host-keys/$(hostname)"

# Host SSH keys
cp /etc/ssh/ssh_host_ed25519_key     "$BUNDLE_DIR/host-keys/$(hostname)/" 2>/dev/null || true
cp /etc/ssh/ssh_host_ed25519_key.pub "$BUNDLE_DIR/host-keys/$(hostname)/" 2>/dev/null || true

# Git repos (mirror clones for minimal size)
if [[ -d "$HOME_DIR/src/public/nixos-config/.git" ]]; then
  git clone --mirror "$HOME_DIR/src/public/nixos-config" \
    "$BUNDLE_DIR/nixos-config.git" 2>/dev/null || true
fi
if [[ -d "$HOME_DIR/src/private/nix-secrets/.git" ]]; then
  git clone --mirror "$HOME_DIR/src/private/nix-secrets" \
    "$BUNDLE_DIR/nix-secrets.git" 2>/dev/null || true
fi

# Vault
if [[ -d "$HOME_DIR/vault" ]]; then
  cp -a "$HOME_DIR/vault" "$BUNDLE_DIR/vault"
fi

# Manifest
printf 'Recovery bundle created %s on %s\n\nContents:\n' \
  "$(date -Iseconds)" "$(hostname)" > "$BUNDLE_DIR/MANIFEST"
find "$BUNDLE_DIR" -type f | sed "s|$BUNDLE_DIR/||" >> "$BUNDLE_DIR/MANIFEST"

# Write bundle
info "writing bundle"
tar -C "$BUNDLE_TMP" -cf "$RECOVERY_MOUNT/recovery-bundle.tar" recovery-bundle
rm -rf "$BUNDLE_TMP"
BUNDLE_TMP=""
info "bundle written to $RECOVERY_MOUNT/recovery-bundle.tar"

# ------------------------------------------------------------------ restic

info "running restic backup"
export RESTIC_REPOSITORY
export RESTIC_PASSWORD_FILE
restic backup "$HOME_DIR" \
  --exclude-file="$EXCLUDE_FILE" \
  --one-file-system \
  --tag auto \
  --hostname "$(hostname)"
restic forget \
  --keep-last 10 \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 6 \
  --prune
info "restic backup complete"

# ------------------------------------------------------------------ media

info "syncing media"
mkdir -p "$RECOVERY_MOUNT/media"
for dir in Pictures Videos Music Audio; do
  if [[ -d "$HOME_DIR/Media/$dir" ]]; then
    rsync -a --delete "$HOME_DIR/Media/$dir/" "$RECOVERY_MOUNT/media/$dir/"
  fi
done
info "media sync complete"

# ------------------------------------------------------------------ done

notify "Backup complete."
info "recovery backup finished"
