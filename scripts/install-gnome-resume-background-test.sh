#!/usr/bin/env bash
set -euo pipefail

target_dir="$HOME/.local/bin/gnome"
target_script="$target_dir/refresh-background-on-resume.sh"

mkdir -p "$target_dir"

cat > "$target_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

wait_for_gnome() {
  local i delay

  delay=0.05
  for i in $(seq 1 8); do
    if gdbus call --session \
      --dest org.gnome.Shell \
      --object-path /org/gnome/Shell \
      --method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; then
      if command -v gnome-monitor-config >/dev/null 2>&1; then
        if gnome-monitor-config list >/dev/null 2>&1; then
          return 0
        fi
      else
        return 0
      fi
    fi
    sleep "$delay"
    delay=$(awk "BEGIN { printf \"%.2f\", $delay * 2 }")
  done
}

refresh_background() {
  local bg_uri bg_dark_uri bg_options ss_uri ss_options tmp_options

  # Wait for GNOME Shell and monitor state to come back instead of using a
  # fixed resume delay. This avoids racing Mutter during resume.
  wait_for_gnome || true

  bg_uri="$(gsettings get org.gnome.desktop.background picture-uri | tr -d "'")"
  bg_dark_uri="$(gsettings get org.gnome.desktop.background picture-uri-dark | tr -d "'")"
  bg_options="$(gsettings get org.gnome.desktop.background picture-options | tr -d "'")"
  ss_uri="$(gsettings get org.gnome.desktop.screensaver picture-uri | tr -d "'")"
  ss_options="$(gsettings get org.gnome.desktop.screensaver picture-options | tr -d "'")"

  if [ -z "$bg_uri" ]; then
    exit 0
  fi

  tmp_options="centered"
  if [ "$bg_options" = "centered" ]; then
    tmp_options="zoom"
  fi

  gsettings set org.gnome.desktop.background picture-options "$tmp_options" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.background picture-uri "$bg_uri" >/dev/null 2>&1 || true
  if [ -n "$bg_dark_uri" ]; then
    gsettings set org.gnome.desktop.background picture-uri-dark "$bg_dark_uri" >/dev/null 2>&1 || true
  fi
  gsettings set org.gnome.desktop.background picture-options "$bg_options" >/dev/null 2>&1 || true

  if [ -n "$ss_uri" ]; then
    gsettings set org.gnome.desktop.screensaver picture-uri "$ss_uri" >/dev/null 2>&1 || true
  fi
  if [ -n "$ss_options" ]; then
    gsettings set org.gnome.desktop.screensaver picture-options "$ss_options" >/dev/null 2>&1 || true
  fi
}

refresh_background

dbus-monitor --system \
  "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" |
  while IFS= read -r line; do
    case "$line" in
      *"boolean false"*)
        refresh_background
        ;;
    esac
  done
EOF

chmod +x "$target_script"

cat <<MSG
Installed:
  $target_script

Run it in the background from your GNOME session with:
  nohup "$target_script" >/tmp/refresh-background-on-resume.log 2>&1 &

Optional smoke test without suspend:
  "$target_script" &
  sleep 3
  pkill -f refresh-background-on-resume.sh
MSG
