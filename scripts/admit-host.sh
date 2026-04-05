#!/usr/bin/env bash
# admit-host: regenerate nix-secrets/.sops.yaml from the flake's host list.
#
# The trust mesh is implicit: every host defined in machines/defs.nix with a
# `sops.ageKey` field is a sops recipient, plus every entry in
# machines/operators.nix. This script reads both via `nix eval`, rewrites
# nix-secrets/.sops.yaml deterministically, and runs `sops updatekeys` to
# re-encrypt secrets.yaml with the current recipient set.
#
# Usage:
#   admit-host                                     regenerate + updatekeys
#   admit-host --set-host-key HOST AGEKEY          patch machines/defs.nix to
#                                                  set HOST's sops.ageKey, then
#                                                  regen
#   admit-host --set-host-syncthing HOST DEVICEID  patch machines/defs.nix to
#                                                  set HOST's syncthing.deviceId,
#                                                  then regen
#
# Adding/removing a host = editing machines/defs.nix directly. This script
# does NOT mutate defs.nix except via --set-host-key / --set-host-syncthing,
# which exist so provision.sh can inject freshly-derived host state
# non-interactively.
#
# Environment:
#   NIX_SECRETS_PATH   path to the nix-secrets git checkout
#                      (default: $HOME/src/private/nix-secrets)
#   NIXOS_CONFIG_PATH  path to the nixos-config repo (default: current dir)

set -euo pipefail
IFS=$'\n\t'

die()  { printf 'admit-host: %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32mOK\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }

NIXOS_CONFIG_PATH="${NIXOS_CONFIG_PATH:-$PWD}"
NIX_SECRETS_PATH="${NIX_SECRETS_PATH:-$HOME/src/private/nix-secrets}"

DEFS_FILE="$NIXOS_CONFIG_PATH/machines/defs.nix"
OPERATORS_FILE="$NIXOS_CONFIG_PATH/machines/operators.nix"
SOPS_YAML="$NIX_SECRETS_PATH/.sops.yaml"
SECRETS_FILE="$NIX_SECRETS_PATH/secrets.yaml"

[[ -f "$DEFS_FILE" ]]      || die "host defs not found: $DEFS_FILE"
[[ -f "$OPERATORS_FILE" ]] || die "operators file not found: $OPERATORS_FILE"
[[ -d "$NIX_SECRETS_PATH" ]] || die "nix-secrets repo not found: $NIX_SECRETS_PATH"
[[ -f "$SECRETS_FILE" ]]   || die "secrets file not found: $SECRETS_FILE"

# -------------------------------------------------------------------- args

MODE="rotate"
SET_HOST=""
SET_KEY=""
SET_DEVID=""

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
    --help|-h)
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
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
  # syncthing device IDs are 56-char base32 in 7 dash-separated groups, e.g.
  # ABCDEFG-HIJKLMN-... (length 63 with dashes). Be lenient — just sanity-check.
  [[ "$SET_DEVID" =~ ^[A-Z0-9-]+$ && ${#SET_DEVID} -ge 56 ]] \
    || die "syncthing device id does not look valid: $SET_DEVID"
fi

# -------------------------------------------------------------------- decryption identity
#
# sops updatekeys must decrypt secrets.yaml before re-encrypting it. Check up
# front so we fail BEFORE touching any files. sops reads age identities via
# SOPS_AGE_KEY_FILE / SOPS_AGE_KEY / SOPS_AGE_KEY_CMD. If none is set, try to
# derive one from the host SSH key with ssh-to-age.

if [[ -z "${SOPS_AGE_KEY_FILE:-}" && -z "${SOPS_AGE_KEY:-}" && -z "${SOPS_AGE_KEY_CMD:-}" ]]; then
  if [[ -r /var/lib/sops-nix/key.txt ]]; then
    export SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt
    info "using decryption identity: /var/lib/sops-nix/key.txt"
  elif [[ -r /etc/ssh/ssh_host_ed25519_key ]]; then
    _age_tmp=$(mktemp)
    chmod 600 "$_age_tmp"
    # shellcheck disable=SC2064
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

# -------------------------------------------------------------------- --set-host-key

# Patch machines/defs.nix in place: inside the block `  ${HOST} = {` ... `  };`,
# either replace an existing `sops.ageKey = "...";` line or insert one right
# after the opening brace. Uses awk for AST-free but structurally precise edit.
patch_host_field() {
  # patch_host_field HOST FIELD_REGEX INSERT_LINE
  # Inside the block `  ${HOST} = {` ... `  };`, replace any existing line
  # whose left-hand-side matches FIELD_REGEX (at host top-level) with
  # INSERT_LINE, or insert INSERT_LINE right after the opening brace if no
  # such line exists.
  local host="$1" field_re="$2" insert_line="$3"
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
        # Insert right after the opening brace; any pre-existing matching
        # line is dropped below so we effectively replace-or-insert.
        print insert_line
        next
      }
      if (in_host) {
        n = gsub(/\{/, "&", line); depth += n
        n = gsub(/\}/, "&", line); depth -= n
        # Drop any pre-existing field line at host top level.
        if (depth >= 1 && line ~ field_re) {
          next
        }
        print line
        if (depth == 0) { in_host = 0 }
        next
      }
      print line
    }
  ' "$DEFS_FILE" > "$tmp"

  if ! grep -q "^  ${host} = {" "$DEFS_FILE"; then
    rm -f "$tmp"
    die "host '${host}' not found in $DEFS_FILE (add it before setting its fields)"
  fi

  cat "$tmp" > "$DEFS_FILE"
  rm -f "$tmp"
}

# Patch machines/defs.nix in place for --set-host-key / --set-host-syncthing.
if [[ "$MODE" == "set-host-key" ]]; then
  info "patching $DEFS_FILE: ${SET_HOST}.sops.ageKey"
  patch_host_field "$SET_HOST" \
    '^[[:space:]]*sops\.ageKey[[:space:]]*=' \
    "    sops.ageKey = \"${SET_KEY}\";"
  ok "defs.nix updated: ${SET_HOST}.sops.ageKey"
fi

if [[ "$MODE" == "set-host-syncthing" ]]; then
  info "patching $DEFS_FILE: ${SET_HOST}.syncthing.deviceId"
  patch_host_field "$SET_HOST" \
    '^[[:space:]]*syncthing\.deviceId[[:space:]]*=' \
    "    syncthing.deviceId = \"${SET_DEVID}\";"
  ok "defs.nix updated: ${SET_HOST}.syncthing.deviceId"
fi

# -------------------------------------------------------------------- read keys from flake

info "enumerating recipients from $DEFS_FILE and $OPERATORS_FILE"

# Read host age keys: { hostname = "age1..."; } from every host in defs.nix
# that declares sops.ageKey. Nix stub so we don't need const/lib.
host_keys_json=$(nix eval --impure --json --expr "
  let
    defs = import $DEFS_FILE { lib = (import <nixpkgs> {}).lib; const = { username = \"x\"; supported-systems = []; }; };
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
") || die "failed to evaluate host keys from $DEFS_FILE"

operator_keys_json=$(nix eval --impure --json --expr "import $OPERATORS_FILE") \
  || die "failed to evaluate operator keys from $OPERATORS_FILE"

# Merge into one sorted list of (name, key) — operator names get a leading
# '@' in the YAML anchor so they can't collide with hostnames.
merged_json=$(jq -n \
  --argjson hosts "$host_keys_json" \
  --argjson ops "$operator_keys_json" \
  '($hosts | to_entries | map({name: .key, key: .value, anchor: .key}))
 + ($ops   | to_entries | map({name: ("@" + .key), key: .value, anchor: (.key + "_op")}))
 | sort_by(.anchor)')

count=$(printf '%s' "$merged_json" | jq 'length')
if [[ "$count" -eq 0 ]]; then
  die "refusing to write empty .sops.yaml — no recipients found"
fi

# -------------------------------------------------------------------- regenerate .sops.yaml

info "regenerating $SOPS_YAML"
{
  cat <<'HEAD'
# GENERATED FILE — do not edit by hand.
# Source of truth: nixos-config/machines/defs.nix (per-host sops.ageKey)
#                + nixos-config/machines/operators.nix (human operators).
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
} > "$SOPS_YAML"

ok ".sops.yaml regenerated ($count recipient(s))"

# -------------------------------------------------------------------- sops updatekeys

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

# -------------------------------------------------------------------- summary

printf '\n'
info "done. changes staged (not committed):"
if [[ "$MODE" == "set-host-key" || "$MODE" == "set-host-syncthing" ]]; then
  printf '  %s\n' "$DEFS_FILE"
fi
printf '  %s\n' "$SOPS_YAML"
printf '  %s\n' "$SECRETS_FILE"
