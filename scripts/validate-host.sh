#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

failures=0

section() {
  printf '\n[%s]\n' "$1"
}

pass() {
  printf 'PASS: %s\n' "$1"
}

warn() {
  printf 'WARN: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

check_cmd() {
  command -v "$1" >/dev/null 2>&1
}

section "System"
if systemctl is-system-running --wait >/dev/null 2>&1; then
  pass "system reached a healthy state"
else
  warn "systemd reports a degraded or starting state"
fi

section "Audio"
if check_cmd wpctl; then
  if wpctl status | grep -q "Dummy Output"; then
    fail "PipeWire only exposes Dummy Output"
  else
    pass "PipeWire has a non-dummy sink"
  fi
else
  warn "wpctl not installed"
fi

if check_cmd aplay; then
  if aplay -l >/dev/null 2>&1; then
    pass "ALSA playback devices enumerate"
  else
    fail "No ALSA playback devices"
  fi
fi

if check_cmd arecord; then
  if arecord -l >/dev/null 2>&1; then
    pass "ALSA capture devices enumerate"
  else
    fail "No ALSA capture devices"
  fi
fi

section "Camera"
if check_cmd v4l2-ctl; then
  if v4l2-ctl --list-devices >/dev/null 2>&1; then
    pass "V4L2 camera devices enumerate"
  else
    fail "No V4L2 camera devices"
  fi
else
  warn "v4l2-ctl not installed"
fi

section "Brightness"
if check_cmd brightnessctl; then
  if brightnessctl -l | grep -q .; then
    pass "brightness devices enumerate"
  else
    fail "No brightness devices exposed"
  fi
else
  warn "brightnessctl not installed"
fi

section "GPU"
if lspci | grep -qi 'NVIDIA'; then
  if check_cmd nvidia-smi && nvidia-smi >/dev/null 2>&1; then
    pass "nvidia-smi can talk to the NVIDIA driver"
  else
    fail "NVIDIA GPU present but nvidia-smi failed"
  fi
fi

section "Summary"
if [[ $failures -eq 0 ]]; then
  pass "all host validation checks passed"
else
  fail "$failures validation check(s) failed"
fi

exit "$failures"
