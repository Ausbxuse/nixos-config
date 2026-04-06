#!/usr/bin/env bash
# enroll: remote-drive a fresh NixOS host into the secrets trust mesh.
#
# Runs on a trusted peer (e.g. razy). Given a target hostname (as it appears
# in flake nixosConfigurations) and an SSH destination, it:
#
#   1. opens one persistent SSH master connection
#   2. reads the target's /etc/ssh/ssh_host_ed25519_key.pub
#   3. derives its age identity via ssh-to-age
#   4. admits it locally via admit-host (re-encrypts secrets.yaml)
#   5. generates a pinned syncthing identity for the target, encrypts cert/key
#      into nix-secrets/secrets.yaml, records the device id in defs.nix
#   6. rsyncs the private nix-secrets checkout to the target at /tmp/nix-secrets
#   7. runs nixos-rebuild switch on the target with --override-input nix-secrets

set -euo pipefail
IFS=$'\n\t'

HOSTNAME=""
SSH_DEST=""
REMOTE_FLAKE="/home/zhenyu/src/public/nixos-config"
NIXOS_CONFIG_PATH=""
NIX_SECRETS_PATH=""
DRY_RUN=0

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
  --remote-flake PATH    Flake path on the target (default: $REMOTE_FLAKE)
  --config-path PATH     Local nixos-config repo (default: \$PWD or \$NIXOS_CONFIG_PATH)
  --secrets-path PATH    Local nix-secrets checkout (default: \$HOME/src/private/nix-secrets
                         or \$NIX_SECRETS_PATH)
  --dry-run              Show the resolved plan and exit without making changes
  --no-color             Disable ANSI colors even on a TTY
  -y, --yes              Accept all confirmation prompts

Environment:
  NIXOS_CONFIG_PATH      Override local nixos-config path
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

  [[ -d "$NIXOS_CONFIG_PATH" ]] || die "nixos-config not found: $NIXOS_CONFIG_PATH"
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

  if [[ $DRY_RUN -eq 1 ]]; then
    kv "mode" "${C_YELLOW}dry run${C_RESET}"
  fi
}

step_ssh_connect() {
  section "1/6 establish persistent ssh session"

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
  section "2/6 derive target age identity"

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
  section "3/6 admit $HOSTNAME to trust mesh"

  if [[ $DRY_RUN -eq 1 ]]; then
    info "would run: admit-host --set-host-key $HOSTNAME <age-pubkey>"
    return 0
  fi

  (
    cd "$NIXOS_CONFIG_PATH"
    admit-host --set-host-key "$HOSTNAME" "$target_age_pub"
  ) || die "admit-host failed"
  ok "admission complete"
}

step_syncthing() {
  section "4/6 generate syncthing identity for $HOSTNAME"

  if [[ $DRY_RUN -eq 1 ]]; then
    info "would generate syncthing cert/key pair"
    info "would encrypt into $NIX_SECRETS_PATH/secrets.yaml"
    info "would record device id in defs.nix"
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

  info "recording device id in defs.nix"
  (
    cd "$NIXOS_CONFIG_PATH"
    admit-host --set-host-syncthing "$HOSTNAME" "$devid"
  ) || die "admit-host --set-host-syncthing failed"
  ok "syncthing identity pinned"
}

step_rsync() {
  section "5/6 rsync nix-secrets + nixos-config to target"

  if [[ $DRY_RUN -eq 1 ]]; then
    info "would rsync $NIX_SECRETS_PATH -> $ssh_user_host:/tmp/nix-secrets/"
    info "would rsync $NIXOS_CONFIG_PATH -> $ssh_user_host:$REMOTE_FLAKE/"
    info "  (excluding .git, machines/defs.nix, machines/$HOSTNAME/)"
    return 0
  fi

  local rsync_ssh_cmd
  rsync_ssh_cmd=$(build_rsync_ssh_cmd)

  run_with_spinner "syncing nix-secrets to target" \
    rsync -a --delete --exclude=.git \
      -e "$rsync_ssh_cmd" \
      "$NIX_SECRETS_PATH"/ "$ssh_user_host:/tmp/nix-secrets/"

  run_with_spinner "syncing nixos-config to target" \
    rsync -a --delete \
      --exclude='.git' \
      --exclude='machines/defs.nix' \
      --exclude="machines/${HOSTNAME}/" \
      -e "$rsync_ssh_cmd" \
      "$NIXOS_CONFIG_PATH"/ "$ssh_user_host:${REMOTE_FLAKE}/"

  ok "nixos-config refreshed (defs.nix + machines/${HOSTNAME}/ preserved)"
}

step_rebuild() {
  section "6/6 nixos-rebuild switch on target"

  if [[ $DRY_RUN -eq 1 ]]; then
    info "would run nixos-rebuild switch --flake .#$HOSTNAME on target"
    info "  with --override-input nix-secrets path:/tmp/nix-secrets"
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
  --override-input nix-secrets path:/tmp/nix-secrets \
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
  setup_ssh_vars
  recap

  if ! prompt_bool "proceed?" yes; then
    die "aborted."
  fi

  local target_host_pub=""
  local target_age_pub=""

  step_ssh_connect
  step_derive_age
  step_admit
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
  kv "" "$NIXOS_CONFIG_PATH/machines/defs.nix"
  kv "" "$NIX_SECRETS_PATH/.sops.yaml"
  kv "" "$NIX_SECRETS_PATH/secrets.yaml"
  printf '\n'
  warn "/tmp/nix-secrets on the target holds the private repo. If the target is"
  warn "ephemeral (VM), shut it down. If persistent, wire up a real flake input"
  warn "(git remote) so it no longer depends on /tmp/nix-secrets."
}

main "$@"
