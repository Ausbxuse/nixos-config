#!/usr/bin/env bash
# provision: remote-drive a fresh NixOS host into the secrets trust mesh.
#
# Runs on a trusted peer (e.g. razy). Given a target hostname (as it appears
# in flake nixosConfigurations) and an SSH destination, it:
#
#   1. reads the target's /etc/ssh/ssh_host_ed25519_key.pub
#   2. derives its age identity via ssh-to-age
#   3. admits it locally via admit-host (re-encrypts secrets.yaml)
#   4. generates a pinned syncthing identity for the target, encrypts cert/key
#      into nix-secrets/secrets.yaml, records the device id in defs.nix
#   5. rsyncs the private nix-secrets checkout to the target at /tmp/nix-secrets
#   6. runs nixos-rebuild switch on the target with --override-input nix-secrets
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
#                       otherwise.

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
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
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

[[ -d "$NIX_SECRETS_PATH" ]] || die "nix-secrets not found: $NIX_SECRETS_PATH"

# ------------------------------------------------------------------------- parse ssh dest

ssh_user_host="${SSH_DEST%:*}"
if [[ "$ssh_user_host" == "$SSH_DEST" ]]; then
  ssh_port=22
else
  ssh_port="${SSH_DEST##*:}"
fi

SSH_OPTS=(-p "$ssh_port"
          -o StrictHostKeyChecking=no
          -o UserKnownHostsFile=/dev/null
          -o BatchMode=no)

info "target:      $HOSTNAME at $ssh_user_host:$ssh_port"
info "local cfg:   $NIXOS_CONFIG_PATH"
info "secrets src: $NIX_SECRETS_PATH"
info "remote cfg:  $REMOTE_FLAKE"

# ------------------------------------------------------------------------- 1. reachability

info "step 1/6: checking ssh reachability"
if ! remote_hostname=$(ssh "${SSH_OPTS[@]}" "$ssh_user_host" 'hostname' 2>&1); then
  die "ssh to $ssh_user_host:$ssh_port failed: $remote_hostname"
fi
ok "ssh reachable (remote reports hostname: $remote_hostname)"

# ------------------------------------------------------------------------- 2. derive target age identity

info "step 2/6: reading target host pubkey and deriving age identity"
target_host_pub=$(ssh "${SSH_OPTS[@]}" "$ssh_user_host" 'cat /etc/ssh/ssh_host_ed25519_key.pub' 2>/dev/null) \
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

# ------------------------------------------------------------------------- 4. syncthing identity (Phase F)
#
# Generate the target's syncthing cert/key locally on this peer, write them
# into nix-secrets/secrets.yaml under keys that modules/home/syncthing.nix
# reads, and record the derived device id in machines/defs.nix. After this
# step the new host's first rebuild will come up with its syncthing identity
# already pinned — no post-boot bootstrap dance.

info "step 4/6: generating syncthing identity for $HOSTNAME"

st_tmp=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$st_tmp'" EXIT

syncthing generate --home="$st_tmp" >"$st_tmp/gen.log" 2>&1 \
  || { cat "$st_tmp/gen.log" >&2; die "syncthing generate failed"; }

# syncthing v2 no longer exposes --device-id; the ID appears in the generate
# log as e.g. "device=ABCDEFG-HIJKLMN-..." — grab it from there.
devid=$(grep -oE 'device=[A-Z0-9-]+' "$st_tmp/gen.log" | head -1 | sed 's/device=//')
[[ -n "$devid" ]] || { cat "$st_tmp/gen.log" >&2; die "could not parse syncthing device id from generate output"; }
[[ -f "$st_tmp/cert.pem" && -f "$st_tmp/key.pem" ]] \
  || die "syncthing generate did not produce cert.pem/key.pem in $st_tmp"

ok "device id: $devid"

# sops set --value-file expects the file to contain a JSON-encoded value
# (i.e. the PEM wrapped in a JSON string literal), not raw PEM.
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

# ------------------------------------------------------------------------- 5. rsync nix-secrets

info "step 5/6: rsyncing nix-secrets to target:/tmp/nix-secrets"
rsync -a --delete --exclude=.git \
  -e "ssh ${SSH_OPTS[*]}" \
  "$NIX_SECRETS_PATH"/ "$ssh_user_host:/tmp/nix-secrets/" \
  || die "rsync failed"
ok "nix-secrets synced"

# ------------------------------------------------------------------------- 5. remote rebuild

info "step 6/6: running nixos-rebuild switch on target"
# shellcheck disable=SC2087
ssh "${SSH_OPTS[@]}" "$ssh_user_host" bash <<EOF
set -euo pipefail
if [[ ! -d "$REMOTE_FLAKE" ]]; then
  echo "remote flake path not found: $REMOTE_FLAKE" >&2
  exit 1
fi
cd "$REMOTE_FLAKE"
sudo nixos-rebuild switch \
  --flake ".#$HOSTNAME" \
  --override-input nix-secrets path:/tmp/nix-secrets \
  --show-trace
echo
echo "--- /run/secrets/ ---"
sudo ls -la /run/secrets/ || true
EOF
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
