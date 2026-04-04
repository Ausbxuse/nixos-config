#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly LOCAL_REPO="${LOCAL_REPO:-$PWD}"
readonly REMOTE_REPO="${REMOTE_REPO:-/home/zhenyu/src/public/nixos-config}"
readonly SSH_PORT="${SSH_PORT:-2223}"
readonly INSTALLED_SSH_PORT="${INSTALLED_SSH_PORT:-2224}"
readonly VM_RAM_MB="${VM_RAM_MB:-4096}"
readonly VM_CPUS="${VM_CPUS:-4}"
readonly BOOT_DISK_SIZE="${BOOT_DISK_SIZE:-40G}"
readonly TARGET_DISK_SIZE="${TARGET_DISK_SIZE:-40G}"
readonly KEEP_VM="${KEEP_VM:-0}"
readonly GUI_INSPECT="${GUI_INSPECT:-0}"
readonly SKIP_INSTALL="${SKIP_INSTALL:-0}"
readonly REUSE_WORKDIR="${REUSE_WORKDIR:-}"
readonly DISPLAY_MODE="${DISPLAY_MODE:-headless}"
readonly VNC_DISPLAY="${VNC_DISPLAY:-1}"
readonly HOSTNAME="${HOSTNAME_OVERRIDE:-adhoc-nixos}"
readonly USERNAME="${USERNAME_OVERRIDE:-zhenyu}"
readonly NIXOS_PROFILE="${NIXOS_PROFILE:-$([[ "$GUI_INSPECT" == "1" ]] && printf 'minimal-gui' || printf 'minimal')}"
readonly INSTALL_LAYOUT="${INSTALL_LAYOUT:-$([[ "$GUI_INSPECT" == "1" ]] && printf 'plain-btrfs' || printf 'luks-btrfs')}"
readonly VM_IMAGE='@vmImage@'
readonly OVMF_CODE='@ovmfCode@'
readonly OVMF_VARS_TEMPLATE='@ovmfVarsTemplate@'
readonly SSH_PASSWORD='nixos'

if [[ -n "$REUSE_WORKDIR" ]]; then
  WORKDIR="$REUSE_WORKDIR"
else
  WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/nixos-system-install.XXXXXX")"
fi
BOOT_OVERLAY="${WORKDIR}/boot-overlay.qcow2"
TARGET_DISK="${WORKDIR}/target-disk.qcow2"
OVMF_VARS="${WORKDIR}/OVMF_VARS.fd"
PID_FILE="${WORKDIR}/qemu.pid"
QEMU_LOG="${WORKDIR}/qemu.log"
SERIAL_LOG="${WORKDIR}/serial.log"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ "$KEEP_VM" == "1" && -f "$PID_FILE" ]]; then
    if [[ "$GUI_INSPECT" == "1" ]]; then
      info "Keeping installed NixOS VM running for inspection."
      info "SSH with: sshpass -p \"$SSH_PASSWORD\" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p \"$INSTALLED_SSH_PORT\" ${USERNAME}@127.0.0.1"
      case "$DISPLAY_MODE" in
        vnc)
          info "VNC available at 127.0.0.1:$((5900 + VNC_DISPLAY))"
          ;;
        gtk)
          info "QEMU GTK window should still be open."
          ;;
      esac
    else
      info "Keeping NixOS installer VM running for inspection."
      info "SSH with: sshpass -p \"$SSH_PASSWORD\" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p \"$SSH_PORT\" zhenyu@127.0.0.1"
    fi
    info "Workdir: $WORKDIR"
    info "QEMU log: $QEMU_LOG"
    if [[ -f "$SERIAL_LOG" ]]; then
      info "Serial log: $SERIAL_LOG"
    fi
    return 0
  fi
  if [[ -f "$PID_FILE" ]]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
  fi
  if [[ -z "$REUSE_WORKDIR" ]]; then
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: $cmd"
  done
}

ssh_cmd() {
  sshpass -p "$SSH_PASSWORD" \
    ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 \
    -p "$SSH_PORT" \
    zhenyu@127.0.0.1 \
    "$@"
}

installed_ssh_cmd() {
  sshpass -p "$SSH_PASSWORD" \
    ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 \
    -p "$INSTALLED_SSH_PORT" \
    "${USERNAME}@127.0.0.1" \
    "$@"
}

display_args() {
  case "$DISPLAY_MODE" in
    headless)
      printf '%s\n' "-display" "none"
      ;;
    vnc)
      printf '%s\n' "-display" "vnc=127.0.0.1:${VNC_DISPLAY}"
      ;;
    gtk)
      printf '%s\n' "-display" "gtk"
      ;;
    *)
      die "Unsupported DISPLAY_MODE: $DISPLAY_MODE"
      ;;
  esac
}

wait_for_shutdown() {
  if [[ ! -f "$PID_FILE" ]]; then
    return 0
  fi

  for _ in $(seq 1 60); do
    if ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      rm -f "$PID_FILE"
      return 0
    fi
    sleep 2
  done

  kill "$(cat "$PID_FILE")" 2>/dev/null || true
  rm -f "$PID_FILE"
}

sync_local_repo() {
  [[ -f "${LOCAL_REPO}/flake.nix" ]] || die "LOCAL_REPO does not look like a flake checkout: ${LOCAL_REPO}"
  info "Syncing local repo into NixOS guest..."
  ssh_cmd "sudo mkdir -p \"$(dirname "$REMOTE_REPO")\" && sudo chown -R zhenyu:users /home/zhenyu/src"
  sshpass -p "$SSH_PASSWORD" rsync -az --delete \
    --exclude .git \
    --exclude result \
    -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p \"$SSH_PORT\"" \
    "${LOCAL_REPO}/" "zhenyu@127.0.0.1:${REMOTE_REPO}/"
}

prepare_gui_override() {
  [[ "$GUI_INSPECT" == "1" ]] || return 0

  info "Preparing temporary GUI inspection module..."
  ssh_cmd "mkdir -p \"${REMOTE_REPO}/machines/${HOSTNAME}\""
  ssh_cmd "cat > \"${REMOTE_REPO}/machines/${HOSTNAME}/nixos.nix\" <<'EOF'
{lib, username, ...}: {
  boot.kernelParams = [\"console=ttyS0,115200n8\"];
  users.users.\${username} = {
    initialHashedPassword = lib.mkForce null;
    initialPassword = lib.mkForce \"${SSH_PASSWORD}\";
  };
  services.openssh.settings.PasswordAuthentication = true;
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = username;
}
EOF"
}

boot_vm() {
  qemu-img create -f qcow2 -F qcow2 -b "$VM_IMAGE" "$BOOT_OVERLAY" >/dev/null
  qemu-img resize "$BOOT_OVERLAY" "$BOOT_DISK_SIZE" >/dev/null
  qemu-img create -f qcow2 "$TARGET_DISK" "$TARGET_DISK_SIZE" >/dev/null

  qemu-system-x86_64 \
    -machine accel=kvm:tcg \
    -cpu host \
    -smp "$VM_CPUS" \
    -m "$VM_RAM_MB" \
    -display none \
    -serial mon:stdio \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" \
    -device virtio-net-pci,netdev=net0 \
    -drive "if=virtio,format=qcow2,file=${BOOT_OVERLAY}" \
    -drive "if=virtio,format=qcow2,file=${TARGET_DISK}" \
    -pidfile "$PID_FILE" \
    >"$QEMU_LOG" 2>&1 &
}

wait_for_ssh() {
  info "Waiting for SSH..."
  for _ in $(seq 1 120); do
    if ssh_cmd "true" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  die "NixOS VM did not become reachable over SSH."
}

run_nixos_install() {
  info "Running ad hoc NixOS install inside guest..."
  if [[ "$INSTALL_LAYOUT" == luks-* ]]; then
    ssh_cmd "source /etc/set-environment && cd \"${REMOTE_REPO}\" && printf 'secret-pass\n' | nix --extra-experimental-features 'nix-command flakes' run ./#install -- --host ${HOSTNAME} --username ${USERNAME} --nixos --no-home --disk /dev/vdb --nixos-profile ${NIXOS_PROFILE} --install-layout ${INSTALL_LAYOUT} --swap-size 8G --copy-repo no --yes"
  else
    ssh_cmd "source /etc/set-environment && cd \"${REMOTE_REPO}\" && nix --extra-experimental-features 'nix-command flakes' run ./#install -- --host ${HOSTNAME} --username ${USERNAME} --nixos --no-home --disk /dev/vdb --nixos-profile ${NIXOS_PROFILE} --install-layout ${INSTALL_LAYOUT} --swap-size 8G --copy-repo no --yes"
  fi
}

verify_guest_state() {
  info "Verifying installed target state..."
  ssh_cmd "test -f /mnt/etc/nixos/hardware-configuration.nix"
  ssh_cmd "test -e /mnt/nix/store"
  ssh_cmd "sudo cryptsetup status luks >/tmp/cryptsetup-status || true"
}

boot_installed_system() {
  local -a qemu_display

  [[ "$GUI_INSPECT" == "1" ]] || return 0

  info "Shutting down installer VM..."
  ssh_cmd "sudo systemctl poweroff" || true
  wait_for_shutdown

  info "Booting installed target disk..."
  rm -f "$OVMF_VARS"
  cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"
  chmod u+w "$OVMF_VARS"
  mapfile -t qemu_display < <(display_args)

  qemu-system-x86_64 \
    -machine accel=kvm:tcg \
    -cpu host \
    -smp "$VM_CPUS" \
    -m "$VM_RAM_MB" \
    "${qemu_display[@]}" \
    -boot menu=on \
    -vga std \
    -serial "file:${SERIAL_LOG}" \
    -netdev "user,id=net0,hostfwd=tcp::${INSTALLED_SSH_PORT}-:22" \
    -device virtio-net-pci,netdev=net0 \
    -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,file=${OVMF_VARS}" \
    -drive "if=virtio,format=qcow2,file=${TARGET_DISK}" \
    -pidfile "$PID_FILE" \
    >"$QEMU_LOG" 2>&1 &
}

wait_for_installed_ssh() {
  [[ "$GUI_INSPECT" == "1" ]] || return 0

  info "Waiting for installed system SSH..."
  for _ in $(seq 1 120); do
    if installed_ssh_cmd "true" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  if [[ "$KEEP_VM" == "1" ]]; then
    warn "Installed system did not become reachable over SSH, but the VM is being kept alive for manual GUI inspection."
    return 0
  fi

  die "Installed system did not become reachable over SSH."
}

verify_installed_gui() {
  [[ "$GUI_INSPECT" == "1" ]] || return 0

  if ! installed_ssh_cmd "true" >/dev/null 2>&1; then
    warn "Skipping installed-system service verification because SSH is unavailable."
    return 0
  fi

  info "Verifying installed graphical target..."
  installed_ssh_cmd "systemctl is-active graphical.target >/dev/null"
  installed_ssh_cmd "systemctl is-active display-manager.service >/dev/null"
}

main() {
  require_cmd qemu-img qemu-system-x86_64 ssh sshpass rsync
  [[ -f "$VM_IMAGE" ]] || die "Installer VM image not found: $VM_IMAGE"
  [[ -f "$OVMF_CODE" ]] || die "OVMF firmware not found: $OVMF_CODE"
  [[ -f "$OVMF_VARS_TEMPLATE" ]] || die "OVMF vars template not found: $OVMF_VARS_TEMPLATE"
  if [[ "$SKIP_INSTALL" == "1" ]]; then
    [[ -f "$TARGET_DISK" ]] || die "Reused target disk not found: $TARGET_DISK"
    boot_installed_system
    wait_for_installed_ssh
    verify_installed_gui
    info "Reused installed system boot test passed."
    return 0
  fi
  boot_vm
  wait_for_ssh
  sync_local_repo
  prepare_gui_override
  run_nixos_install
  verify_guest_state
  boot_installed_system
  wait_for_installed_ssh
  verify_installed_gui
  info "NixOS system install integration test passed."
}

main "$@"
