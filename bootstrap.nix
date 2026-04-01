{
  pkgs,
  home-manager,
  system,
}: flakeName:
pkgs.writeShellScriptBin "bootstrap" ''
  set -euo pipefail

  info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
  warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }

  REPO_DIR="$HOME/src/public/nixos-config"
  GIT_REPO="https://github.com/ausbxuse/nixos-config"

  # Clone repo (needed for nvim out-of-store symlink)
  if [ ! -d "$REPO_DIR" ]; then
    info "Cloning config repository..."
    mkdir -p "$(dirname "$REPO_DIR")"
    ${pkgs.git}/bin/git clone "$GIT_REPO" --depth 1 -b master "$REPO_DIR"
  else
    info "Config repo already exists at $REPO_DIR"
  fi

  # Patch globals.nix with current user
  info "Patching globals.nix..."
  ${pkgs.gnused}/bin/sed -i \
    -e "s/username = \"[^\"]*\";/username = \"$(whoami)\";/g" \
    "$REPO_DIR/globals.nix"

  # Enable flakes if needed
  NIX_CONF="$HOME/.config/nix/nix.conf"
  mkdir -p "$(dirname "$NIX_CONF")"
  if ! grep -q "extra-experimental-features" "$NIX_CONF" 2>/dev/null; then
    info "Enabling flakes..."
    echo 'extra-experimental-features = nix-command flakes' >> "$NIX_CONF"
  fi

  # Run home-manager switch
  info "Switching home-manager to $(whoami)@${flakeName}..."
  ${home-manager}/bin/home-manager switch \
    --flake "$REPO_DIR#$(whoami)@${flakeName}"

  # Setup zsh as default shell
  ZSH_PATH="$HOME/.nix-profile/bin/zsh"
  if [ -x "$ZSH_PATH" ]; then
    if ! grep -q "$ZSH_PATH" /etc/shells 2>/dev/null; then
      info "Adding zsh to /etc/shells..."
      echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
    fi
    if [ "$SHELL" != "$ZSH_PATH" ]; then
      info "Setting zsh as default shell..."
      chsh -s "$ZSH_PATH"
    fi
  fi

  info "Bootstrap complete!"
''
