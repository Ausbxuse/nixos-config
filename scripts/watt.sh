#!/usr/bin/env bash
set -euo pipefail

battery_path=""
for d in /sys/class/power_supply/*; do
  [[ -d "$d" ]] || continue
  if [[ "$(cat "$d/type" 2>/dev/null)" == "Battery" ]]; then
    battery_path=$d
    break
  fi
done

if [[ -z "$battery_path" ]]; then
  echo "no battery found" >&2
  exit 1
fi

status=$(cat "$battery_path/status" 2>/dev/null || echo "unknown")

if [[ -r "$battery_path/power_now" ]]; then
  power_uw=$(cat "$battery_path/power_now")
elif [[ -r "$battery_path/current_now" && -r "$battery_path/voltage_now" ]]; then
  power_uw=$(awk -v c="$(cat "$battery_path/current_now")" -v v="$(cat "$battery_path/voltage_now")" 'BEGIN { printf "%.0f", (c * v) / 1000000 }')
else
  echo "no power telemetry found" >&2
  exit 1
fi

awk -v p="$power_uw" -v s="$status" 'BEGIN {
  if (s == "Discharging") sign = "-"
  else if (s == "Charging") sign = "+"
  else sign = ""
  printf "%s%.2f W\n", sign, p / 1000000
}'
