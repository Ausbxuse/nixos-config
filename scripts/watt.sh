#!/usr/bin/env bash
set -euo pipefail

power_supply_root="${POWER_SUPPLY_ROOT:-/sys/class/power_supply}"
nvidia_pci_root="${NVIDIA_PCI_ROOT:-/sys/bus/pci/devices}"
nvidia_query_mode="${WATT_NVIDIA_QUERY:-auto}"
sample_seconds="${WATT_SAMPLE_SECONDS:-5}"

read_file() {
  local path="$1"

  cat "$path" 2>/dev/null || true
}

read_int() {
  local path="$1"
  local value

  value="$(read_file "$path")"
  [[ "$value" =~ ^-?[0-9]+$ ]] || return 1
  printf '%s\n' "$value"
}

battery_power_uw() {
  local battery_path="$1"
  local current_ua voltage_uv

  if [[ -r "$battery_path/power_now" ]]; then
    read_int "$battery_path/power_now"
    return
  fi

  if [[ -r "$battery_path/current_now" && -r "$battery_path/voltage_now" ]]; then
    current_ua="$(read_int "$battery_path/current_now")"
    voltage_uv="$(read_int "$battery_path/voltage_now")"
    awk -v c="$current_ua" -v v="$voltage_uv" 'BEGIN { printf "%.0f\n", (c * v) / 1000000 }'
    return
  fi

  return 1
}

instant_battery_power_uw() {
  local power_uw="$1"
  local status="$2"

  awk -v p="$power_uw" -v s="$status" 'BEGIN {
    if (s == "Discharging") p = -p
    printf "%.0f\n", p
  }'
}

sampled_battery_power_uw() {
  local battery_path="$1"
  local seconds="$2"
  local first_value second_value first_voltage second_voltage field

  [[ "$seconds" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  awk -v s="$seconds" 'BEGIN { exit !(s > 0) }'

  if [[ -r "$battery_path/energy_now" ]]; then
    field="energy_now"
    first_value="$(read_int "$battery_path/$field")"
    sleep "$seconds"
    second_value="$(read_int "$battery_path/$field")"
    awk -v a="$first_value" -v b="$second_value" -v s="$seconds" 'BEGIN {
      printf "%.0f\n", ((b - a) * 3600) / s
    }'
    return
  fi

  if [[ -r "$battery_path/charge_now" && -r "$battery_path/voltage_now" ]]; then
    field="charge_now"
    first_value="$(read_int "$battery_path/$field")"
    first_voltage="$(read_int "$battery_path/voltage_now")"
    sleep "$seconds"
    second_value="$(read_int "$battery_path/$field")"
    second_voltage="$(read_int "$battery_path/voltage_now")"
    awk \
      -v a="$first_value" \
      -v b="$second_value" \
      -v va="$first_voltage" \
      -v vb="$second_voltage" \
      -v s="$seconds" \
      'BEGIN {
        avg_v = (va + vb) / 2
        printf "%.0f\n", (((b - a) * avg_v) / 1000000) * 3600 / s
      }'
    return
  fi

  return 1
}

format_watts() {
  local microwatts="$1"

  awk -v p="$microwatts" 'BEGIN { printf "%.2f W", p / 1000000 }'
}

online_power_supplies() {
  local d type online name usb_type

  for d in "$power_supply_root"/*; do
    [[ -d "$d" ]] || continue
    type="$(read_file "$d/type")"
    case "$type" in
      Mains | USB | USB_C | USB_PD) ;;
      *) continue ;;
    esac

    online="$(read_file "$d/online")"
    [[ "$online" == "1" ]] || continue

    name="${d##*/}"
    usb_type="$(read_file "$d/usb_type")"
    if [[ -n "$usb_type" ]]; then
      printf '%s (%s)\n' "$name" "$usb_type"
    else
      printf '%s\n' "$name"
    fi
  done
}

nvidia_runtime_statuses() {
  local d vendor class status

  for d in "$nvidia_pci_root"/*; do
    [[ -d "$d" ]] || continue

    vendor="$(read_file "$d/vendor")"
    [[ "${vendor,,}" == "0x10de" ]] || continue

    class="$(read_file "$d/class")"
    # PCI display controller classes: VGA, 3D controller, and display controller.
    [[ "${class,,}" == 0x03* ]] || continue

    if [[ -r "$d/power/runtime_status" ]]; then
      status="$(read_file "$d/power/runtime_status")"
      printf '%s\n' "${status:-unknown}"
    else
      printf 'unknown\n'
    fi
  done
}

nvidia_runtime_state() {
  local status found=false any_active=false any_unknown=false

  while IFS= read -r status; do
    found=true
    case "$status" in
      active) any_active=true ;;
      unknown | "") any_unknown=true ;;
    esac
  done < <(nvidia_runtime_statuses)

  if [[ "$found" != true ]]; then
    printf 'absent\n'
  elif [[ "$any_active" == true ]]; then
    printf 'active\n'
  elif [[ "$any_unknown" == true ]]; then
    printf 'unknown\n'
  else
    printf 'suspended\n'
  fi
}

nvidia_power_watts() {
  local state="$1"
  local values

  case "$nvidia_query_mode" in
    auto | "")
      [[ "$state" == "active" ]] || return 2
      ;;
    always | force | yes | true | 1) ;;
    never | off | no | false | 0) return 2 ;;
    *)
      printf 'invalid WATT_NVIDIA_QUERY=%s; expected auto, always, or never\n' "$nvidia_query_mode" >&2
      return 2
      ;;
  esac

  command -v nvidia-smi >/dev/null 2>&1 || return 1
  values="$(
    nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null \
      | awk '
          /^[[:space:]]*(N\/A)?[[:space:]]*$/ { next }
          {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if ($0 ~ /^[0-9]+([.][0-9]+)?$/) total += $0
          }
          END {
            if (total > 0) printf "%.2f\n", total
          }
        '
  )"
  [[ -n "$values" ]] || return 1
  printf '%s\n' "$values"
}

battery_path=""
for d in "$power_supply_root"/*; do
  [[ -d "$d" ]] || continue
  if [[ "$(read_file "$d/type")" == "Battery" ]]; then
    battery_path=$d
    break
  fi
done

if [[ -z "$battery_path" ]]; then
  echo "no battery found" >&2
  exit 1
fi

battery_status="$(read_file "$battery_path/status")"
battery_status="${battery_status:-unknown}"

if ! power_uw="$(battery_power_uw "$battery_path")"; then
  echo "no power telemetry found" >&2
  exit 1
fi

instant_power_uw="$(instant_battery_power_uw "$power_uw" "$battery_status")"

if sampled_power_uw="$(sampled_battery_power_uw "$battery_path" "$sample_seconds")"; then
  printf 'battery %s sampled over %ss (%s)\n' "$(format_watts "$sampled_power_uw")" "$sample_seconds" "$battery_status"
  if awk -v sampled="$sampled_power_uw" -v instant="$instant_power_uw" 'BEGIN {
    exit !((sampled < 0 && instant > 0) || (sampled > 0 && instant < 0))
  }'; then
    printf 'battery instant %s from ACPI current (%s)\n' "$(format_watts "$instant_power_uw")" "$battery_status"
  fi
  signed_power_uw="$sampled_power_uw"
else
  printf 'battery %s instant (%s)\n' "$(format_watts "$instant_power_uw")" "$battery_status"
  signed_power_uw="$instant_power_uw"
fi

if mapfile -t supplies < <(online_power_supplies) && ((${#supplies[@]} > 0)); then
  printf 'ac online: %s\n' "$(IFS=', '; printf '%s' "${supplies[*]}")"
else
  printf 'ac online: no\n'
fi

nvidia_state="$(nvidia_runtime_state)"
if gpu_watts="$(nvidia_power_watts "$nvidia_state")"; then
  printf 'nvidia %.2f W\n' "$gpu_watts"
  awk -v b="$signed_power_uw" -v g="$gpu_watts" 'BEGIN {
    if (b < 0) {
      printf "visible draw at least %.2f W (nvidia + battery drain; adapter draw not exposed)\n", g + (-b / 1000000)
    }
  }'
else
  gpu_status=$?
  if [[ "$gpu_status" == 2 ]]; then
    case "$nvidia_query_mode" in
      never | off | no | false | 0)
        printf 'nvidia skipped (WATT_NVIDIA_QUERY=%s)\n' "$nvidia_query_mode"
        ;;
      *)
        case "$nvidia_state" in
          suspended) printf 'nvidia asleep (skipped nvidia-smi)\n' ;;
          unknown) printf 'nvidia runtime unknown (skipped nvidia-smi; set WATT_NVIDIA_QUERY=always to force)\n' ;;
          *) printf 'nvidia unavailable\n' ;;
        esac
        ;;
    esac
  else
    printf 'nvidia unavailable\n'
  fi
fi
