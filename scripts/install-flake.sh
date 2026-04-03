#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly REPO_SOURCE='@repoSource@'
readonly HOST_DEFS_FILE='@hostDefsFile@'
readonly DEFAULT_USERNAME='@username@'
readonly SECRET_KEY_PATH='/tmp/secret.key'

HOST=""
SYSTEM=""
DISK=""
USERNAME=""
NIXOS_MODE=""
HOME_MODE=""
NIXOS_PROFILE=""
HOME_PROFILE=""
DISPLAY_PROFILE=""
SWAP_SIZE=""
INSTALL_LAYOUT=""
PLATFORM=""
VISIBILITY=""
COPY_REPO=""
REPO_DEST=""
ASSUME_YES=0
KNOWN_HOST=0
WORKTREE=""

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -f "$SECRET_KEY_PATH" ]]; then
    sudo rm -f "$SECRET_KEY_PATH"
  fi
  if [[ -n "$WORKTREE" && -d "$WORKTREE" ]]; then
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

prompt_text() {
  local prompt=$1
  local default=${2-}
  local reply

  if [[ -n "$default" ]]; then
    read -e -i "$default" -rp "$prompt: " reply
    printf '%s\n' "${reply:-$default}"
  else
    read -e -rp "$prompt: " reply
    [[ -n "${reply:-}" ]] || die "$prompt cannot be empty."
    printf '%s\n' "$reply"
  fi
}

prompt_bool() {
  local prompt=$1
  local default=${2:-yes}
  local reply

  if [[ $ASSUME_YES -eq 1 ]]; then
    return 0
  fi

  if [[ "$default" == "yes" ]]; then
    read -r -p "$prompt [Y/n] " reply
    [[ -z "$reply" || "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
  else
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
  fi
}

detect_system() {
  case "$(uname -m)" in
    x86_64) printf 'x86_64-linux\n' ;;
    aarch64|arm64) printf 'aarch64-linux\n' ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
}

suggest_nixos_profile() {
  if command -v lspci >/dev/null 2>&1 && lspci | grep -qi 'NVIDIA'; then
    printf 'portable-nvidia-gnome\n'
  else
    printf 'portable-gnome\n'
  fi
}

host_known() {
  jq -e --arg host "$1" 'has($host)' "$HOST_DEFS_FILE" >/dev/null
}

host_query() {
  local host=$1
  local query=$2
  jq -r --arg host "$host" "$query" "$HOST_DEFS_FILE"
}

host_bool() {
  if [[ "$(host_query "$1" "$2")" == "true" ]]; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

list_known_hosts() {
  jq -r 'keys[]' "$HOST_DEFS_FILE"
}

list_disks() {
  lsblk -ndo PATH,TYPE,RM,SIZE,MODEL,TRAN | awk '$2=="disk" && $3==0 {print $1 "  " $4 "  " $5 "  " $6}'
}

default_disk() {
  local disks
  mapfile -t disks < <(lsblk -ndo PATH,TYPE,RM | awk '$2=="disk" && $3==0 {print $1}')
  if [[ ${#disks[@]} -eq 1 ]]; then
    printf '%s\n' "${disks[0]}"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)
        HOST=${2:?missing value for --host}
        shift 2
        ;;
      --disk)
        DISK=${2:?missing value for --disk}
        shift 2
        ;;
      --system)
        SYSTEM=${2:?missing value for --system}
        shift 2
        ;;
      --username)
        USERNAME=${2:?missing value for --username}
        shift 2
        ;;
      --nixos)
        NIXOS_MODE=yes
        shift
        ;;
      --no-nixos)
        NIXOS_MODE=no
        shift
        ;;
      --home)
        HOME_MODE=yes
        shift
        ;;
      --no-home)
        HOME_MODE=no
        shift
        ;;
      --nixos-profile)
        NIXOS_PROFILE=${2:?missing value for --nixos-profile}
        shift 2
        ;;
      --home-profile)
        HOME_PROFILE=${2:?missing value for --home-profile}
        shift 2
        ;;
      --display-profile)
        DISPLAY_PROFILE=${2:?missing value for --display-profile}
        shift 2
        ;;
      --swap-size)
        SWAP_SIZE=${2:?missing value for --swap-size}
        shift 2
        ;;
      --copy-repo)
        COPY_REPO=${2:?missing value for --copy-repo}
        shift 2
        ;;
      --repo-dest)
        REPO_DEST=${2:?missing value for --repo-dest}
        shift 2
        ;;
      -y|--yes)
        ASSUME_YES=1
        shift
        ;;
      -h|--help)
        cat <<'EOF'
Usage:
  nix run .#install -- [options]

Options:
  --host NAME              Known host name or a new ad hoc host name
  --disk PATH              Target disk for NixOS installation
  --system SYSTEM          Override detected system, e.g. x86_64-linux
  --username NAME          Override the host user name
  --nixos / --no-nixos     Enable or disable NixOS installation mode
  --home / --no-home       Enable or disable Home Manager mode
  --nixos-profile NAME     Profile file basename under modules/profiles/nixos/
  --home-profile NAME      Profile file basename under modules/profiles/home/
  --display-profile NAME   Display profile for ad hoc home configs
  --swap-size SIZE         Swapfile size for ad hoc disk configs, e.g. 32G
  --copy-repo yes|no       Copy the resulting repo into the installed system
  --repo-dest PATH         Destination for copied repo inside the target root
  -y, --yes                Accept destructive prompts
EOF
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

resolve_target() {
  if [[ -z "$HOST" ]]; then
    printf 'Known hosts:\n'
    list_known_hosts | sed 's/^/  - /'
    HOST=$(prompt_text "Host name for install or bootstrap")
  fi

  if host_known "$HOST"; then
    KNOWN_HOST=1
    # jq filters are intentionally single-quoted here so `$host` is passed to jq via `--arg`.
    # shellcheck disable=SC2016
    SYSTEM=${SYSTEM:-$(host_query "$HOST" '.[$host].system // empty')}
    # shellcheck disable=SC2016
    USERNAME=${USERNAME:-$(host_query "$HOST" '.[$host].username // empty')}
    # shellcheck disable=SC2016
    PLATFORM=${PLATFORM:-$(host_query "$HOST" '.[$host].platform // "ad-hoc"')}
    # shellcheck disable=SC2016
    VISIBILITY=${VISIBILITY:-$(host_query "$HOST" '.[$host].visibility // "private"')}
    # shellcheck disable=SC2016
    INSTALL_LAYOUT=${INSTALL_LAYOUT:-$(host_query "$HOST" '.[$host].install.layout // empty')}
    # shellcheck disable=SC2016
    DISK=${DISK:-$(host_query "$HOST" '.[$host].install.disk // empty')}
    # shellcheck disable=SC2016
    SWAP_SIZE=${SWAP_SIZE:-$(host_query "$HOST" '.[$host].install.swapSize // empty')}
    # shellcheck disable=SC2016
    [[ -n "$NIXOS_MODE" ]] || NIXOS_MODE=$(host_bool "$HOST" '.[$host].nixos.enable // false')
    # shellcheck disable=SC2016
    [[ -n "$HOME_MODE" ]] || HOME_MODE=$(host_bool "$HOST" '.[$host].home.enable // false')
    # shellcheck disable=SC2016
    [[ -n "$NIXOS_PROFILE" ]] || NIXOS_PROFILE=$(host_query "$HOST" '.[$host].nixos.profile // empty')
    # shellcheck disable=SC2016
    [[ -n "$HOME_PROFILE" ]] || HOME_PROFILE=$(host_query "$HOST" '.[$host].home.profile // empty')
    # shellcheck disable=SC2016
    [[ -n "$DISPLAY_PROFILE" ]] || DISPLAY_PROFILE=$(host_query "$HOST" '.[$host].home.displayProfile // empty')
  else
    SYSTEM=${SYSTEM:-$(detect_system)}
    USERNAME=${USERNAME:-$DEFAULT_USERNAME}
    PLATFORM=${PLATFORM:-"ad-hoc"}
    VISIBILITY=${VISIBILITY:-"private"}
    INSTALL_LAYOUT=${INSTALL_LAYOUT:-"luks-btrfs"}
    if [[ -z "$NIXOS_MODE" ]]; then
      if prompt_bool "Install NixOS for ad hoc host '$HOST'?" yes; then
        NIXOS_MODE=yes
      else
        NIXOS_MODE=no
      fi
    fi
    if [[ -z "$HOME_MODE" ]]; then
      if prompt_bool "Set up Home Manager for ad hoc host '$HOST'?" yes; then
        HOME_MODE=yes
      else
        HOME_MODE=no
      fi
    fi
  fi

  USERNAME=${USERNAME:-$DEFAULT_USERNAME}
  [[ "$NIXOS_MODE" == "yes" || "$HOME_MODE" == "yes" ]] || die "Nothing to do: both NixOS and Home Manager modes are disabled."
}

resolve_ad_hoc_profiles() {
  [[ $KNOWN_HOST -eq 0 ]] || return 0

  if [[ "$NIXOS_MODE" == "yes" && -z "$NIXOS_PROFILE" ]]; then
    NIXOS_PROFILE=$(prompt_text "Ad hoc NixOS profile" "$(suggest_nixos_profile)")
  fi

  if [[ "$HOME_MODE" == "yes" && -z "$HOME_PROFILE" ]]; then
    HOME_PROFILE=$(prompt_text "Ad hoc home profile" "personal-gnome")
  fi

  if [[ "$HOME_MODE" == "yes" && -z "$DISPLAY_PROFILE" ]]; then
    DISPLAY_PROFILE=$(prompt_text "Ad hoc display profile" "gnome-default")
  fi

  if [[ "$NIXOS_MODE" == "yes" && -z "$SWAP_SIZE" ]]; then
    SWAP_SIZE=$(prompt_text "Ad hoc swap size" "32G")
  fi
}

resolve_disk() {
  [[ "$NIXOS_MODE" == "yes" ]] || return 0

  if [[ -z "$DISK" ]]; then
    local suggested_disk
    suggested_disk=$(default_disk || true)
    printf 'Available disks:\n'
    list_disks | sed 's/^/  /'
    DISK=$(prompt_text "Target disk" "$suggested_disk")
  fi

  [[ -b "$DISK" ]] || die "Not a block device: $DISK"
  [[ "$(lsblk -ndo TYPE "$DISK")" == "disk" ]] || die "Not a whole disk: $DISK"
}

prepare_worktree() {
  WORKTREE=$(mktemp -d "${TMPDIR:-/tmp}/nixos-installer.XXXXXX")
  rsync -a --delete "$REPO_SOURCE"/ "$WORKTREE"/
}

write_worktree_host_defs() {
  local base_defs="$WORKTREE/machines/defs-known.nix"
  local defs_file="$WORKTREE/machines/defs.nix"

  mv "$defs_file" "$base_defs"

  cat >"$defs_file" <<EOF
{lib, ...}:
  let
    defs = import ./defs-known.nix {inherit lib;};
  in
  defs
  // {
    ${HOST} = (defs.${HOST} or {})
    // {
      system = "${SYSTEM}";
      username = "${USERNAME}";
      platform = "${PLATFORM}";
      visibility = "${VISIBILITY}";
      home = {
        enable = $([[ "$HOME_MODE" == "yes" ]] && printf true || printf false);
      }$(
        if [[ -n "$HOME_PROFILE" || -n "$DISPLAY_PROFILE" ]]; then
          printf ' // {\n'
          if [[ -n "$HOME_PROFILE" ]]; then
            printf '          profile = "%s";\n' "$HOME_PROFILE"
          fi
          if [[ -n "$DISPLAY_PROFILE" ]]; then
            printf '          displayProfile = "%s";\n' "$DISPLAY_PROFILE"
          fi
          printf '        }'
        fi
      );
      nixos = {
        enable = $([[ "$NIXOS_MODE" == "yes" ]] && printf true || printf false);
      }$(
        if [[ -n "$NIXOS_PROFILE" ]]; then
          printf ' // {\n          profile = "%s";\n        }' "$NIXOS_PROFILE"
        fi
      );
      install = (defs.${HOST}.install or {})
      // {
        layout = "${INSTALL_LAYOUT}";
        disk = "${DISK}";
        swapSize = "${SWAP_SIZE}";
      };
    };
  }
EOF
}

prepare_target_config() {
  write_worktree_host_defs
  if [[ "$NIXOS_MODE" == "yes" ]]; then
    mkdir -p "$WORKTREE/machines/$HOST"
  fi
}

write_secret_key() {
  local luks_pw
  read -r -s -p "Enter LUKS disk password: " luks_pw
  printf '\n'
  [[ -n "${luks_pw:-}" ]] || die "LUKS password cannot be empty."
  printf '%s' "$luks_pw" | sudo tee "$SECRET_KEY_PATH" >/dev/null
  sudo chmod 600 "$SECRET_KEY_PATH"
}

run_nixos_install() {
  [[ "$NIXOS_MODE" == "yes" ]] || return 0

  write_secret_key

  info "Host: $HOST"
  info "System: $SYSTEM"
  info "Username: $USERNAME"
  info "Disk: $DISK"
  info "Working tree: $WORKTREE"

  if ! prompt_bool "This will destroy data on $DISK. Continue?" no; then
    die "Aborted."
  fi

  (
    cd "$WORKTREE"
    sudo disko --mode destroy,format,mount --flake ".#${HOST}"
    sudo nixos-generate-config --no-filesystems --root /mnt
    sudo install -D -m 0644 /mnt/etc/nixos/hardware-configuration.nix "machines/$HOST/hardware-configuration.nix"
    sudo nixos-install --root /mnt --flake ".#${HOST}"
  )
}

copy_repo_to_target() {
  [[ "$NIXOS_MODE" == "yes" ]] || return 0

  if [[ -z "$REPO_DEST" ]]; then
    REPO_DEST="/mnt/home/${USERNAME}/src/public/nixos-config"
  fi

  if [[ -z "$COPY_REPO" ]]; then
    if prompt_bool "Copy the configured repo to ${REPO_DEST}?" yes; then
      COPY_REPO=yes
    else
      COPY_REPO=no
    fi
  fi

  if [[ "$COPY_REPO" == "yes" ]]; then
    sudo mkdir -p "$(dirname "$REPO_DEST")"
    sudo rsync -a --delete "$WORKTREE"/ "${REPO_DEST}/"
  fi
}

run_home_install() {
  [[ "$HOME_MODE" == "yes" ]] || return 0
  if [[ "$NIXOS_MODE" == "yes" ]]; then
    return 0
  fi

  info "Running Home Manager for ${USERNAME}@${HOST}"
  nix run nixpkgs#home-manager -- switch --flake "${WORKTREE}#${USERNAME}@${HOST}"
}

main() {
  require_cmd jq rsync lsblk awk sed perl nix
  parse_args "$@"
  resolve_target
  resolve_ad_hoc_profiles
  resolve_disk
  prepare_worktree
  prepare_target_config
  run_nixos_install
  copy_repo_to_target
  run_home_install
  info "Finished for host ${HOST}"
}

main "$@"
