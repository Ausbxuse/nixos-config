#!/usr/bin/env bash
# provision: remote-drive a fresh NixOS host into the secrets trust mesh.
#
# Runs on a trusted peer (e.g. razy). Given a target hostname (as it appears
# in flake nixosConfigurations) and an SSH destination, it:
#
#   1. opens one persistent SSH master connection
#   2. validates remote sudo once and keeps it warm for the duration
#   3. reads the target's /etc/ssh/ssh_host_ed25519_key.pub
#   4. derives its age identity via ssh-to-age
#   5. admits it locally via admit-host (re-encrypts secrets.yaml)
#   6. generates a pinned syncthing identity for the target, encrypts cert/key
#      into nix-secrets/secrets.yaml, records the device id in defs.nix
#   7. rsyncs the private nix-secrets checkout to the target at /tmp/nix-secrets
#   8. runs nixos-rebuild switch on the target with --override-input nix-secrets
#
# Usage:
#   provision <hostname> <user@host[:port]> [--remote-flake <path>]
#
# Examples:
#   provision adhoc-nixos zhenyu@127.0.0.1:2224
#   provision dev-box zhenyu@dev.example.com
#   provision dev-box zhenyu@dev.example.com --remote-flake /etc/nixos
#
# Environment:
#   NIXOS_CONFIG_PATH   path to the nixos-config repo (default: $PWD)
#   NIX_SECRETS_PATH    path to the nix-secrets checkout to ship
#                       (default: $HOME/src/private/nix-secrets)
#   SOPS_AGE_KEY_FILE   recommended: user age identity so admit-host doesn't
#                       need sudo. Falls through to admit-host's own detection
#
# Notes:
#   - This script prompts for the SSH password once (to establish the master
#     connection) and for sudo once on the remote host (sudo -v).
#   - If the remote sudoers policy has timestamp_timeout=0, sudo will still
#     require a password each time by policy; this script assumes normal sudo
#     timestamp caching is enabled.

set -euo pipefail
IFS=$'\n\t'

# ------------------------------------------------------------------------- ui

die()  { printf 'provision: %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32mOK\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }

# ------------------------------------------------------------------------- args

HOSTNAME=""
SSH_DEST=""
REMOTE_FLAKE="/home/zhenyu/src/public/nixos-config"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote-flake) REMOTE_FLAKE="${2:?missing value}"; shift 2 ;;
    --help|-h)
      sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --*) die "unknown flag: $1" ;;
    *)
      if   [[ -z "$HOSTNAME" ]]; then HOSTNAME="$1"
      elif [[ -z "$SSH_DEST" ]]; then SSH_DEST="$1"
      else die "too many positional arguments"
      fi
      shift
      ;;
  esac
done

[[ -n "$HOSTNAME" ]] || die "hostname required (positional #1)"
[[ -n "$SSH_DEST" ]] || die "ssh destination required (positional #2, e.g. user@host:port)"

NIXOS_CONFIG_PATH="${NIXOS_CONFIG_PATH:-$PWD}"
NIX_SECRETS_PATH="${NIX_SECRETS_PATH:-$HOME/src/private/nix-secrets}"

[[ -d "$NIXOS_CONFIG_PATH" ]] || die "nixos-config not found: $NIXOS_CONFIG_PATH"
[[ -d "$NIX_SECRETS_PATH" ]] || die "nix-secrets not found: $NIX_SECRETS_PATH"

# ------------------------------------------------------------------------- parse ssh dest

ssh_user_host="${SSH_DEST%:*}"
if [[ "$ssh_user_host" == "$SSH_DEST" ]]; then
  ssh_port=22
else
  ssh_port="${SSH_DEST##*:}"
fi

# Persistent SSH control socket: authenticate once, reuse everywhere.
control_dir=$(mktemp -d)
control_path="$control_dir/ssh-%r@%h:%p"
SSH_OPTS=(
  -p "$ssh_port"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o BatchMode=no
  -o ControlMaster=auto
  -o ControlPersist=30m
  -o ControlPath="$control_path"
)

st_tmp=""
sudo_keepalive_pid=""

cleanup() {
  set +e
  if [[ -n "${sudo_keepalive_pid:-}" ]]; then
    kill "$sudo_keepalive_pid" >/dev/null 2>&1 || true
    wait "$sudo_keepalive_pid" >/dev/null 2>&1 || true
  fi
  ssh -O exit "${SSH_OPTS[@]}" "$ssh_user_host" >/dev/null 2>&1 || true
  [[ -n "${st_tmp:-}" && -d "$st_tmp" ]] && rm -rf "$st_tmp"
  [[ -d "$control_dir" ]] && rm -rf "$control_dir"
}
trap cleanup EXIT

ssh_cmd() {
  local remote_cmd="${1:?missing remote command}"
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "$ssh_user_host" "$remote_cmd"
}

# Join SSH args safely for rsync -e.
build_rsync_ssh_cmd() {
  local out=() arg
  out+=(ssh)
  for arg in "${SSH_OPTS[@]}"; do
    out+=("$(printf '%q' "$arg")")
  done
  printf '%s ' "${out[@]}"
}

info "target:      $HOSTNAME at $ssh_user_host:$ssh_port"
info "local cfg:   $NIXOS_CONFIG_PATH"
info "secrets src: $NIX_SECRETS_PATH"
info "remote cfg:  $REMOTE_FLAKE"

# ------------------------------------------------------------------------- 1. establish master connection + cache sudo

info "step 1/6: establishing persistent ssh session"
# This is the single SSH-auth point for the whole script.
if ! ssh -MNf "${SSH_OPTS[@]}" "$ssh_user_host" 2>/tmp/provision-ssh.err; then
  err=$(cat /tmp/provision-ssh.err 2>/dev/null || true)
  rm -f /tmp/provision-ssh.err
  die "failed to establish persistent ssh session: $err"
fi
rm -f /tmp/provision-ssh.err

if ! remote_hostname=$(ssh_cmd 'hostname' 2>&1); then
  die "ssh to $ssh_user_host:$ssh_port failed after master connection: $remote_hostname"
fi
ok "ssh reachable (remote reports hostname: $remote_hostname)"

# ------------------------------------------------------------------------- 2. derive target age identity

info "step 2/6: reading target host pubkey and deriving age identity"
target_host_pub=$(ssh_cmd 'cat /etc/ssh/ssh_host_ed25519_key.pub' 2>/dev/null) \
  || die "could not read /etc/ssh/ssh_host_ed25519_key.pub on target"
[[ -n "$target_host_pub" ]] || die "empty host pubkey from target"

target_age_pub=$(printf '%s\n' "$target_host_pub" | ssh-to-age) \
  || die "ssh-to-age failed to convert target host pubkey"
[[ "$target_age_pub" == age1* ]] \
  || die "derived age key doesn't look right: $target_age_pub"

ok "target age pubkey: $target_age_pub"

# ------------------------------------------------------------------------- 3. admit

info "step 3/6: admitting $HOSTNAME to trust mesh"
(
  cd "$NIXOS_CONFIG_PATH"
  admit-host --set-host-key "$HOSTNAME" "$target_age_pub"
) || die "admit-host failed"
ok "admission complete"

# ------------------------------------------------------------------------- 4. syncthing identity

info "step 4/6: generating syncthing identity for $HOSTNAME"

st_tmp=$(mktemp -d)

syncthing generate --home="$st_tmp" >"$st_tmp/gen.log" 2>&1 \
  || { cat "$st_tmp/gen.log" >&2; die "syncthing generate failed"; }

devid=$(grep -oE 'device=[A-Z0-9-]+' "$st_tmp/gen.log" | head -1 | sed 's/device=//')
[[ -n "$devid" ]] || { cat "$st_tmp/gen.log" >&2; die "could not parse syncthing device id from generate output"; }
[[ -f "$st_tmp/cert.pem" && -f "$st_tmp/key.pem" ]] \
  || die "syncthing generate did not produce cert.pem/key.pem in $st_tmp"

ok "device id: $devid"

jq -Rs . < "$st_tmp/cert.pem" > "$st_tmp/cert.json"
jq -Rs . < "$st_tmp/key.pem"  > "$st_tmp/key.json"

info "writing cert/key into $NIX_SECRETS_PATH/secrets.yaml"
(
  cd "$NIX_SECRETS_PATH"
  sops set --value-file secrets.yaml "[\"syncthing-cert-${HOSTNAME}\"]" "$st_tmp/cert.json"
  sops set --value-file secrets.yaml "[\"syncthing-key-${HOSTNAME}\"]"  "$st_tmp/key.json"
) || die "sops set failed"
ok "cert/key encrypted into secrets.yaml"

info "recording device id in defs.nix and re-running admit"
(
  cd "$NIXOS_CONFIG_PATH"
  admit-host --set-host-syncthing "$HOSTNAME" "$devid"
) || die "admit-host --set-host-syncthing failed"
ok "syncthing identity pinned for $HOSTNAME"

# ------------------------------------------------------------------------- 5. rsync nix-secrets + nixos-config

info "step 5/6: rsyncing nix-secrets + refreshing nixos-config on target"
rsync_ssh_cmd=$(build_rsync_ssh_cmd)

rsync -a --delete --exclude=.git \
  -e "$rsync_ssh_cmd" \
  "$NIX_SECRETS_PATH"/ "$ssh_user_host:/tmp/nix-secrets/" \
  || die "nix-secrets rsync failed"
ok "nix-secrets synced"

rsync -a --delete \
  --exclude='.git' \
  --exclude='machines/defs.nix' \
  --exclude="machines/${HOSTNAME}/" \
  -e "$rsync_ssh_cmd" \
  "$NIXOS_CONFIG_PATH"/ "$ssh_user_host:${REMOTE_FLAKE}/" \
  || die "nixos-config rsync failed"
ok "nixos-config refreshed on target (defs.nix + machines/${HOSTNAME}/ preserved)"

# ------------------------------------------------------------------------- 6. remote rebuild

info "step 6/6: running nixos-rebuild switch on target"

ssh_cmd "cat > /tmp/provision-rebuild.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d "$REMOTE_FLAKE" ]]; then
  echo "remote flake path not found: $REMOTE_FLAKE" >&2
  exit 1
fi

cd "$REMOTE_FLAKE"

# Authenticate sudo ON THIS EXACT TTY/session.
sudo -v

# Keep sudo alive for long rebuilds.
(
  while true; do
    sleep 50
    sudo -n true >/dev/null 2>&1 || exit 0
  done
) &
keepalive_pid=\$!

cleanup() {
  kill "\$keepalive_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

sudo -n nixos-rebuild switch \
  --flake ".#$HOSTNAME" \
  --override-input nix-secrets path:/tmp/nix-secrets \
  --show-trace

echo
echo "--- /run/secrets/ ---"
sudo -n ls -la /run/secrets/ || true
EOF

# shellcheck disable=SC2029
ssh -tt "${SSH_OPTS[@]}" "$ssh_user_host" 'bash /tmp/provision-rebuild.sh'
ok "remote rebuild succeeded"

# ------------------------------------------------------------------------- summary

printf '\n'
info "provision complete: $HOSTNAME is in the trust mesh"
info "locally-modified (uncommitted) files to review + commit:"
printf '  %s\n' "$NIXOS_CONFIG_PATH/machines/defs.nix"
printf '  %s\n' "$NIX_SECRETS_PATH/.sops.yaml"
printf '  %s\n' "$NIX_SECRETS_PATH/secrets.yaml"
printf '\n'
warn "/tmp/nix-secrets on the target holds the private repo. If the target is"
warn "ephemeral (VM), shut it down. If persistent, wire up a real flake input"
warn "(git remote) on the target so it no longer depends on /tmp/nix-secrets."
