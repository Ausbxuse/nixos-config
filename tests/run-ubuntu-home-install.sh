#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly REPO_FLAKE="${REPO_FLAKE:-github:ausbxuse/nixos-config}"
readonly UBUNTU_RELEASE="${UBUNTU_RELEASE:-24.04}"
readonly UBUNTU_SERIES="${UBUNTU_SERIES:-noble}"
readonly SSH_PORT="${SSH_PORT:-2222}"
readonly VM_RAM_MB="${VM_RAM_MB:-4096}"
readonly VM_CPUS="${VM_CPUS:-4}"
readonly VM_DISK_SIZE="${VM_DISK_SIZE:-40G}"
readonly KEEP_VM="${KEEP_VM:-0}"
readonly HOSTNAME="${HOSTNAME_OVERRIDE:-ubuntu-adhoc}"
readonly HOME_PROFILE="${HOME_PROFILE:-personal-gnome}"
readonly DISPLAY_PROFILE="${DISPLAY_PROFILE:-gnome-default}"
readonly CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/nixos-config-tests"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ubuntu-home-install.XXXXXX")"
IMG_CACHE="${CACHE_DIR}/${UBUNTU_SERIES}-server-cloudimg-amd64.img"
OVERLAY_IMG="${WORKDIR}/ubuntu-overlay.qcow2"
SEED_IMG="${WORKDIR}/seed.img"
PID_FILE="${WORKDIR}/qemu.pid"
SSH_KEY="${WORKDIR}/id_ed25519"

info() { printf '[INFO] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ "$KEEP_VM" == "1" && -f "$PID_FILE" ]]; then
    info "Keeping Ubuntu VM running for inspection."
    info "SSH with: ssh -i \"$SSH_KEY\" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p \"$SSH_PORT\" zhenyu@127.0.0.1"
    info "Workdir: $WORKDIR"
    return 0
  fi
  if [[ -f "$PID_FILE" ]]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
  fi
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: $cmd"
  done
}

ssh_cmd() {
  ssh \
    -i "$SSH_KEY" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 \
    -p "$SSH_PORT" \
    zhenyu@127.0.0.1 \
    "$@"
}

download_image() {
  mkdir -p "$CACHE_DIR"
  if [[ ! -f "$IMG_CACHE" ]]; then
    info "Downloading Ubuntu cloud image..."
    curl -L "https://cloud-images.ubuntu.com/${UBUNTU_SERIES}/current/${UBUNTU_SERIES}-server-cloudimg-amd64.img" -o "$IMG_CACHE"
  fi
}

make_seed() {
  ssh-keygen -q -t ed25519 -N "" -f "$SSH_KEY" >/dev/null

  cat >"${WORKDIR}/user-data" <<EOF
#cloud-config
growpart:
  mode: auto
  devices: ["/"]
  ignore_growroot_disabled: false
resize_rootfs: true
users:
  - default
  - name: zhenyu
    gecos: Zhenyu
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    ssh_authorized_keys:
      - $(cat "${SSH_KEY}.pub")
package_update: false
package_upgrade: false
runcmd:
  - mkdir -p /home/zhenyu/src/public
EOF

  cat >"${WORKDIR}/meta-data" <<EOF
instance-id: nixos-config-ubuntu-home-test
local-hostname: ${HOSTNAME}
EOF

  cloud-localds "$SEED_IMG" "${WORKDIR}/user-data" "${WORKDIR}/meta-data"
}

boot_vm() {
  qemu-img create -f qcow2 -F qcow2 -b "$IMG_CACHE" "$OVERLAY_IMG" >/dev/null
  qemu-img resize "$OVERLAY_IMG" "$VM_DISK_SIZE" >/dev/null

  qemu-system-x86_64 \
    -machine accel=kvm:tcg \
    -cpu host \
    -smp "$VM_CPUS" \
    -m "$VM_RAM_MB" \
    -display none \
    -serial mon:stdio \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" \
    -device virtio-net-pci,netdev=net0 \
    -drive "if=virtio,format=qcow2,file=${OVERLAY_IMG}" \
    -drive "if=virtio,format=raw,file=${SEED_IMG}" \
    -pidfile "$PID_FILE" \
    >/tmp/ubuntu-home-install-qemu.log 2>&1 &
}

wait_for_ssh() {
  info "Waiting for SSH..."
  for _ in $(seq 1 120); do
    if ssh_cmd "true" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  die "Ubuntu VM did not become reachable over SSH."
}

install_nix() {
  info "Installing Nix inside Ubuntu guest..."
  ssh_cmd "command -v nix >/dev/null 2>&1 || sh <(curl -L https://nixos.org/nix/install) --daemon --yes"
}

run_home_install() {
  info "Running ad hoc home-only install inside Ubuntu guest..."
  ssh_cmd "source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && nix --extra-experimental-features 'nix-command flakes' run ${REPO_FLAKE}#install -- --host ${HOSTNAME} --home --no-nixos --home-profile ${HOME_PROFILE} --display-profile ${DISPLAY_PROFILE} --yes"
}

verify_guest_state() {
  info "Verifying guest state..."
  ssh_cmd "source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && home-manager generations >/tmp/hm-generations && grep -q current /tmp/hm-generations"
  ssh_cmd "test -d ~/.config || test -L ~/.config"
}

main() {
  require_cmd curl qemu-img qemu-system-x86_64 cloud-localds ssh ssh-keygen
  download_image
  make_seed
  boot_vm
  wait_for_ssh
  install_nix
  run_home_install
  verify_guest_state
  info "Ubuntu home install integration test passed."
}

main "$@"
