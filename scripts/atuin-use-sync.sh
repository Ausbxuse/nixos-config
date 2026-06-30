#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: atuin-use-sync.sh [SYNC_ADDRESS]

Set Atuin's sync_address on this machine without committing the address to Nix.
If SYNC_ADDRESS is omitted, the script prompts for it.

This is meant for ad hoc or unenrolled hosts. Declarative private hosts should
set this from the private nix-secrets input instead.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

sync_address="${1:-${ATUIN_SYNC_ADDRESS:-}}"
if [ -z "$sync_address" ]; then
  read -r -p "Atuin sync address: " sync_address
fi

if [ -z "$sync_address" ]; then
  echo "sync address is required" >&2
  exit 1
fi

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/atuin"
config_file="$config_dir/config.toml"
mkdir -p "$config_dir"

if [ -L "$config_file" ]; then
  tmp="$(mktemp "$config_dir/config.toml.XXXXXX")"
  cp --dereference "$config_file" "$tmp"
  chmod 0600 "$tmp"
  mv "$tmp" "$config_file"
elif [ ! -e "$config_file" ]; then
  install -m 0600 /dev/null "$config_file"
elif [ ! -w "$config_file" ]; then
  chmod u+w "$config_file"
fi

atuin config set --type string sync_address "$sync_address"
atuin config get sync_address
