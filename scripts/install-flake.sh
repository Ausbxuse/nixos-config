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
DRY_RUN=0
USE_COLOR=1
WORKTREE=""

# --------------------------------------------------------------------- colors

# Respect NO_COLOR, --no-color, and non-TTY stdout.
if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
  USE_COLOR=0
fi
# (Re-checked after parse_args so --no-color on a TTY still disables.)

C_RESET=""
C_DIM=""
C_BOLD=""
C_RED=""
C_GREEN=""
C_YELLOW=""
C_BLUE=""
C_CYAN=""
C_MAGENTA=""

_SYM_SEC="■"
_SYM_INFO="·"
_SYM_OK="✓"
_SYM_WARN="!"
_SYM_ERR="✗"
_SYM_MARK="›"

apply_colors() {
  if [[ $USE_COLOR -eq 1 ]]; then
    C_RESET=$'\033[0m'
    C_DIM=$'\033[2m'
    C_BOLD=$'\033[1m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
    C_MAGENTA=$'\033[35m'
    _SYM_SEC="■"; _SYM_INFO="·"; _SYM_OK="✓"; _SYM_WARN="!"; _SYM_ERR="✗"; _SYM_MARK="›"
  else
    C_RESET=""; C_DIM=""; C_BOLD=""
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""; C_MAGENTA=""
    _SYM_SEC=">"; _SYM_INFO="-"; _SYM_OK="+"; _SYM_WARN="!"; _SYM_ERR="x"; _SYM_MARK=">"
  fi
}
apply_colors

# --------------------------------------------------------------------- output

section() { printf '\n%s%s %s%s\n' "${C_BOLD}${C_MAGENTA}" "$_SYM_SEC" "$*" "${C_RESET}"; }
info()    { printf '  %s%s%s %s\n' "${C_BLUE}"   "$_SYM_INFO" "${C_RESET}" "$*"; }
ok()      { printf '  %s%s%s %s\n' "${C_GREEN}"  "$_SYM_OK"   "${C_RESET}" "$*"; }
warn()    { printf '  %s%s%s %s\n' "${C_YELLOW}" "$_SYM_WARN" "${C_RESET}" "$*" >&2; }
err()     { printf '  %s%s%s %s\n' "${C_RED}"    "$_SYM_ERR"  "${C_RESET}" "$*" >&2; }
die()     { err "$*"; exit 1; }

kv() {
  # kv LABEL VALUE — aligned two-column print for recaps.
  printf '  %s%-13s%s %s\n' "${C_DIM}" "$1" "${C_RESET}" "$2"
}

# --------------------------------------------------------------------- spinner

# run_with_spinner MSG CMD [ARGS...]
# Runs CMD in the foreground while a small spinner animates on its own line.
# Output of CMD is suppressed to keep the spinner clean; stderr is captured to
# a tempfile and streamed on failure so errors aren't lost.
run_with_spinner() {
  local msg=$1
  shift
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  if [[ $USE_COLOR -eq 0 ]]; then
    frames="|/-\\"
  fi
  local stderr_log
  stderr_log=$(mktemp)
  "$@" >/dev/null 2>"$stderr_log" &
  local pid=$!
  local i=0 n=${#frames}
  # Only animate when stderr (where we draw) is a TTY.
  if [[ -t 2 ]]; then
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r  %s%s%s %s' "${C_CYAN}" "${frames:i%n:1}" "${C_RESET}" "$msg" >&2
      i=$((i + 1))
      sleep 0.1
    done
    printf '\r\033[K' >&2
  else
    info "$msg"
    wait "$pid" || true
  fi
  if wait "$pid"; then
    ok "$msg"
    rm -f "$stderr_log"
    return 0
  else
    local rc=$?
    err "$msg (exit $rc)"
    if [[ -s "$stderr_log" ]]; then
      sed 's/^/    /' "$stderr_log" >&2
    fi
    rm -f "$stderr_log"
    return "$rc"
  fi
}

# --------------------------------------------------------------------- prompts

# prompt_select PROMPT DEFAULT OPT1 OPT2 ...
# Renders a numbered menu, pre-selects DEFAULT (if it matches an option),
# validates input, and echoes the chosen option on stdout.
prompt_select() {
  local prompt=$1 default=$2
  shift 2
  local -a options=("$@")
  local n=${#options[@]}

  [[ $n -gt 0 ]] || die "prompt_select: no options provided for '$prompt'"

  printf '\n%s%s %s%s\n' "${C_BOLD}${C_MAGENTA}" "$_SYM_SEC" "$prompt" "${C_RESET}" >&2
  local i=1 default_idx=0
  for opt in "${options[@]}"; do
    if [[ "$opt" == "$default" ]]; then
      default_idx=$i
      printf '  %s%s%s %s%2d%s %s\n' \
        "${C_GREEN}" "$_SYM_MARK" "${C_RESET}" "${C_CYAN}" "$i" "${C_RESET}" "$opt" >&2
    else
      printf '    %s%2d%s %s\n' "${C_CYAN}" "$i" "${C_RESET}" "$opt" >&2
    fi
    ((i++))
  done

  local reply
  while true; do
    if [[ $default_idx -gt 0 ]]; then
      printf '  %s?%s [1-%d] ' "${C_BOLD}" "${C_RESET}" "$n" >&2
    else
      printf '  %s?%s [1-%d] ' "${C_BOLD}" "${C_RESET}" "$n" >&2
    fi
    read -r reply || die "no input"

    if [[ -z "$reply" && $default_idx -gt 0 ]]; then
      printf '%s\n' "${options[default_idx - 1]}"
      return 0
    fi
    if [[ "$reply" =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= n )); then
      printf '%s\n' "${options[reply - 1]}"
      return 0
    fi
    # Also accept the literal option text.
    for opt in "${options[@]}"; do
      if [[ "$reply" == "$opt" ]]; then
        printf '%s\n' "$opt"
        return 0
      fi
    done
    warn "Invalid selection: '$reply' — enter a number 1-$n."
  done
}

# prompt_text PROMPT DEFAULT [VALIDATOR]
# Free-text prompt with default and optional validator function.
# VALIDATOR receives the input as $1; returns 0 to accept, non-zero to reject
# (and may print its own warn/err message).
prompt_text() {
  local prompt=$1 default=${2-} validator=${3-}
  local reply
  while true; do
    if [[ -n "$default" ]]; then
      printf '  %s?%s %s %s(%s)%s ' \
        "${C_BOLD}" "${C_RESET}" "$prompt" "${C_DIM}" "$default" "${C_RESET}" >&2
      read -e -i "$default" -r reply || die "no input"
    else
      printf '  %s?%s %s ' "${C_BOLD}" "${C_RESET}" "$prompt" >&2
      read -e -r reply || die "no input"
    fi
    reply=${reply:-$default}
    if [[ -z "$reply" ]]; then
      warn "value cannot be empty"
      continue
    fi
    if [[ -n "$validator" ]] && ! "$validator" "$reply"; then
      continue
    fi
    printf '%s\n' "$reply"
    return 0
  done
}

# prompt_bool PROMPT DEFAULT(yes|no)
prompt_bool() {
  local prompt=$1 default=${2:-yes} reply
  if [[ $ASSUME_YES -eq 1 ]]; then
    return 0
  fi
  local hint
  if [[ "$default" == "yes" ]]; then hint="Y/n"; else hint="y/N"; fi
  printf '  %s?%s %s %s(%s)%s ' \
    "${C_BOLD}" "${C_RESET}" "$prompt" "${C_DIM}" "$hint" "${C_RESET}" >&2
  read -r reply
  if [[ "$default" == "yes" ]]; then
    [[ -z "$reply" || "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
  else
    [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
  fi
}

# -------------------------------------------------------------------- helpers

require_cmd() {
  local cmd missing=()
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required command(s): ${missing[*]}"
  fi
}

export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG
}experimental-features = nix-command flakes"
readonly NIX_CMD=(nix --extra-experimental-features "nix-command flakes")

cleanup() {
  if [[ -f "$SECRET_KEY_PATH" ]]; then
    sudo rm -f "$SECRET_KEY_PATH" 2>/dev/null || true
  fi
  if [[ -n "$WORKTREE" && -d "$WORKTREE" ]]; then
    if ! rm -rf "$WORKTREE" 2>/dev/null; then
      sudo rm -rf "$WORKTREE" 2>/dev/null || true
    fi
  fi
}
trap cleanup EXIT

detect_system() {
  case "$(uname -m)" in
    x86_64)        printf 'x86_64-linux\n'  ;;
    aarch64|arm64) printf 'aarch64-linux\n' ;;
    *)             die "Unsupported architecture: $(uname -m)" ;;
  esac
}

detect_ram_gib() {
  # Round up MemTotal (kB) to the next whole GiB.
  local kb
  kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  if [[ "$kb" -eq 0 ]]; then
    printf '8\n'
    return
  fi
  awk -v kb="$kb" 'BEGIN { printf "%d\n", int((kb + 1024*1024 - 1) / (1024*1024)) }'
}

default_swap_size() {
  # RAM-matched swap: enough for hibernation, same units as existing hosts.
  printf '%sG\n' "$(detect_ram_gib)"
}

suggest_nixos_profile() {
  if command -v lspci >/dev/null 2>&1 && lspci 2>/dev/null | grep -qi 'NVIDIA'; then
    printf 'portable-nvidia-gnome\n'
  else
    printf 'portable-gnome\n'
  fi
}

home_profile_supports_display_profile() {
  case "$1" in
    minimal-gui|personal-gnome) return 0 ;;
    *)                          return 1 ;;
  esac
}

# Enumerate profile basenames from the in-repo modules tree.
list_nixos_profiles() {
  find "$REPO_SOURCE/modules/profiles/nixos" -maxdepth 1 -type f -name '*.nix' \
    -exec basename {} .nix \; 2>/dev/null | sort
}
list_home_profiles() {
  find "$REPO_SOURCE/modules/profiles/home" -maxdepth 1 -type f -name '*.nix' \
    -exec basename {} .nix \; 2>/dev/null | sort
}
list_install_layouts() {
  find "$REPO_SOURCE/modules/nixos/install" -maxdepth 1 -type f -name '*.nix' \
    -exec basename {} .nix \; 2>/dev/null | sort
}
list_display_profiles() {
  # Parsed out of modules/home/display-profile.nix (the enum of profile names).
  awk '
    /^  profiles = {/ { in_profiles = 1; next }
    in_profiles && /^  };/ { in_profiles = 0 }
    in_profiles && /^    [A-Za-z0-9_-]+ = {/ {
      name = $1
      print name
    }
  ' "$REPO_SOURCE/modules/home/display-profile.nix" 2>/dev/null
}

host_known() { jq -e --arg host "$1" 'has($host)' "$HOST_DEFS_FILE" >/dev/null; }
host_query() { jq -r --arg host "$1" "$2" "$HOST_DEFS_FILE"; }
host_bool() {
  if [[ "$(host_query "$1" "$2")" == "true" ]]; then printf 'yes\n'; else printf 'no\n'; fi
}
list_known_hosts() { jq -r 'keys[]' "$HOST_DEFS_FILE"; }

# Parse `lsblk` into two parallel arrays: disk paths and pretty labels.
declare -a DISK_PATHS=() DISK_LABELS=()
load_disks() {
  DISK_PATHS=(); DISK_LABELS=()
  while IFS=$'\t' read -r path type rm size model tran; do
    [[ "$type" == "disk" && "$rm" == "0" ]] || continue
    DISK_PATHS+=("$path")
    DISK_LABELS+=("$(printf '%-14s %-8s %s %s' "$path" "$size" "${model:-?}" "${tran:-?}")")
  done < <(lsblk -ndP -o PATH,TYPE,RM,SIZE,MODEL,TRAN 2>/dev/null \
    | sed 's/ *\([A-Z]\{1,\}\)="/\t\1="/g; s/"//g; s/^[A-Z]\{1,\}=//; s/\t[A-Z]\{1,\}=/\t/g')
}

# ----------------------------------------------------------------- validators

validate_swap_size() {
  if [[ "$1" =~ ^[0-9]+[KMGkmg]?$ ]]; then
    return 0
  fi
  warn "swap size must look like '32G', '512M', or '20M' (got '$1')"
  return 1
}

validate_username() {
  if [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    return 0
  fi
  warn "username must start with a letter and contain only [a-z0-9_-]"
  return 1
}

validate_hostname() {
  if [[ "$1" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]; then
    return 0
  fi
  warn "hostname must start with a letter and contain only [A-Za-z0-9-]"
  return 1
}

# --------------------------------------------------------------------- args

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)            HOST=${2:?missing value};            shift 2 ;;
      --disk)            DISK=${2:?missing value};            shift 2 ;;
      --system)          SYSTEM=${2:?missing value};          shift 2 ;;
      --username)        USERNAME=${2:?missing value};        shift 2 ;;
      --nixos)           NIXOS_MODE=yes;                       shift   ;;
      --no-nixos)        NIXOS_MODE=no;                        shift   ;;
      --home)            HOME_MODE=yes;                        shift   ;;
      --no-home)         HOME_MODE=no;                         shift   ;;
      --nixos-profile)   NIXOS_PROFILE=${2:?missing value};   shift 2 ;;
      --home-profile)    HOME_PROFILE=${2:?missing value};    shift 2 ;;
      --display-profile) DISPLAY_PROFILE=${2:?missing value}; shift 2 ;;
      --swap-size)       SWAP_SIZE=${2:?missing value};       shift 2 ;;
      --install-layout)  INSTALL_LAYOUT=${2:?missing value};  shift 2 ;;
      --copy-repo)       COPY_REPO=${2:?missing value};       shift 2 ;;
      --repo-dest)       REPO_DEST=${2:?missing value};       shift 2 ;;
      --dry-run)         DRY_RUN=1;                            shift   ;;
      --no-color)        USE_COLOR=0; apply_colors;           shift   ;;
      -y|--yes)          ASSUME_YES=1;                         shift   ;;
      -h|--help)
        cat <<EOF
Usage:
  nix run .#install -- [options]

Options:
  --host NAME              Known host name or a new ad hoc host name
  --disk PATH              Target disk for NixOS installation
  --system SYSTEM          Override detected system, e.g. x86_64-linux
  --username NAME          Override the host user name
  --nixos / --no-nixos     Enable or disable NixOS installation mode
  --home / --no-home       Enable or disable Home Manager mode
  --nixos-profile NAME     Profile basename under modules/profiles/nixos/
  --home-profile NAME      Profile basename under modules/profiles/home/
  --display-profile NAME   Display profile for ad hoc home configs
  --swap-size SIZE         Swapfile size, e.g. 32G (default: RAM-matched)
  --install-layout NAME    Layout under modules/nixos/install/
  --copy-repo yes|no       Copy the resulting repo into the installed system
  --repo-dest PATH         Destination for copied repo inside the target root
  --dry-run                Show the resolved plan and exit without touching disks
  --no-color               Disable ANSI colors even on a TTY
  -y, --yes                Accept all confirmation prompts
EOF
        exit 0
        ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
}

# --------------------------------------------------------------- resolve plan

resolve_target() {
  if [[ -z "$HOST" ]]; then
    local -a known
    mapfile -t known < <(list_known_hosts)
    if [[ ${#known[@]} -gt 0 ]]; then
      HOST=$(prompt_select "pick host (or type new)" "" "${known[@]}" "<new ad hoc host>")
      if [[ "$HOST" == "<new ad hoc host>" ]]; then
        HOST=$(prompt_text "hostname" "" validate_hostname)
      fi
    else
      HOST=$(prompt_text "hostname" "" validate_hostname)
    fi
  fi

  if host_known "$HOST"; then
    KNOWN_HOST=1
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
    [[ -n "$HOME_MODE"  ]] || HOME_MODE=$(host_bool  "$HOST" '.[$host].home.enable // false')
    # shellcheck disable=SC2016
    [[ -n "$NIXOS_PROFILE"   ]] || NIXOS_PROFILE=$(host_query "$HOST" '.[$host].nixos.profile // empty')
    # shellcheck disable=SC2016
    [[ -n "$HOME_PROFILE"    ]] || HOME_PROFILE=$(host_query "$HOST" '.[$host].home.profile // empty')
    # shellcheck disable=SC2016
    [[ -n "$DISPLAY_PROFILE" ]] || DISPLAY_PROFILE=$(host_query "$HOST" '.[$host].home.displayProfile // empty')
  else
    SYSTEM=${SYSTEM:-$(detect_system)}
    USERNAME=${USERNAME:-$DEFAULT_USERNAME}
    PLATFORM=${PLATFORM:-"ad-hoc"}
    VISIBILITY=${VISIBILITY:-"private"}
    NIXOS_MODE=${NIXOS_MODE:-}
    HOME_MODE=${HOME_MODE:-}
  fi

  USERNAME=${USERNAME:-$DEFAULT_USERNAME}
}

resolve_modes() {
  if [[ -z "$NIXOS_MODE" ]]; then
    NIXOS_MODE=$(prompt_select "install nixos on this machine?" yes yes no)
  fi
  if [[ -z "$HOME_MODE" ]]; then
    HOME_MODE=$(prompt_select "activate home-manager?" yes yes no)
  fi
  [[ "$NIXOS_MODE" == "yes" || "$HOME_MODE" == "yes" ]] \
    || die "Nothing to do: enable at least --nixos or --home."
}

resolve_ad_hoc_profiles() {
  [[ $KNOWN_HOST -eq 0 ]] || return 0

  if [[ "$NIXOS_MODE" == "yes" && -z "$NIXOS_PROFILE" ]]; then
    local -a profiles
    mapfile -t profiles < <(list_nixos_profiles)
    [[ ${#profiles[@]} -gt 0 ]] || die "no nixos profiles under modules/profiles/nixos/"
    NIXOS_PROFILE=$(prompt_select "pick nixos profile" "$(suggest_nixos_profile)" "${profiles[@]}")
  fi

  if [[ "$HOME_MODE" == "yes" && -z "$HOME_PROFILE" ]]; then
    local -a profiles
    mapfile -t profiles < <(list_home_profiles)
    [[ ${#profiles[@]} -gt 0 ]] || die "no home profiles under modules/profiles/home/"
    HOME_PROFILE=$(prompt_select "pick home profile" "personal-gnome" "${profiles[@]}")
  fi

  if [[ "$HOME_MODE" == "yes" && -n "$DISPLAY_PROFILE" ]] \
     && ! home_profile_supports_display_profile "$HOME_PROFILE"; then
    warn "home profile '${HOME_PROFILE}' does not use display profiles — ignoring"
    DISPLAY_PROFILE=""
  fi

  if [[ "$HOME_MODE" == "yes" && -z "$DISPLAY_PROFILE" ]] \
     && home_profile_supports_display_profile "$HOME_PROFILE"; then
    local -a profiles
    mapfile -t profiles < <(list_display_profiles)
    [[ ${#profiles[@]} -gt 0 ]] || profiles=(none gnome-default)
    DISPLAY_PROFILE=$(prompt_select "pick display profile" "gnome-default" "${profiles[@]}")
  fi

  if [[ "$NIXOS_MODE" == "yes" && -z "$INSTALL_LAYOUT" ]]; then
    local -a layouts
    mapfile -t layouts < <(list_install_layouts)
    [[ ${#layouts[@]} -gt 0 ]] || die "no install layouts under modules/nixos/install/"
    INSTALL_LAYOUT=$(prompt_select "pick install layout" "luks-btrfs" "${layouts[@]}")
  fi

  if [[ "$NIXOS_MODE" == "yes" && -z "$SWAP_SIZE" ]]; then
    section "swap"
    local ram_gib
    ram_gib=$(detect_ram_gib)
    printf '  %sram %s GiB · default matches ram for hibernation%s\n' \
      "${C_DIM}" "$ram_gib" "${C_RESET}"
    SWAP_SIZE=$(prompt_text "size" "$(default_swap_size)" validate_swap_size)
  fi
}

resolve_disk() {
  [[ "$NIXOS_MODE" == "yes" ]] || return 0

  load_disks
  if [[ ${#DISK_PATHS[@]} -eq 0 ]]; then
    die "no non-removable disks detected"
  fi

  if [[ -z "$DISK" ]]; then
    local default_label=""
    if [[ ${#DISK_PATHS[@]} -eq 1 ]]; then
      default_label=${DISK_LABELS[0]}
    fi
    local chosen
    chosen=$(prompt_select "pick target disk" "$default_label" "${DISK_LABELS[@]}")
    local i
    for i in "${!DISK_LABELS[@]}"; do
      if [[ "${DISK_LABELS[i]}" == "$chosen" ]]; then
        DISK=${DISK_PATHS[i]}
        break
      fi
    done
  fi

  [[ -b "$DISK" ]] || die "Not a block device: $DISK"
  [[ "$(lsblk -ndo TYPE "$DISK")" == "disk" ]] || die "Not a whole disk: $DISK"
}

# --------------------------------------------------------------- recap + exec

recap() {
  section "summary"
  kv "host"       "$HOST"
  kv "system"     "$SYSTEM"
  kv "user"       "$USERNAME"
  kv "platform"   "$PLATFORM"
  kv "visibility" "$VISIBILITY"
  kv "nixos"      "${NIXOS_PROFILE:+$NIXOS_PROFILE}"
  kv "home"       "${HOME_PROFILE:+$HOME_PROFILE}"
  [[ -n "$DISPLAY_PROFILE" ]] && kv "display" "$DISPLAY_PROFILE"
  if [[ "$NIXOS_MODE" == "yes" ]]; then
    kv "layout" "$INSTALL_LAYOUT"
    kv "disk"   "$DISK"
    kv "swap"   "$SWAP_SIZE"
  fi
  [[ $DRY_RUN -eq 1 ]] && kv "mode" "${C_YELLOW}dry run${C_RESET}"
}

prepare_worktree() {
  WORKTREE=$(mktemp -d "${TMPDIR:-/tmp}/nixos-installer.XXXXXX")
  run_with_spinner "preparing worktree at ${WORKTREE}" \
    rsync -a --delete --chmod=Du+rwx,Dgo+rx,Fu+rw,Fgo+r "$REPO_SOURCE"/ "$WORKTREE"/
}

write_worktree_host_defs() {
  local base_defs="$WORKTREE/machines/defs-known.nix"
  local defs_file="$WORKTREE/machines/defs.nix"

  mv "$defs_file" "$base_defs"

  cat >"$defs_file" <<EOF
{lib, const, ...}:
  let
    defs = import ./defs-known.nix {inherit lib const;};
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
      }$(
        if [[ $KNOWN_HOST -eq 0 && "$NIXOS_MODE" == "yes" ]]; then
          printf ' // {\n'
          printf '        canTouchEfiVariables = false;\n'
          printf '        efiInstallAsRemovable = true;\n'
          printf '      }'
        fi
      );
    };
  }
EOF
}

prepare_target_config() {
  write_worktree_host_defs
  if [[ "$NIXOS_MODE" == "yes" ]]; then
    mkdir -p "$WORKTREE/machines/$HOST"
  fi
  ok "host definitions written"
}

write_secret_key() {
  section "luks passphrase"
  local luks_pw
  while true; do
    read -r -s -p "  enter: " luks_pw
    printf '\n'
    [[ -n "${luks_pw:-}" ]] || { warn "passphrase cannot be empty"; continue; }
    local confirm
    read -r -s -p "  confirm: " confirm
    printf '\n'
    if [[ "$luks_pw" == "$confirm" ]]; then
      break
    fi
    warn "passphrases did not match"
  done
  printf '%s' "$luks_pw" | sudo tee "$SECRET_KEY_PATH" >/dev/null
  sudo chmod 600 "$SECRET_KEY_PATH"
  ok "staged at ${SECRET_KEY_PATH}"
}

run_nixos_install() {
  [[ "$NIXOS_MODE" == "yes" ]] || return 0
  [[ $DRY_RUN -eq 0 ]] || { info "Dry run: skipping disko + nixos-install"; return 0; }

  section "destructive"
  warn "this will DESTROY all data on ${C_BOLD}${DISK}${C_RESET}"
  if ! prompt_bool "proceed with disko + nixos-install on ${DISK}?" no; then
    die "aborted."
  fi

  local -a disko_args=(--mode "destroy,format,mount" --flake ".#${HOST}")

  if [[ "$INSTALL_LAYOUT" == luks-* ]]; then
    write_secret_key
  fi

  section "disko"
  (
    cd "$WORKTREE"
    if [[ $ASSUME_YES -eq 1 ]]; then
      disko_args=(--yes-wipe-all-disks "${disko_args[@]}")
    fi
    sudo disko "${disko_args[@]}"
  )
  ok "disko finished"

  section "hardware config"
  sudo nixos-generate-config --no-filesystems --root /mnt
  sudo install -D -m 0644 /mnt/etc/nixos/hardware-configuration.nix \
    "$WORKTREE/machines/$HOST/hardware-configuration.nix"
  ok "hardware-configuration.nix staged"

  section "nixos-install"
  (cd "$WORKTREE" && sudo nixos-install --root /mnt --flake ".#${HOST}")
  ok "nixos-install finished"
}

copy_repo_to_target() {
  [[ "$NIXOS_MODE" == "yes" ]] || return 0
  [[ $DRY_RUN -eq 0 ]] || { info "Dry run: skipping repo copy"; return 0; }

  if [[ -z "$REPO_DEST" ]]; then
    REPO_DEST="/mnt/home/${USERNAME}/src/public/nixos-config"
  fi

  if [[ -z "$COPY_REPO" ]]; then
    if prompt_bool "copy repo to ${REPO_DEST}?" yes; then
      COPY_REPO=yes
    else
      COPY_REPO=no
    fi
  fi

  if [[ "$COPY_REPO" == "yes" ]]; then
    sudo mkdir -p "$(dirname "$REPO_DEST")"
    run_with_spinner "copying repo → ${REPO_DEST}" \
      sudo rsync -a --delete "$WORKTREE"/ "${REPO_DEST}/"
  fi
}

run_home_install() {
  [[ "$HOME_MODE" == "yes" ]] || return 0
  if [[ "$NIXOS_MODE" == "yes" ]]; then
    return 0
  fi
  [[ $DRY_RUN -eq 0 ]] || { info "Dry run: skipping home-manager switch"; return 0; }

  section "home-manager"
  info "switching ${USERNAME}@${HOST}"
  "${NIX_CMD[@]}" run nixpkgs#home-manager -- switch --flake "${WORKTREE}#${USERNAME}@${HOST}"
  ok "home-manager switch finished"
}

# --------------------------------------------------------------------- main

banner() {
  printf '\n%s%s nixos installer%s\n' \
    "${C_BOLD}" "${C_MAGENTA}" "${C_RESET}"
}

main() {
  require_cmd jq rsync lsblk awk sed perl nix
  parse_args "$@"
  apply_colors  # re-apply after --no-color may have flipped USE_COLOR

  # banner
  resolve_target
  resolve_modes
  resolve_ad_hoc_profiles
  resolve_disk
  recap

  if ! prompt_bool "proceed?" yes; then
    die "aborted."
  fi

  prepare_worktree
  prepare_target_config

  if [[ $DRY_RUN -eq 1 ]]; then
    section "dry run · defs.nix"
    sed 's/^/  /' "$WORKTREE/machines/defs.nix"
    printf '\n'
    ok "dry run complete — no disks touched"
    return 0
  fi

  run_nixos_install
  copy_repo_to_target
  run_home_install

  section "done"
  ok "finished install for ${C_BOLD}${HOST}${C_RESET}"
}

main "$@"
