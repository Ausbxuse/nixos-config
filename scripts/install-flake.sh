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
FULL_NAME=""
EMAIL=""
NIXOS_MODE=""       # yes|no
HOME_MODE=""        # yes|no
NIXOS_PROFILE=""
HOME_PROFILE=""
NIXOS_FLAG_SET=0
HOME_FLAG_SET=0

DISPLAY_PROFILE=""
SWAP_SIZE=""
INSTALL_LAYOUT=""
PLATFORM=""
VISIBILITY=""
COPY_REPO=""        # yes|no
REPO_DEST=""
KNOWN_HOST=0
DRY_RUN=0
PORTABLE=0
WORKTREE=""
INSTALL_REPO_SOURCE=""

@source_lib@

script_banner() { banner "nixos installer" "partition, format, and install NixOS"; }

bool_word() {
  if [[ "$1" == "yes" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

nix_escape_string() {
  printf '%s' "$1" | sed 's/[&|]/\\&/g; s/\\/\\\\/g; s/"/\\"/g'
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

resolve_install_repo_source() {
  local cwd=${PWD:-}
  local git_root=""

  if [[ -n "$cwd" ]] && git_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null); then
    if [[ -f "$git_root/flake.nix" ]] && [[ -d "$git_root/.git" ]]; then
      INSTALL_REPO_SOURCE=$git_root
      return 0
    fi
  fi

  INSTALL_REPO_SOURCE=$REPO_SOURCE
}

default_swap_size() {
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
  awk '
    /^  profiles = {/ { in_profiles = 1; next }
    in_profiles && /^  };/ { in_profiles = 0 }
    in_profiles && /^    [A-Za-z0-9_-]+ = {/ { print $1 }
  ' "$REPO_SOURCE/modules/home/display-profile.nix" 2>/dev/null
}

host_known() {
  jq -e --arg host "$1" 'has($host)' "$HOST_DEFS_FILE" >/dev/null
}

host_query() {
  jq -r --arg host "$1" "$2" "$HOST_DEFS_FILE"
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

# Parse `lsblk` into two parallel arrays: disk paths and pretty labels.
declare -a DISK_PATHS=()
declare -a DISK_LABELS=()

load_disks() {
  DISK_PATHS=()
  DISK_LABELS=()

  while IFS=$'\t' read -r path type rm size model tran; do
    if [[ "$type" != "disk" || "$rm" != "0" ]]; then
      continue
    fi
    DISK_PATHS+=("$path")
    DISK_LABELS+=("$(printf '%-14s %-8s %s %s' "$path" "$size" "${model:-?}" "${tran:-?}")")
  done < <(
    lsblk -ndP -o PATH,TYPE,RM,SIZE,MODEL,TRAN 2>/dev/null \
      | sed 's/ *\([A-Z]\{1,\}\)="/\t\1="/g; s/"//g; s/^[A-Z]\{1,\}=//; s/\t[A-Z]\{1,\}=/\t/g'
  )
}

# --------------------------------------------------------------------- args

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)            HOST=${2:?missing value};            shift 2 ;;
      --disk)            DISK=${2:?missing value};            shift 2 ;;
      --system)          SYSTEM=${2:?missing value};          shift 2 ;;
      --username)        USERNAME=${2:?missing value};        shift 2 ;;
      --name)            FULL_NAME=${2:?missing value};       shift 2 ;;
      --email)           EMAIL=${2:?missing value};           shift 2 ;;
      --nixos)           NIXOS_MODE=yes; NIXOS_FLAG_SET=1;    shift ;;
      --home)            HOME_MODE=yes;  HOME_FLAG_SET=1;     shift ;;

      --nixos-profile)   NIXOS_PROFILE=${2:?missing value};   shift 2 ;;
      --home-profile)    HOME_PROFILE=${2:?missing value};    shift 2 ;;
      --display-profile) DISPLAY_PROFILE=${2:?missing value}; shift 2 ;;
      --swap-size)       SWAP_SIZE=${2:?missing value};       shift 2 ;;
      --install-layout)  INSTALL_LAYOUT=${2:?missing value};  shift 2 ;;
      --copy-repo)       COPY_REPO=${2:?missing value};       shift 2 ;;
      --repo-dest)       REPO_DEST=${2:?missing value};       shift 2 ;;
      --portable)        PORTABLE=1;                            shift ;;
      --dry-run)         DRY_RUN=1;                           shift ;;
      --no-color)        USE_COLOR=0; apply_colors;          shift ;;
      -y|--yes)          ASSUME_YES=1;                        shift ;;
      -h|--help)
        cat <<EOF
Usage:
  nix run .#install -- [options]

Options:
  --host NAME              Known host name or a new custom host name
  --disk PATH              Target disk for NixOS installation
  --system SYSTEM          Override detected system, e.g. x86_64-linux
  --username NAME          Override the host user name
  --name NAME              Override the Git user name written into globals.nix
  --email EMAIL            Override the Git user email written into globals.nix
  --nixos / --no-nixos     Enable or disable NixOS installation mode
  --home / --no-home       Enable or disable Home Manager mode
  --nixos-profile NAME     Profile basename under modules/profiles/nixos/
  --home-profile NAME      Profile basename under modules/profiles/home/
  --display-profile NAME   Display profile for custom home configs
  --swap-size SIZE         Swapfile size, e.g. 32G (default: RAM-matched)
  --install-layout NAME    Layout under modules/nixos/install/
  --copy-repo yes|no       Copy the resulting repo into the installed system
  --repo-dest PATH         Destination for copied repo inside the target root
  --portable               Portable mode for non-root, non-NixOS hosts using
                           nix-portable (implies --home)
  --dry-run                Show the resolved plan and exit without touching disks
  --no-color               Disable ANSI colors even on a TTY
  -y, --yes                Accept all confirmation prompts
EOF
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done

  if [[ -n "$HOST" ]]; then
    validate_hostname "$HOST" || die "invalid --host: $HOST"
  fi

  if [[ -n "$USERNAME" ]]; then
    validate_username "$USERNAME" || die "invalid --username: $USERNAME"
  fi

  if [[ -n "$EMAIL" ]]; then
    validate_email "$EMAIL" || die "invalid --email: $EMAIL"
  fi

  if [[ -n "$SWAP_SIZE" ]]; then
    validate_swap_size "$SWAP_SIZE" || die "invalid --swap-size: $SWAP_SIZE"
  fi

  if [[ -n "$COPY_REPO" && "$COPY_REPO" != "yes" && "$COPY_REPO" != "no" ]]; then
    die "--copy-repo must be yes or no"
  fi
}

# --------------------------------------------------------------- resolve plan
# shellcheck disable=SC2016
resolve_target() {
  if [[ -z "$HOST" ]]; then
    local -a known
    mapfile -t known < <(list_known_hosts)

    if [[ ${#known[@]} -gt 0 ]]; then
      HOST=$(prompt_select "pick host (or type new)" "" "${known[@]}" "<new custom host>")
      if [[ "$HOST" == "<new custom host>" ]]; then
        HOST=$(prompt_text "hostname" "" validate_hostname)
      fi
    else
      HOST=$(prompt_text "hostname" "" validate_hostname)
    fi
  fi

  if host_known "$HOST"; then
    KNOWN_HOST=1

    SYSTEM=${SYSTEM:-$(host_query "$HOST" '.[$host].system // empty')}
    USERNAME=${USERNAME:-$(host_query "$HOST" '.[$host].username // empty')}
    PLATFORM=${PLATFORM:-$(host_query "$HOST" '.[$host].platform // "custom"')}
    VISIBILITY=${VISIBILITY:-$(host_query "$HOST" '.[$host].visibility // "private"')}
    INSTALL_LAYOUT=${INSTALL_LAYOUT:-$(host_query "$HOST" '.[$host].install.layout // empty')}
    DISK=${DISK:-$(host_query "$HOST" '.[$host].install.disk // empty')}
    SWAP_SIZE=${SWAP_SIZE:-$(host_query "$HOST" '.[$host].install.swapSize // empty')}

    if [[ -z "$NIXOS_MODE" ]]; then
      NIXOS_MODE=$(host_bool "$HOST" '.[$host].nixos.enable // false')
    fi
    if [[ -z "$HOME_MODE" ]]; then
      HOME_MODE=$(host_bool "$HOST" '.[$host].home.enable // false')
    fi
    if [[ -z "$NIXOS_PROFILE" ]]; then
      NIXOS_PROFILE=$(host_query "$HOST" '.[$host].nixos.profile // empty')
    fi
    if [[ -z "$HOME_PROFILE" ]]; then
      HOME_PROFILE=$(host_query "$HOST" '.[$host].home.profile // empty')
    fi
    if [[ -z "$DISPLAY_PROFILE" ]]; then
      DISPLAY_PROFILE=$(host_query "$HOST" '.[$host].home.displayProfile // empty')
    fi
  else
    SYSTEM=${SYSTEM:-$(detect_system)}
    if [[ -z "$USERNAME" ]]; then
      USERNAME=$(prompt_text "username" "$DEFAULT_USERNAME" validate_username)
    fi
    PLATFORM=${PLATFORM:-custom}
    VISIBILITY=${VISIBILITY:-private}
  fi

  USERNAME=${USERNAME:-$DEFAULT_USERNAME}
}

resolve_modes() {
  if [[ $NIXOS_FLAG_SET -eq 0 && $HOME_FLAG_SET -eq 0 ]]; then
    NIXOS_MODE=$(prompt_select "install nixos on this machine?" no yes no)
    HOME_MODE=$(prompt_select "activate home-manager?" no yes no)
  fi

  if [[ "$NIXOS_MODE" != "yes" && "$HOME_MODE" != "yes" ]]; then
    die "Nothing to do: enable at least --nixos or --home."
  fi
}

resolve_identity() {
  if [[ -z "$FULL_NAME" ]]; then
    FULL_NAME=$(prompt_text "git name")
  fi

  if [[ -z "$EMAIL" ]]; then
    EMAIL=$(prompt_text "git email" "" validate_email)
  fi
}

resolve_custom_profiles() {
  if [[ $KNOWN_HOST -ne 0 ]]; then
    return 0
  fi

  if [[ "$NIXOS_MODE" == "yes" && -z "$NIXOS_PROFILE" ]]; then
    local -a profiles
    mapfile -t profiles < <(list_nixos_profiles)
    if [[ ${#profiles[@]} -eq 0 ]]; then
      die "no nixos profiles under modules/profiles/nixos/"
    fi
    NIXOS_PROFILE=$(prompt_select "pick nixos profile" "$(suggest_nixos_profile)" "${profiles[@]}")
  fi

  if [[ "$HOME_MODE" == "yes" && -z "$HOME_PROFILE" ]]; then
    local -a profiles
    mapfile -t profiles < <(list_home_profiles)
    if [[ ${#profiles[@]} -eq 0 ]]; then
      die "no home profiles under modules/profiles/home/"
    fi
    HOME_PROFILE=$(prompt_select "pick home profile" "personal-gnome" "${profiles[@]}")
  fi

  if [[ "$HOME_MODE" == "yes" && -n "$DISPLAY_PROFILE" ]]; then
    if ! home_profile_supports_display_profile "$HOME_PROFILE"; then
      warn "home profile '${HOME_PROFILE}' does not use display profiles — ignoring"
      DISPLAY_PROFILE=""
    fi
  fi

  if [[ "$HOME_MODE" == "yes" && -z "$DISPLAY_PROFILE" ]]; then
    if home_profile_supports_display_profile "$HOME_PROFILE"; then
      local -a profiles
      mapfile -t profiles < <(list_display_profiles)
      if [[ ${#profiles[@]} -eq 0 ]]; then
        profiles=(none gnome-default)
      fi
      DISPLAY_PROFILE=$(prompt_select "pick display profile" "gnome-default" "${profiles[@]}")
    fi
  fi

  if [[ "$NIXOS_MODE" == "yes" && -z "$INSTALL_LAYOUT" ]]; then
    local -a layouts
    mapfile -t layouts < <(list_install_layouts)
    if [[ ${#layouts[@]} -eq 0 ]]; then
      die "no install layouts under modules/nixos/install/"
    fi
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
  if [[ "$NIXOS_MODE" != "yes" ]]; then
    return 0
  fi

  load_disks
  if [[ ${#DISK_PATHS[@]} -eq 0 ]]; then
    die "no non-removable disks detected"
  fi

  if [[ -z "$DISK" ]]; then
    local default_label=""
    local chosen=""
    local i

    if [[ ${#DISK_PATHS[@]} -eq 1 ]]; then
      default_label=${DISK_LABELS[0]}
    fi

    chosen=$(prompt_select "pick target disk" "$default_label" "${DISK_LABELS[@]}")

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
  kv "git name"   "$FULL_NAME"
  kv "git email"  "$EMAIL"
  kv "platform"   "$PLATFORM"
  kv "visibility" "$VISIBILITY"
  kv "nixos"      "${NIXOS_PROFILE:+$NIXOS_PROFILE}"
  kv "home"       "${HOME_PROFILE:+$HOME_PROFILE}"

  if [[ -n "$DISPLAY_PROFILE" ]]; then
    kv "display" "$DISPLAY_PROFILE"
  fi

  if [[ "$NIXOS_MODE" == "yes" ]]; then
    kv "layout" "$INSTALL_LAYOUT"
    kv "disk"   "$DISK"
    kv "swap"   "$SWAP_SIZE"
  fi

  if [[ $PORTABLE -eq 1 ]]; then
    kv "mode" "${C_CYAN}portable${C_RESET}"
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    kv "mode" "${C_YELLOW}dry run${C_RESET}"
  fi
}

prepare_worktree() {
  WORKTREE=$(mktemp -d "${TMPDIR:-/tmp}/nixos-installer.XXXXXX")
  resolve_install_repo_source
  run_with_spinner "preparing worktree at ${WORKTREE}" \
    rsync -a --delete --chmod=Du+rwx,Dgo+rx,Fu+rw,Fgo+r "${INSTALL_REPO_SOURCE}/" "$WORKTREE"/
}

write_worktree_host_defs() {
  local defs_file="$WORKTREE/machines/defs.nix"
  local home_enable
  local nixos_enable

  home_enable=$(bool_word "$HOME_MODE")
  nixos_enable=$(bool_word "$NIXOS_MODE")

  # Build a self-contained defs.nix: read the original, strip the outer
  # `{lib, const, ...}: {` header and closing `}`, then remove any existing
  # block for HOST and append a fresh one.
  #
  # This avoids a separate defs-known.nix file that would break when
  # enroll rsyncs the repo (it excludes defs.nix but not defs-known.nix).
  local body
  body=$(sed '1,/^}: {$/d; $d' "$defs_file")
  # Remove existing HOST block (top-level `  HOST = {` … `  };`) to avoid
  # duplicate attribute errors.  Uses awk to skip lines between the opening
  # and closing markers.
  body=$(printf '%s\n' "$body" | awk -v host="  ${HOST} = {" '
    $0 == host { skip=1; next }
    skip && /^  };/ { skip=0; next }
    !skip
  ')

  cat >"$defs_file" <<EOF
{lib, const, ...}: {
${body}
  ${HOST} = {
    system = "${SYSTEM}";
    username = "${USERNAME}";
    platform = "${PLATFORM}";
    visibility = "${VISIBILITY}";

    home = {
      enable = ${home_enable};$(
        if [[ -n "$HOME_PROFILE" ]]; then
          printf '\n      profile = "%s";' "$HOME_PROFILE"
        fi
        if [[ -n "$DISPLAY_PROFILE" ]]; then
          printf '\n      displayProfile = "%s";' "$DISPLAY_PROFILE"
        fi
      )
    };

    nixos = {
      enable = ${nixos_enable};$(
        if [[ -n "$NIXOS_PROFILE" ]]; then
          printf '\n      profile = "%s";' "$NIXOS_PROFILE"
        fi
      )
    };

    install = {
      layout = "${INSTALL_LAYOUT}";
      disk = "${DISK}";
      swapSize = "${SWAP_SIZE}";$(
        if [[ $KNOWN_HOST -eq 0 && "$NIXOS_MODE" == "yes" ]]; then
          printf '\n      canTouchEfiVariables = false;'
          printf '\n      efiInstallAsRemovable = true;'
        fi
      )
    };
  };
}
EOF
}

prepare_target_config() {
  local escaped_username
  local escaped_name
  local escaped_email

  write_worktree_host_defs

  if [[ "$NIXOS_MODE" == "yes" ]]; then
    mkdir -p "$WORKTREE/machines/$HOST"
  fi

  # Update globals.nix in the worktree so the copied repo reflects the
  # selected install identity even before private globals are available.
  escaped_username=$(nix_escape_string "$USERNAME")
  escaped_name=$(nix_escape_string "$FULL_NAME")
  escaped_email=$(nix_escape_string "$EMAIL")

  sed -i "s|^  username = .*|  username = \"$escaped_username\";|" "$WORKTREE/globals.nix"
  if grep -q '^  name = ' "$WORKTREE/globals.nix"; then
    sed -i "s|^  name = .*|  name = \"$escaped_name\";|" "$WORKTREE/globals.nix"
  else
    perl -0pi -e 's/\{\n/\{\n  name = "'"$escaped_name"'";\n/' "$WORKTREE/globals.nix"
  fi
  if grep -q '^  email = ' "$WORKTREE/globals.nix"; then
    sed -i "s|^  email = .*|  email = \"$escaped_email\";|" "$WORKTREE/globals.nix"
  else
    perl -0pi -e 's/\{\n/\{\n  email = "'"$escaped_email"'";\n/' "$WORKTREE/globals.nix"
  fi

  ok "host definitions written"
}

write_secret_key() {
  section "luks passphrase"
  require_tty

  local luks_pw=""
  local confirm=""

  while true; do
    read -r -s -p "  enter: " luks_pw </dev/tty
    printf '\n'
    if [[ -z "$luks_pw" ]]; then
      warn "passphrase cannot be empty"
      continue
    fi

    read -r -s -p "  confirm: " confirm </dev/tty
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
  if [[ "$NIXOS_MODE" != "yes" ]]; then
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    info "Dry run: skipping disko + nixos-install"
    return 0
  fi

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

    sudo --non-interactive true 2>/dev/null || true
    exec </dev/tty >/dev/tty 2>&1
    sudo disko "${disko_args[@]}"
  )
  ok "disko finished"

  section "hardware config"
  sudo nixos-generate-config --no-filesystems --root /mnt
  sudo install -D -m 0644 /mnt/etc/nixos/hardware-configuration.nix \
    "$WORKTREE/machines/$HOST/hardware-configuration.nix"
  ok "hardware-configuration.nix staged"

  section "nixos-install"
  local install_log=""
  install_log=$(mktemp)

  if ! (
    cd "$WORKTREE"
    sudo nixos-install --root /mnt --flake ".#${HOST}" 2>&1 | tee "$install_log"
  ); then
    rm -f "$install_log"
    die "nixos-install failed"
  fi

  if grep -Eq '^ERROR:' "$install_log"; then
    err "nixos-install reported errors despite exiting successfully:"
    grep -E '^ERROR:' "$install_log" | sed 's/^/    /' >&2
    rm -f "$install_log"
    die "nixos-install reported an installation error"
  fi

  rm -f "$install_log"
  ok "nixos-install finished"
}

copy_repo_to_target() {
  if [[ "$NIXOS_MODE" != "yes" ]]; then
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    info "Dry run: skipping repo copy"
    return 0
  fi

  if [[ -z "$REPO_DEST" ]]; then
    REPO_DEST="/mnt/home/${USERNAME}/src/public/nix-config"
  fi

  if [[ -z "$COPY_REPO" ]]; then
    if prompt_bool "copy repo to ${REPO_DEST}?" yes; then
      COPY_REPO=yes
    else
      COPY_REPO=no
    fi
  fi

  if [[ "$COPY_REPO" == "yes" ]]; then
    sudo mkdir -p "$REPO_DEST"
    run_with_spinner "copying repo → ${REPO_DEST}" \
      sudo rsync -a --delete "$WORKTREE"/ "${REPO_DEST}/"

    # Fix ownership inside the target system, where the installed user exists.
    sudo nixos-enter --root /mnt -c "chown -R ${USERNAME}:users /home/${USERNAME}/src"
  fi
}

run_home_install() {
  if [[ "$HOME_MODE" != "yes" ]]; then
    return 0
  fi

  if [[ "$NIXOS_MODE" == "yes" ]]; then
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    info "Dry run: skipping home-manager switch"
    return 0
  fi

  section "home-manager"
  info "switching ${USERNAME}@${HOST}"
  "${NIX_CMD[@]}" run nixpkgs#home-manager -- switch --flake "${WORKTREE}#${USERNAME}@${HOST}"
  ok "home-manager switch finished"
}

# --------------------------------------------------------- portable helpers

setup_portable_env() {
  if [[ $PORTABLE -eq 0 ]]; then
    return 0
  fi

  section "portable shell"

  local np_runtime="${NP_RUNTIME:-bwrap}"
  local nix_portable_bin
  nix_portable_bin=$(command -v nix-portable 2>/dev/null || echo "$HOME/.local/bin/nix-portable")

  cat >"$HOME/hm-env" <<WRAPPER
#!/usr/bin/env bash
NP_RUNTIME=${np_runtime} exec "${nix_portable_bin}" nix run nixpkgs#zsh
WRAPPER
  chmod +x "$HOME/hm-env"
  ok "created ~/hm-env"
  info "run ${C_BOLD}~/hm-env${C_RESET} to enter your managed shell"
}

# --------------------------------------------------------------------- main

main() {
  parse_args "$@"

  if [[ $PORTABLE -eq 1 ]]; then
    NIXOS_MODE=no
    HOME_MODE=${HOME_MODE:-yes}
    require_cmd jq rsync awk sed nix
  else
    require_cmd jq rsync lsblk awk sed nix
  fi
  apply_colors

  script_banner
  resolve_target
  resolve_modes
  resolve_identity
  resolve_custom_profiles
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
  setup_portable_env

  section "done"
  ok "finished install for ${C_BOLD}${HOST}${C_RESET}"
}

main "$@"
