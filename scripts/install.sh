#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly REPO_URL="https://github.com/ausbxuse/nixos-config"
readonly DEFAULT_CLONE_DIR="${PWD}/nixos-config"
readonly DEFAULT_TARGET=".#spacy"
readonly DEFAULT_COPY_REPO="yes"
readonly SECRET_KEY_PATH="/tmp/secret.key"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -f "$SECRET_KEY_PATH" ]]; then
    sudo rm -f "$SECRET_KEY_PATH"
  fi
  if [[ -n "${WORKTREE:-}" && -d "${WORKTREE:-}" && "${KEEP_WORKTREE:-0}" != "1" ]]; then
    rm -rf "$WORKTREE"
  fi
}
trap cleanup EXIT

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: $cmd"
  done
}

confirm() {
  local prompt=$1
  local default=${2:-N}
  local reply

  if [[ "$default" == "Y" ]]; then
    read -r -p "$prompt [Y/n] " reply
    [[ -z "$reply" || "$reply" =~ ^[Yy]$ ]]
  else
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
  fi
}

is_nixos_config_repo() {
  local dir=$1
  [[ -d "$dir/.git" && -f "$dir/flake.nix" && -d "$dir/hosts" && -d "$dir/scripts" ]]
}

find_repo_root() {
  local dir=$1

  while [[ "$dir" != "/" ]]; do
    if is_nixos_config_repo "$dir"; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done

  return 1
}

select_repo() {
  local detected_repo clone_dir reply

  if detected_repo=$(find_repo_root "$PWD"); then
    info "Detected nixos-config repo at $detected_repo"
    read -e -i "$detected_repo" -rp "Repository directory (Enter to use detected repo): " reply
    REPO_DIR=${reply:-$detected_repo}
    [[ -d "$REPO_DIR/.git" ]] || die "Expected a git repo at: $REPO_DIR"
  else
    read -e -i "$DEFAULT_CLONE_DIR" -rp "Clone nixos-config into: " clone_dir
    [[ -n "${clone_dir:-}" ]] || die "Clone directory cannot be empty."
    [[ ! -e "$clone_dir" ]] || die "Path already exists: $clone_dir"
    git clone "$REPO_URL" "$clone_dir"
    REPO_DIR=$clone_dir
  fi

  is_nixos_config_repo "$REPO_DIR" || die "Not a nixos-config repo: $REPO_DIR"
}

prepare_repo() {
  WORKTREE=$(mktemp -d "${TMPDIR:-/tmp}/nixos-install.XXXXXX")
  KEEP_WORKTREE=0
  rsync -a --delete --exclude '.git' "$REPO_DIR"/ "$WORKTREE"/
}

list_disks() {
  info "Available non-removable disks:"
  lsblk -ndo PATH,TYPE,RM,SIZE,MODEL,TRAN | awk '$2=="disk" && $3==0 {print "  " $0}'
}

prompt_target() {
  local target host
  read -e -i "$DEFAULT_TARGET" -rp "Enter flake target: " target
  [[ -n "${target:-}" ]] || die "Flake target cannot be empty."
  [[ "$target" == *#* ]] || die "Flake target must include a host, for example .#spacy"

  host="${target##*#}"
  [[ -n "${host:-}" ]] || die "Could not derive host from target: $target"
  [[ -d "$WORKTREE/hosts/$host" ]] || die "Host does not exist in repo: $host"

  TARGET=$target
  HOST=$host
}

prompt_disk() {
  local target_disk
  list_disks
  read -e -rp "Enter target disk path (for example /dev/nvme0n1): " target_disk
  [[ -n "${target_disk:-}" ]] || die "No disk selected."
  [[ -b "$target_disk" ]] || die "Not a block device: $target_disk"
  [[ "$(lsblk -ndo TYPE "$target_disk")" == "disk" ]] || die "Not a whole disk: $target_disk"
  TARGET_DISK=$target_disk
}

patch_disk_config_if_needed() {
  local host_disk="$WORKTREE/hosts/$HOST/disk.nix"
  local globals="$WORKTREE/globals.nix"

  if [[ -f "$host_disk" ]] && grep -Fq "@DISK@" "$host_disk"; then
    sed -i "s|@DISK@|$TARGET_DISK|g" "$host_disk"
    info "Patched hosts/$HOST/disk.nix with $TARGET_DISK"
    return
  fi

  if grep -Fq "@DISK@" "$globals"; then
    sed -i "s|@DISK@|$TARGET_DISK|g" "$globals"
    info "Patched globals.nix with $TARGET_DISK"
    return
  fi

  if [[ -f "$host_disk" ]] && grep -Fq "device = \"$TARGET_DISK\";" "$host_disk"; then
    info "Host disk config already points at $TARGET_DISK"
    return
  fi

  warn "No @DISK@ placeholder found and hosts/$HOST/disk.nix does not already match $TARGET_DISK"
  warn "Continuing without editing disk configuration. Verify hosts/$HOST/disk.nix manually if needed."
}

write_secret_key() {
  local luks_pw
  read -r -s -p "Enter LUKS disk password: " luks_pw
  printf '\n'
  [[ -n "${luks_pw:-}" ]] || die "LUKS password cannot be empty."

  printf '%s' "$luks_pw" | sudo tee "$SECRET_KEY_PATH" >/dev/null
  sudo chmod 600 "$SECRET_KEY_PATH"
}

run_install() {
  info "Target host: $HOST"
  info "Target disk: $TARGET_DISK"
  info "Working tree: $WORKTREE"

  confirm "This will destroy data on $TARGET_DISK. Continue?" || die "Aborted."

  (
    cd "$WORKTREE"

    sudo disko --mode destroy,format,mount --flake "$TARGET"
    sudo nixos-generate-config --no-filesystems --root /mnt
    sudo install -D -m 0644 /mnt/etc/nixos/hardware-configuration.nix "hosts/$HOST/hardware-configuration.nix"
    sudo nixos-install --root /mnt --flake ".#$HOST"
  )
}

copy_repo_to_target() {
  local reply
  read -e -i "$DEFAULT_COPY_REPO" -rp "Copy repo into /mnt/home/zhenyu/src/public/nixos-config? (yes/no): " reply

  case "$reply" in
    yes)
      sudo mkdir -p /mnt/home/zhenyu/src/public
      sudo rsync -a --delete "$WORKTREE"/ /mnt/home/zhenyu/src/public/nixos-config/
      ;;
    no)
      ;;
    *)
      die "Unsupported answer: $reply"
      ;;
  esac
}

main() {
  require_cmd git rsync lsblk disko nixos-generate-config nixos-install sed awk

  select_repo
  prepare_repo
  prompt_target
  prompt_disk
  patch_disk_config_if_needed
  write_secret_key
  run_install
  copy_repo_to_target

  info "Install finished for host $HOST"
}

main "$@"
