#!/usr/bin/env bash
# admit-host: promote staged hosts into nix-secrets/hosts.nix and regenerate
# nix-secrets/.sops.yaml from the canonical host list.
#
# Canonical admitted hosts live in nix-secrets/hosts.nix. Public
# machines/defs.nix is a staging registry for hosts that have not been
# admitted yet.
#
# Usage:
#   admit-host                                     regenerate + updatekeys
#   admit-host --set-host-key HOST AGEKEY          promote HOST if needed,
#                                                  set HOST.sops.ageKey in
#                                                  nix-secrets/hosts.nix, then
#                                                  regen
#   admit-host --set-host-syncthing HOST DEVICEID  promote HOST if needed,
#                                                  set HOST.syncthing.deviceId
#                                                  in nix-secrets/hosts.nix,
#                                                  then regen
#   admit-host --set-host-user-ssh-key HOST PUBKEY promote HOST if needed,
#                                                  set HOST.userSshPubKey in
#                                                  nix-secrets/hosts.nix, then
#                                                  regen
#
# Environment:
#   NIX_SECRETS_PATH   path to the nix-secrets git checkout
#                      (default: $HOME/src/private/nix-secrets)
#   NIXOS_CONFIG_PATH  path to the nix-config repo (default: current dir)

set -euo pipefail
IFS=$'\n\t'

die()  { printf 'admit-host: %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32mOK\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }

NIXOS_CONFIG_PATH="${NIXOS_CONFIG_PATH:-$PWD}"
NIX_SECRETS_PATH="${NIX_SECRETS_PATH:-$HOME/src/private/nix-secrets}"

STAGING_DEFS_FILE="$NIXOS_CONFIG_PATH/machines/defs.nix"
PRIVATE_HOSTS_FILE="$NIX_SECRETS_PATH/hosts.nix"
SOPS_YAML="$NIX_SECRETS_PATH/.sops.yaml"
SECRETS_FILE="$NIX_SECRETS_PATH/secrets.yaml"

[[ -f "$STAGING_DEFS_FILE" ]] || die "staging host defs not found: $STAGING_DEFS_FILE"
[[ -d "$NIX_SECRETS_PATH" ]] || die "nix-secrets repo not found: $NIX_SECRETS_PATH"
[[ -f "$SECRETS_FILE" ]] || die "secrets file not found: $SECRETS_FILE"
if [[ ! -f "$PRIVATE_HOSTS_FILE" ]]; then
  cat >"$PRIVATE_HOSTS_FILE" <<'EOF'
{lib, const, ...}: {
}
EOF
fi

MODE="rotate"
SET_HOST=""
SET_KEY=""
SET_DEVID=""
SET_USER_SSH_PUBKEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --set-host-key)
      MODE="set-host-key"
      SET_HOST="${2:-}"
      SET_KEY="${3:-}"
      shift 3 || die "--set-host-key requires HOST and AGEKEY"
      ;;
    --set-host-syncthing)
      MODE="set-host-syncthing"
      SET_HOST="${2:-}"
      SET_DEVID="${3:-}"
      shift 3 || die "--set-host-syncthing requires HOST and DEVICEID"
      ;;
    --set-host-user-ssh-key)
      MODE="set-host-user-ssh-key"
      SET_HOST="${2:-}"
      SET_USER_SSH_PUBKEY="${3:-}"
      shift 3 || die "--set-host-user-ssh-key requires HOST and PUBKEY"
      ;;
    --help|-h)
      sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

if [[ "$MODE" == "set-host-key" ]]; then
  [[ -n "$SET_HOST" && -n "$SET_KEY" ]] || die "--set-host-key requires HOST and AGEKEY"
  [[ "$SET_KEY" == age1* && ${#SET_KEY} -ge 62 ]] \
    || die "age key does not look valid: $SET_KEY"
fi

if [[ "$MODE" == "set-host-syncthing" ]]; then
  [[ -n "$SET_HOST" && -n "$SET_DEVID" ]] || die "--set-host-syncthing requires HOST and DEVICEID"
  [[ "$SET_DEVID" =~ ^[A-Z0-9-]+$ && ${#SET_DEVID} -ge 56 ]] \
    || die "syncthing device id does not look valid: $SET_DEVID"
fi

if [[ "$MODE" == "set-host-user-ssh-key" ]]; then
  [[ -n "$SET_HOST" && -n "$SET_USER_SSH_PUBKEY" ]] || die "--set-host-user-ssh-key requires HOST and PUBKEY"
  [[ "$SET_USER_SSH_PUBKEY" =~ ^ssh-(ed25519|rsa|ecdsa)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]] \
    || die "user ssh pubkey does not look valid: $SET_USER_SSH_PUBKEY"
fi

if [[ -z "${SOPS_AGE_KEY_FILE:-}" && -z "${SOPS_AGE_KEY:-}" && -z "${SOPS_AGE_KEY_CMD:-}" ]]; then
  if [[ -r /var/lib/sops-nix/key.txt ]]; then
    export SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt
    info "using decryption identity: /var/lib/sops-nix/key.txt"
  elif [[ -r /etc/ssh/ssh_host_ed25519_key ]]; then
    _age_tmp=$(mktemp)
    chmod 600 "$_age_tmp"
    trap "rm -f '$_age_tmp'" EXIT
    if ! ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key -o "$_age_tmp" 2>/dev/null; then
      die "ssh-to-age failed to convert /etc/ssh/ssh_host_ed25519_key"
    fi
    export SOPS_AGE_KEY_FILE="$_age_tmp"
    info "using decryption identity: derived from /etc/ssh/ssh_host_ed25519_key (tempfile)"
  fi
fi

if [[ -z "${SOPS_AGE_KEY_FILE:-}" && -z "${SOPS_AGE_KEY:-}" && -z "${SOPS_AGE_KEY_CMD:-}" ]]; then
  warn "no readable decryption identity found."
  warn "re-run with sudo (to read /etc/ssh/ssh_host_ed25519_key via ssh-to-age),"
  warn "or export SOPS_AGE_KEY_FILE / SOPS_AGE_KEY / SOPS_AGE_KEY_CMD."
  die "cannot run sops updatekeys without a decryption identity"
fi

host_defined_in_file() {
  local file="$1" host="$2"
  grep -q "^  ${host} = {" "$file"
}

ensure_host_stub() {
  local file="$1" host="$2"
  if host_defined_in_file "$file" "$host"; then
    return 0
  fi

  info "host '${host}' not found in $(basename "$file") — inserting minimal stub"
  local tmp
  tmp=$(mktemp)
  awk -v host="$host" '
    { lines[NR] = $0 }
    END {
      last_close = 0
      for (i = NR; i >= 1; i--) {
        if (lines[i] ~ /^\}[[:space:]]*$/) { last_close = i; break }
      }
      if (last_close == 0) { exit 2 }
      for (i = 1; i <= NR; i++) {
        if (i == last_close) {
          print ""
          print "  " host " = {"
          print "    system = \"x86_64-linux\";"
          print "    username = const.username;"
          print "    platform = \"custom\";"
          print "    visibility = \"private\";"
          print "  };"
        }
        print lines[i]
      }
    }
  ' "$file" >"$tmp" || { rm -f "$tmp"; die "failed to locate top-level brace in $file"; }
  cat "$tmp" >"$file"
  rm -f "$tmp"
  ok "$(basename "$file"): inserted stub for ${host}"
}

extract_host_block() {
  local file="$1" host="$2"
  awk -v host="$host" '
    BEGIN { capture = 0; depth = 0 }
    {
      line = $0
      if (!capture && line ~ ("^  " host " = \\{[[:space:]]*$")) {
        capture = 1
        depth = 1
        print line
        next
      }
      if (capture) {
        print line
        n = gsub(/\{/, "&", line); depth += n
        n = gsub(/\}/, "&", line); depth -= n
        if (depth == 0) {
          exit 0
        }
      }
    }
    END {
      if (!capture) exit 1
      if (depth != 0) exit 2
    }
  ' "$file"
}

remove_host_block() {
  local file="$1" host="$2"
  local tmp
  tmp=$(mktemp)
  awk -v host="$host" '
    BEGIN { skip = 0; depth = 0 }
    {
      line = $0
      if (!skip && line ~ ("^  " host " = \\{[[:space:]]*$")) {
        skip = 1
        depth = 1
        next
      }
      if (skip) {
        n = gsub(/\{/, "&", line); depth += n
        n = gsub(/\}/, "&", line); depth -= n
        if (depth == 0) {
          skip = 0
        }
        next
      }
      print line
    }
  ' "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

append_host_block() {
  local file="$1" block_file="$2"
  local tmp
  tmp=$(mktemp)
  awk -v block_file="$block_file" '
    BEGIN {
      while ((getline line < block_file) > 0) {
        block[++block_len] = line
      }
      close(block_file)
    }
    { lines[NR] = $0 }
    END {
      last_close = 0
      for (i = NR; i >= 1; i--) {
        if (lines[i] ~ /^\}[[:space:]]*$/) { last_close = i; break }
      }
      if (last_close == 0) exit 2
      for (i = 1; i <= NR; i++) {
        if (i == last_close) {
          if (block_len > 0) {
            print ""
            for (j = 1; j <= block_len; j++) {
              print block[j]
            }
          }
        }
        print lines[i]
      }
    }
  ' "$file" >"$tmp" || { rm -f "$tmp"; die "failed to locate top-level brace in $file"; }
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

patch_host_field() {
  local file="$1" host="$2" field_re="$3" insert_line="$4"
  local tmp
  tmp=$(mktemp)
  awk -v host="$host" -v field_re="$field_re" -v insert_line="$insert_line" '
    BEGIN { in_host = 0; depth = 0 }
    {
      line = $0
      if (!in_host && match(line, "^  " host " = \\{[[:space:]]*$")) {
        in_host = 1
        depth = 1
        print line
        print insert_line
        next
      }
      if (in_host) {
        n = gsub(/\{/, "&", line); depth += n
        n = gsub(/\}/, "&", line); depth -= n
        if (depth >= 1 && line ~ field_re) {
          next
        }
        print line
        if (depth == 0) { in_host = 0 }
        next
      }
      print line
    }
  ' "$file" >"$tmp"

  if ! host_defined_in_file "$file" "$host"; then
    rm -f "$tmp"
    die "host '${host}' not found in $file"
  fi

  cat "$tmp" >"$file"
  rm -f "$tmp"
}

promote_host() {
  local host="$1"
  local block_tmp

  if host_defined_in_file "$PRIVATE_HOSTS_FILE" "$host"; then
    if host_defined_in_file "$STAGING_DEFS_FILE" "$host"; then
      info "removing duplicate staged host '${host}' from $(basename "$STAGING_DEFS_FILE")"
      remove_host_block "$STAGING_DEFS_FILE" "$host"
      ok "staging defs updated: removed ${host}"
    fi
    return 0
  fi

  if host_defined_in_file "$STAGING_DEFS_FILE" "$host"; then
    block_tmp=$(mktemp)
    extract_host_block "$STAGING_DEFS_FILE" "$host" >"$block_tmp" \
      || { rm -f "$block_tmp"; die "failed to extract staged host '${host}'"; }
    append_host_block "$PRIVATE_HOSTS_FILE" "$block_tmp"
    remove_host_block "$STAGING_DEFS_FILE" "$host"
    rm -f "$block_tmp"
    ok "promoted ${host} from staging defs into hosts.nix"
    return 0
  fi

  warn "host '${host}' not found in staging defs or private hosts; creating minimal private stub"
  ensure_host_stub "$PRIVATE_HOSTS_FILE" "$host"
}

if [[ "$MODE" != "rotate" ]]; then
  promote_host "$SET_HOST"
fi

if [[ "$MODE" == "set-host-key" ]]; then
  info "patching $PRIVATE_HOSTS_FILE: ${SET_HOST}.sops.ageKey"
  patch_host_field "$PRIVATE_HOSTS_FILE" "$SET_HOST" \
    '^[[:space:]]*sops\.ageKey[[:space:]]*=' \
    "    sops.ageKey = \"${SET_KEY}\";"
  ok "hosts.nix updated: ${SET_HOST}.sops.ageKey"
fi

if [[ "$MODE" == "set-host-syncthing" ]]; then
  info "patching $PRIVATE_HOSTS_FILE: ${SET_HOST}.syncthing.deviceId"
  patch_host_field "$PRIVATE_HOSTS_FILE" "$SET_HOST" \
    '^[[:space:]]*syncthing\.deviceId[[:space:]]*=' \
    "    syncthing.deviceId = \"${SET_DEVID}\";"
  ok "hosts.nix updated: ${SET_HOST}.syncthing.deviceId"
fi

if [[ "$MODE" == "set-host-user-ssh-key" ]]; then
  info "patching $PRIVATE_HOSTS_FILE: ${SET_HOST}.userSshPubKey"
  patch_host_field "$PRIVATE_HOSTS_FILE" "$SET_HOST" \
    '^[[:space:]]*userSshPubKey[[:space:]]*=' \
    "    userSshPubKey = \"${SET_USER_SSH_PUBKEY}\";"
  ok "hosts.nix updated: ${SET_HOST}.userSshPubKey"
fi

info "enumerating recipients from $PRIVATE_HOSTS_FILE"

host_keys_json=$(nix eval --impure --json --expr "
  let
    defs = import $PRIVATE_HOSTS_FILE { lib = (import <nixpkgs> {}).lib; const = { username = \"x\"; supported-systems = []; }; };
  in
    builtins.listToAttrs (
      builtins.filter (x: x != null) (
        builtins.attrValues (
          builtins.mapAttrs (name: def:
            if def ? sops && def.sops ? ageKey
            then { inherit name; value = def.sops.ageKey; }
            else null
          ) defs
        )
      )
    )
") || die "failed to evaluate host keys from $PRIVATE_HOSTS_FILE"

merged_json=$(jq -n \
  --argjson hosts "$host_keys_json" \
  '($hosts | to_entries | map({name: .key, key: .value, anchor: .key}))
 | sort_by(.anchor)')

count=$(printf '%s' "$merged_json" | jq 'length')
if [[ "$count" -eq 0 ]]; then
  die "refusing to write empty .sops.yaml — no recipients found"
fi

info "regenerating $SOPS_YAML"
{
  cat <<'HEAD'
# GENERATED FILE — do not edit by hand.
# Source of truth: nix-secrets/hosts.nix (admitted hosts with sops.ageKey)
# Regenerate with: nix run .#admit-host

keys:
HEAD

  printf '%s' "$merged_json" | jq -r '.[] | "  - &\(.anchor) \(.key)"'

  cat <<'MID'

creation_rules:
  - path_regex: secrets\.yaml$
    key_groups:
      - age:
MID

  printf '%s' "$merged_json" | jq -r '.[] | "          - *\(.anchor)"'
} >"$SOPS_YAML"

ok ".sops.yaml regenerated ($count recipient(s))"

info "running sops updatekeys on $SECRETS_FILE"
pre_owner=$(stat -c '%u:%g' "$SECRETS_FILE" 2>/dev/null || true)
pre_mode=$(stat -c '%a' "$SECRETS_FILE" 2>/dev/null || true)
(
  cd "$NIX_SECRETS_PATH"
  sops updatekeys -y secrets.yaml
)
if [[ -n "$pre_owner" ]]; then
  current_owner=$(stat -c '%u:%g' "$SECRETS_FILE" 2>/dev/null || true)
  if [[ "$current_owner" != "$pre_owner" ]]; then
    if chown "$pre_owner" "$SECRETS_FILE" 2>/dev/null; then
      info "restored ownership on secrets.yaml ($pre_owner)"
    else
      warn "failed to restore ownership on secrets.yaml (wanted $pre_owner)"
    fi
  fi
fi
if [[ -n "$pre_mode" ]]; then
  chmod "$pre_mode" "$SECRETS_FILE" 2>/dev/null || true
fi
ok "secrets.yaml re-encrypted with current key set"

printf '\n'
info "done. changes staged (not committed):"
if [[ "$MODE" != "rotate" ]]; then
  printf '  %s\n' "$STAGING_DEFS_FILE"
  printf '  %s\n' "$PRIVATE_HOSTS_FILE"
fi
printf '  %s\n' "$SOPS_YAML"
printf '  %s\n' "$SECRETS_FILE"
