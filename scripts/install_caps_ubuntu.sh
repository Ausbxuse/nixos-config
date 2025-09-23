#!/usr/bin/env bash
set -euo pipefail

echo "[1/6] Installing interception-tools..."
sudo apt update
sudo apt install -y interception-tools interception-tools-plugins

echo "[2/6] Creating config directories..."
sudo mkdir -p /etc/interception/udevmon.d

echo "[3/6] Writing dual-function-keys.yaml..."
sudo tee /etc/dual-function-keys.yaml >/dev/null <<'EOF'
MAPPINGS:
  - KEY: KEY_CAPSLOCK
    TAP: KEY_ESC
    HOLD: KEY_LEFTCTRL
EOF

echo "[4/6] Writing udevmon pipeline config..."
sudo tee /etc/interception/udevmon.d/dual-function-keys.yaml >/dev/null <<'EOF'
- JOB: "intercept -g $DEVNODE \
       | dual-function-keys -c /etc/dual-function-keys.yaml \
       | uinput -d $DEVNODE"
  DEVICE:
    EVENTS:
      EV_KEY: [KEY_CAPSLOCK]
EOF

echo "[5/6] Enabling udevmon service..."
sudo systemctl enable udevmon
sudo systemctl restart udevmon

echo "[6/6] Adding current user to input/uinput groups..."
sudo groupadd -f input
sudo usermod -aG input "$USER"
sudo usermod -aG uinput "$USER"

echo
echo "✅ Setup complete!"
echo
echo "ℹ️ Please log out and back in (or reboot) for group membership changes to take effect."
echo "After reboot, CapsLock will act as Control when held, Escape when tapped."
