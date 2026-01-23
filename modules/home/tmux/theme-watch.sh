#!/usr/bin/env bash
set -euo pipefail

if ! command -v gsettings >/dev/null 2>&1; then
  exit 0
fi

theme_cache="${XDG_CACHE_HOME:-$HOME/.cache}/tmux/theme"

light_wall="$HOME/.local/share/wallpapers/神里绫华同学2.png"
dark_wall="$HOME/.local/share/wallpapers/1310342-out.jpg"

light_uri="file://$light_wall"
dark_uri="file://$dark_wall"

detect_theme() {
  local scheme
  scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
  case "$scheme" in
    *dark*) printf "dark" ;;
    *light*) printf "light" ;;
    *) printf "light" ;;
  esac
}

apply_theme() {
  local theme
  theme=$(detect_theme)
  mkdir -p "$(dirname "$theme_cache")"
  printf "%s\n" "$theme" > "$theme_cache"

  if [ "$theme" = "light" ]; then
    gsettings set org.gnome.desktop.background picture-uri "$light_uri" >/dev/null 2>&1 || true
    gsettings set org.gnome.desktop.background picture-uri-dark "$dark_uri" >/dev/null 2>&1 || true
  else
    gsettings set org.gnome.desktop.background picture-uri "$light_uri" >/dev/null 2>&1 || true
    gsettings set org.gnome.desktop.background picture-uri-dark "$dark_uri" >/dev/null 2>&1 || true
  fi

  if tmux ls >/dev/null 2>&1; then
    tmux set-environment -g TMUX_COLOR_SCHEME "$theme" >/dev/null 2>&1 || true
    tmux source-file "$HOME/.config/tmux/tmux.conf" >/dev/null 2>&1 || true
  fi
}

apply_theme
gsettings monitor org.gnome.desktop.interface color-scheme | while read -r _; do
  apply_theme
done
