#!/usr/bin/env bash
set -euo pipefail

# ─── Constants ──────────────────────────────────────────────
NIX_INSTALL_URL="https://nixos.org/nix/install"
GIT_CONFIG_REPO="https://github.com/ausbxuse/nixos-config"
GIT_BRANCH="master"
FLAKE_NAME="spacy"
REPO_DIR="$HOME/src/public/nixos-config"
NIX_CONF="$HOME/.config/nix/nix.conf"

# ─── Helpers ───────────────────────────────────────────────
info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error()   { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }
need_sudo() {
  if ! sudo -v; then
    error "This script requires sudo privileges."
  fi
}

# ─── Install Nix if missing ─────────────────────────────────
install_nix() {
  if ! command -v nix >/dev/null 2>&1; then
    info "Installing Nix..."
    sh <(curl --proto '=https' --tlsv1.2 -L "$NIX_INSTALL_URL") --daemon
    exec "$SHELL" "$0"  # restart script in new shell env
  else
    info "Nix already installed."
  fi
}

# ─── Clone configuration repo ───────────────────────────────
clone_repo() {
  if [ ! -d "$REPO_DIR" ]; then
    info "Cloning git repository..."
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone "$GIT_CONFIG_REPO" --depth 1 -b "$GIT_BRANCH" "$REPO_DIR"
  else
    info "Config repo already exists, skipping clone."
  fi
}

# ─── Patch constants.nix ────────────────────────────────────
patch_constants() {
  info "Patching constants.nix with system values..."
  sed -i \
    -e "s/username = \"[^\"]*\";/username = \"$(whoami)\";/g" \
    -e "s|user-homedir = \"/home/[^\"]*\";|user-homedir = \"$(echo "$HOME")\";|g" \
    -e "s/hostname = \"[^\"]*\";/hostname = \"$(hostname)\";/g" \
    "$REPO_DIR/constants.nix"
}

# ─── Enable flakes in nix.conf ──────────────────────────────
enable_flakes() {
  mkdir -p "$(dirname "$NIX_CONF")"
  if ! grep -q "extra-experimental-features" "$NIX_CONF" 2>/dev/null; then
    info "Enabling flakes and nix-command..."
    echo 'extra-experimental-features = nix-command flakes' >>"$NIX_CONF"
  fi
}

# ─── Switch Home Manager ────────────────────────────────────
hm_switch() {
  info "Running home-manager switch..."
  cd "$REPO_DIR"
  nix run nixpkgs#home-manager -- switch --flake ".#$FLAKE_NAME"
}

# ─── Setup Zsh as default shell ─────────────────────────────
setup_zsh() {
  local zsh_path
  zsh_path="$(command -v zsh || true)"
  if [ -z "$zsh_path" ]; then
    warn "Zsh not found. Skipping shell setup."
    return
  fi

  if ! grep -q "$zsh_path" /etc/shells; then
    info "Authorizing Zsh in /etc/shells..."
    echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
  fi

  if [ "$SHELL" != "$zsh_path" ]; then
    info "Changing default shell to Zsh..."
    chsh -s "$zsh_path"
  else
    info "Zsh already the default shell."
  fi
}

# ─── Optional: Interception-tools setup ─────────────────────
setup_interception_tools() {
  read -rp "👉 Do you want to set CapsLock = Ctrl when held, Esc when tapped? [y/N] " ans
  case "$ans" in
    [yY]*)
      need_sudo
      info "Installing interception-tools..."
      sudo apt update
      sudo apt install -y interception-tools interception-tools-plugins

      info "Writing dual-function-keys config..."
      sudo tee /etc/dual-function-keys.yaml >/dev/null <<'EOF'
MAPPINGS:
  - KEY: KEY_CAPSLOCK
    TAP: KEY_ESC
    HOLD: KEY_LEFTCTRL
EOF

      sudo mkdir -p /etc/interception/udevmon.d
      sudo tee /etc/interception/udevmon.d/dual-function-keys.yaml >/dev/null <<'EOF'
- JOB: "intercept -g $DEVNODE \
       | dual-function-keys -c /etc/dual-function-keys.yaml \
       | uinput -d $DEVNODE"
  DEVICE:
    EVENTS:
      EV_KEY: [KEY_CAPSLOCK]
EOF

      info "Enabling udevmon service..."
      sudo systemctl enable udevmon
      sudo systemctl restart udevmon

      info "Adding user to input/uinput groups..."
      sudo groupadd -f input
      sudo usermod -aG input "$USER"
      sudo usermod -aG uinput "$USER"

      warn "Please reboot or log out/in for group changes to take effect."
      ;;
    *)
      info "Skipping interception-tools setup."
      ;;
  esac
}

# ─── Main ──────────────────────────────────────────────────
main() {
  need_sudo
  install_nix
  clone_repo
  patch_constants
  enable_flakes
  hm_switch
  setup_zsh
  setup_interception_tools
  info "🎉 Installation and setup complete!"
}

main "$@"
