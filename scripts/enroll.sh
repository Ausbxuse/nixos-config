#!/usr/bin/env bash
# enroll: remote-drive a fresh NixOS host into the secrets trust mesh.
#
# Runs on a trusted peer (e.g. razy). Given a target hostname (as it appears
# in flake nixosConfigurations) and an SSH destination, it:
#
#   1. opens one persistent SSH master connection
#   2. reads the target's /etc/ssh/ssh_host_ed25519_key.pub
#   3. derives its age identity via ssh-to-age
#   4. admits it locally via admit-host (promotes the host into hosts.nix,
#      removes any staging entry, re-encrypts secrets.yaml)
#   5. ensures the target user has an SSH key, records it in hosts.nix, and
#      appends it to root@zhenyuzhao.com's authorized_keys
#   6. generates a pinned syncthing identity for the target, encrypts cert/key
#      into nix-secrets/secrets.yaml, records the device id in hosts.nix
#   7. rsyncs the private nix-secrets checkout to ~/src/private/nix-secrets on target
#   8. initializes git repos on the target for both nix-config and nix-secrets
#   9. runs nixos-rebuild switch on the target with --override-input nix-secrets

set -euo pipefail
IFS=$'\n\t'

HOSTNAME=""
SSH_DEST=""
REMOTE_FLAKE=""
REMOTE_SECRETS=""
NIXOS_CONFIG_PATH=""
NIX_SECRETS_PATH=""
DRY_RUN=0
DEFAULT_SOPS_AGE_KEY_FILE="${HOME}/.config/sops/age/keys.txt"
REMOTE_ROOT_KEY_DEST="root@zhenyuzhao.com"

@source_lib@

script_banner() { banner "enroll" "enroll a fresh NixOS host into the trust mesh"; }

# --------------------------------------------------------------------- args

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --remote-flake)    REMOTE_FLAKE="${2:?missing value}";      shift 2 ;;
      --config-path)     NIXOS_CONFIG_PATH="${2:?missing value}"; shift 2 ;;
      --secrets-path)    NIX_SECRETS_PATH="${2:?missing value}";  shift 2 ;;
      --dry-run)         DRY_RUN=1;                               shift ;;
      --no-color)        USE_COLOR=0; apply_colors;               shift ;;
      -y|--yes)          ASSUME_YES=1;                            shift ;;
      -h|--help)
        cat <<EOF
Usage:
  nix run .#enroll -- [options] [hostname] [user@host[:port]]

Arguments:
  hostname               Target hostname (as in flake nixosConfigurations)
  user@host[:port]       SSH destination for the target machine

Options:
  --remote-flake PATH    Flake path on the target (default: /home/<user>/src/public/nix-config)
  --config-path PATH     Local nix-config repo (default: \$PWD or \$NIXOS_CONFIG_PATH)
  --secrets-path PATH    Local nix-secrets checkout (default: \$HOME/src/private/nix-secrets
                         or \$NIX_SECRETS_PATH)
  --dry-run              Show the resolved plan and exit without making changes
  --no-color             Disable ANSI colors even on a TTY
  -y, --yes              Accept all confirmation prompts

Environment:
  NIXOS_CONFIG_PATH      Override local nix-config path
  NIX_SECRETS_PATH       Override local nix-secrets path
  SOPS_AGE_KEY_FILE      User age identity (avoids sudo in admit-host)

Examples:
  nix run .#enroll -- custom-nixos zhenyu@127.0.0.1:2224
  nix run .#enroll -- dev-box zhenyu@dev.example.com
  nix run .#enroll -- --dry-run dev-box zhenyu@dev.example.com
EOF
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
}

# --------------------------------------------------------------- resolve plan

resolve_params() {
  if [[ -z "$HOSTNAME" ]]; then
    section "target"
    HOSTNAME=$(prompt_text "hostname" "" validate_hostname)
  fi

  if [[ -z "$SSH_DEST" ]]; then
    SSH_DEST=$(prompt_text "ssh destination (user@host[:port])" "" validate_ssh_dest)
  fi

  NIXOS_CONFIG_PATH="${NIXOS_CONFIG_PATH:-${PWD}}"
  NIX_SECRETS_PATH="${NIX_SECRETS_PATH:-$HOME/src/private/nix-secrets}"

  [[ -d "$NIXOS_CONFIG_PATH" ]] || die "nix-config not found: $NIXOS_CONFIG_PATH"
  [[ -d "$NIX_SECRETS_PATH" ]] || die "nix-secrets not found: $NIX_SECRETS_PATH"
}

# ----------------------------------------------------------------- ssh setup

ssh_user_host=""
ssh_port=""
control_dir=""
control_path=""

declare -a SSH_OPTS=()

setup_ssh_vars() {
  ssh_user_host="${SSH_DEST%:*}"
  if [[ "$ssh_user_host" == "$SSH_DEST" ]]; then
    ssh_port=22
  else
    ssh_port="${SSH_DEST##*:}"
  fi

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
}

resolve_remote_paths() {
  local remote_user="${ssh_user_host%%@*}"
  if [[ "$remote_user" == "$ssh_user_host" ]]; then
    remote_user=$(whoami)
  fi
  REMOTE_FLAKE="${REMOTE_FLAKE:-/home/${remote_user}/src/public/nix-config}"
  REMOTE_SECRETS="/home/${remote_user}/src/private/nix-secrets"
}

resolve_sops_identity() {
  if [[ -n "${SOPS_AGE_KEY_FILE:-}" || -n "${SOPS_AGE_KEY:-}" || -n "${SOPS_AGE_KEY_CMD:-}" ]]; then
    return 0
  fi

  if [[ -r "$DEFAULT_SOPS_AGE_KEY_FILE" ]]; then
    export SOPS_AGE_KEY_FILE="$DEFAULT_SOPS_AGE_KEY_FILE"
    info "using default sops age identity: $SOPS_AGE_KEY_FILE"
    return 0
  fi

  die "no readable decryption identity found.
set SOPS_AGE_KEY_FILE / SOPS_AGE_KEY / SOPS_AGE_KEY_CMD,
or place your default key at: $DEFAULT_SOPS_AGE_KEY_FILE"
}

st_tmp=""
sudo_keepalive_pid=""

cleanup() {
  set +e
  if [[ -n "${sudo_keepalive_pid:-}" ]]; then
    kill "$sudo_keepalive_pid" >/dev/null 2>&1 || true
    wait "$sudo_keepalive_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n "${ssh_user_host:-}" ]]; then
    ssh -O exit "${SSH_OPTS[@]}" "$ssh_user_host" >/dev/null 2>&1 || true
  fi
  [[ -n "${st_tmp:-}" && -d "$st_tmp" ]] && rm -rf "$st_tmp"
  [[ -n "${control_dir:-}" && -d "$control_dir" ]] && rm -rf "$control_dir"
}
trap cleanup EXIT

ssh_cmd() {
  local remote_cmd="${1:?missing remote command}"
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "$ssh_user_host" "$remote_cmd"
}

build_rsync_ssh_cmd() {
  local out=() arg
  out+=(ssh)
  for arg in "${SSH_OPTS[@]}"; do
    out+=("$(printf '%q' "$arg")")
  done
  printf '%s ' "${out[@]}"
}

# --------------------------------------------------------------- recap + exec

recap() {
  section "summary"
  kv "hostname"      "$HOSTNAME"
  kv "ssh dest"      "$ssh_user_host:$ssh_port"
  kv "local config"  "$NIXOS_CONFIG_PATH"
  kv "secrets src"   "$NIX_SECRETS_PATH"
  kv "remote flake"  "$REMOTE_FLAKE"
  kv "remote secrets" "$REMOTE_SECRETS"
  kv "key relay"     "$REMOTE_ROOT_KEY_DEST"

  if [[ $DRY_RUN -eq 1 ]]; then
    kv "mode" "${C_YELLOW}dry run${C_RESET}"
  fi
}

step_ssh_connect() {
  section "1/7 establish persistent ssh session"

  if [[ $DRY_RUN -eq 1 ]]; then
    info "would connect to $ssh_user_host:$ssh_port"
    return 0
  fi

  if ! ssh -MNf "${SSH_OPTS[@]}" "$ssh_user_host" 2>/tmp/enroll-ssh.err; then
    local ssh_err
    ssh_err=$(cat /tmp/enroll-ssh.err 2>/dev/null || true)
    rm -f /tmp/enroll-ssh.err
    die "failed to establish persistent ssh session: $ssh_err"
  fi
  rm -f /tmp/enroll-ssh.err

  local remote_hostname
  if ! remote_hostname=$(ssh_cmd 'hostname' 2>&1); then
    die "ssh to $ssh_user_host:$ssh_port failed: $remote_hostname"
  fi
  ok "ssh reachable (remote hostname: $remote_hostname)"
}

step_derive_age() {
  section "2/7 derive target age identity"

  if [[ $DRY_RUN -eq 1 ]]; then
    info "would read /etc/ssh/ssh_host_ed25519_key.pub and derive age key"
    return 0
  fi

  target_host_pub=$(ssh_cmd 'cat /etc/ssh/ssh_host_ed25519_key.pub' 2>/dev/null) \
    || die "could not read /etc/ssh/ssh_host_ed25519_key.pub on target"
  [[ -n "$target_host_pub" ]] || die "empty host pubkey from target"

  target_age_pub=$(printf '%s\n' "$target_host_pub" | ssh-to-age) \
    || die "ssh-to-age failed to convert target host pubkey"
  [[ "$target_age_pub" == age1* ]] \
    || die "derived age key doesn't look right: $target_age_pub"

  ok "target age pubkey: $target_age_pub"
}

step_admit() {
  section "3/7 admit $HOSTNAME to trust mesh"

  if [[ $DRY_RUN -eq 1 ]]; then
    info "would run: admit-host --set-host-key $HOSTNAME <age-pubkey>"
    info "would promote ${HOSTNAME} from staging defs into hosts.nix if needed"
    return 0
  fi

  (
    cd "$NIXOS_CONFIG_PATH"
    admit-host --set-host-key "$HOSTNAME" "$target_age_pub"
  ) || die "admit-host failed"
  ok "admission complete"
}

quote_sq() {
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

step_user_ssh_key() {
  section "4/7 publish target user ssh key"

  if [[ $DRY_RUN -eq 1 ]]; then
    info "would ensure ~/.ssh/id_ed25519 exists on target"
    info "would record ${HOSTNAME}.userSshPubKey in hosts.nix"
    info "would append the key to ${REMOTE_ROOT_KEY_DEST}:~/.ssh/authorized_keys"
    return 0
  fi

  local target_user_pub=""
  local escaped_pub=""
  target_user_pub=$(
    ssh_cmd "set -euo pipefail; \
      mkdir -p ~/.ssh && chmod 700 ~/.ssh; \
      if [ ! -f ~/.ssh/id_ed25519 ]; then \
        ssh-keygen -q -t ed25519 -N '' -f ~/.ssh/id_ed25519 -C '${HOSTNAME}' >/dev/null; \
      fi; \
      chmod 600 ~/.ssh/id_ed25519; \
      chmod 644 ~/.ssh/id_ed25519.pub; \
      cat ~/.ssh/id_ed25519.pub"
  ) || die "could not read or generate ~/.ssh/id_ed25519.pub on target"

  [[ "$target_user_pub" =~ ^ssh-(ed25519|rsa|ecdsa)\  ]] \
    || die "target user ssh pubkey does not look valid: $target_user_pub"

  (
    cd "$NIXOS_CONFIG_PATH"
    admit-host --set-host-user-ssh-key "$HOSTNAME" "$target_user_pub"
  ) || die "admit-host --set-host-user-ssh-key failed"
  ok "user ssh pubkey recorded in hosts.nix"

  escaped_pub=$(quote_sq "$target_user_pub")
  # shellcheck disable=SC2029
  if ssh "$REMOTE_ROOT_KEY_DEST" \
      "umask 077; mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && grep -qxF '$escaped_pub' ~/.ssh/authorized_keys || printf '%s\n' '$escaped_pub' >> ~/.ssh/authorized_keys"; then
    ok "user ssh pubkey installed on ${REMOTE_ROOT_KEY_DEST}"
  else
    warn "failed to install user ssh pubkey on ${REMOTE_ROOT_KEY_DEST} (non-fatal)"
  fi
}

step_syncthing() {
  section "5/7 generate syncthing identity for $HOSTNAME"

  if [[ $DRY_RUN -eq 1 ]]; then
    info "would generate syncthing cert/key pair"
    info "would encrypt into $NIX_SECRETS_PATH/secrets.yaml"
    info "would record device id in hosts.nix"
    return 0
  fi

  st_tmp=$(mktemp -d)

  syncthing generate --home="$st_tmp" >"$st_tmp/gen.log" 2>&1 \
    || { cat "$st_tmp/gen.log" >&2; die "syncthing generate failed"; }

  local devid
  devid=$(grep -oE 'device=[A-Z0-9-]+' "$st_tmp/gen.log" | head -1 | sed 's/device=//')
  [[ -n "$devid" ]] || { cat "$st_tmp/gen.log" >&2; die "could not parse syncthing device id"; }
  [[ -f "$st_tmp/cert.pem" && -f "$st_tmp/key.pem" ]] \
    || die "syncthing generate did not produce cert.pem/key.pem"

  ok "device id: $devid"

  jq -Rs . < "$st_tmp/cert.pem" > "$st_tmp/cert.json"
  jq -Rs . < "$st_tmp/key.pem"  > "$st_tmp/key.json"

  info "writing cert/key into secrets.yaml"
  (
    cd "$NIX_SECRETS_PATH"
    sops set --value-file secrets.yaml "[\"syncthing-cert-${HOSTNAME}\"]" "$st_tmp/cert.json"
    sops set --value-file secrets.yaml "[\"syncthing-key-${HOSTNAME}\"]"  "$st_tmp/key.json"
  ) || die "sops set failed"
  ok "cert/key encrypted into secrets.yaml"

  info "recording device id in hosts.nix"
  (
    cd "$NIXOS_CONFIG_PATH"
    admit-host --set-host-syncthing "$HOSTNAME" "$devid"
  ) || die "admit-host --set-host-syncthing failed"
  ok "syncthing identity pinned"
}

step_rsync() {
  section "6/7 rsync nix-secrets + nix-config to target"

  if [[ $DRY_RUN -eq 1 ]]; then
    info "would rsync $NIX_SECRETS_PATH -> $ssh_user_host:$REMOTE_SECRETS/"
    info "would rsync $NIXOS_CONFIG_PATH -> $ssh_user_host:$REMOTE_FLAKE/"
    info "  (excluding .git, machines/defs.nix, machines/$HOSTNAME/)"
    info "would initialize git repos on target"
    return 0
  fi

  local rsync_ssh_cmd
  rsync_ssh_cmd=$(build_rsync_ssh_cmd)

  ssh_cmd "mkdir -p '$(dirname "$REMOTE_SECRETS")'"

  run_with_spinner "syncing nix-secrets to target" \
    rsync -a --delete --exclude=.git \
      -e "$rsync_ssh_cmd" \
      "$NIX_SECRETS_PATH"/ "$ssh_user_host:${REMOTE_SECRETS}/"

  run_with_spinner "syncing nix-config to target" \
    rsync -a --delete \
      --exclude='.git' \
      --exclude='machines/defs.nix' \
      --exclude="machines/${HOSTNAME}/" \
      -e "$rsync_ssh_cmd" \
      "$NIXOS_CONFIG_PATH"/ "$ssh_user_host:${REMOTE_FLAKE}/"

  ok "nix-config refreshed (defs.nix + machines/${HOSTNAME}/ preserved)"

  info "initializing git repos on target"
  ssh_cmd "cd '$REMOTE_SECRETS' && git init && git add -A && git commit -m 'enroll: initial nix-secrets snapshot' --author='enroll <enroll@nix-config>' --allow-empty" \
    || warn "git init for nix-secrets on target failed (non-fatal)"
  ssh_cmd "cd '$REMOTE_FLAKE' && git init && git add -A && git commit -m 'enroll: initial nix-config snapshot' --author='enroll <enroll@nix-config>' --allow-empty" \
    || warn "git init for nix-config on target failed (non-fatal)"
  ok "target repos initialized as git repositories"
}

step_rebuild() {
  section "7/7 nixos-rebuild switch on target"

  if [[ $DRY_RUN -eq 1 ]]; then
    info "would run nixos-rebuild switch --flake .#$HOSTNAME on target"
    info "  with --override-input nix-secrets path:$REMOTE_SECRETS"
    return 0
  fi

  ssh_cmd "cat > /tmp/enroll-rebuild.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d "$REMOTE_FLAKE" ]]; then
  echo "remote flake path not found: $REMOTE_FLAKE" >&2
  exit 1
fi

cd "$REMOTE_FLAKE"

sudo -v

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
  --override-input nix-secrets path:$REMOTE_SECRETS \
  --show-trace

echo
echo "--- /run/secrets/ ---"
sudo -n ls -la /run/secrets/ || true
EOF

  # shellcheck disable=SC2029
  ssh -tt "${SSH_OPTS[@]}" "$ssh_user_host" 'bash /tmp/enroll-rebuild.sh'
  ok "remote rebuild succeeded"
}

# --------------------------------------------------------------------- main

main() {
  require_cmd jq rsync ssh ssh-to-age syncthing sops admit-host
  parse_args "$@"
  apply_colors

  script_banner
  resolve_params
  resolve_sops_identity
  setup_ssh_vars
  resolve_remote_paths
  recap

  if ! prompt_bool "proceed?" yes; then
    die "aborted."
  fi

  local target_host_pub=""
  local target_age_pub=""

  step_ssh_connect
  step_derive_age
  step_admit
  step_user_ssh_key
  step_syncthing
  step_rsync
  step_rebuild

  if [[ $DRY_RUN -eq 1 ]]; then
    printf '\n'
    ok "dry run complete — no changes made"
    return 0
  fi

  section "done"
  ok "enroll complete: ${C_BOLD}${HOSTNAME}${C_RESET} is in the trust mesh"
  printf '\n'
  info "locally-modified (uncommitted) files to review + commit:"
  kv "" "$NIX_SECRETS_PATH/hosts.nix"
  kv "" "$NIXOS_CONFIG_PATH/machines/defs.nix"
  kv "" "$NIX_SECRETS_PATH/.sops.yaml"
  kv "" "$NIX_SECRETS_PATH/secrets.yaml"
  printf '\n'
  info "nix-secrets synced to $REMOTE_SECRETS on the target."
  info "future rebuilds on the target will auto-detect it via the Justfile."
  info "to pull updates later, set up a git remote in $REMOTE_SECRETS."
}

main "$@"
