#!/usr/bin/env bash
set -euo pipefail

tmux_bin="${TMUX_BIN:-tmux}"
workbench_bin="${WORKBENCH_BIN:-$HOME/.local/bin/tmux/workbench.sh}"
home_dir="${HOME:?}"
session="${TMUX_WORKBENCH_SESSION:-}"

roots=(
  "$home_dir/src/public"
  "$home_dir/src/private"
  "$home_dir/src/school"
  "$home_dir/Research"
  "$home_dir/src/dev"
)

sanitize_name() {
  printf '%s' "$1" |
    tr '/:.[:space:]' '----' |
    tr -cs 'A-Za-z0-9_-' '-' |
    sed -E 's/^[-_]+//; s/[-_]+$//'
}

project_name() {
  local path="$1" rel base

  rel="${path#"$home_dir"/}"
  base="$(basename "$path")"

  case "$rel" in
    src/public/*) sanitize_name "public-$base" ;;
    src/private/*) sanitize_name "private-$base" ;;
    src/school/*) sanitize_name "school-$base" ;;
    src/dev/*) sanitize_name "dev-$base" ;;
    Research/*) sanitize_name "research-$base" ;;
    *) sanitize_name "$base" ;;
  esac
}

window_option() {
  "$tmux_bin" show-options -wqv -t "$1" "$2" 2>/dev/null || true
}

is_workbench_helper_session() {
  local session="${1:-}"

  [[ -n "$session" ]] || return 1
  [[ "$session" == "${WORKBENCH_PARK_SESSION:-__workbench-park}" ]] && return 0
  [[ "$session" == *-terms ]] && return 0
  return 1
}

workbench_session_for_context() {
  local session="$1" window="${2:-}" owner parked_for parked_session

  if is_workbench_helper_session "$session"; then
    if [[ -n "$window" ]]; then
      owner="$(window_option "$window" @workbench-session)"
      if [[ -n "$owner" && "$owner" != @* && "$owner" != "$session" ]]; then
        printf '%s\n' "$owner"
        return 0
      fi

      parked_for="$(window_option "$window" @parked-for)"
      if [[ -n "$parked_for" ]]; then
        parked_session="$("$tmux_bin" display -p -t "$parked_for" '#{session_name}' 2>/dev/null || true)"
        if [[ -n "$parked_session" && "$parked_session" != "$session" ]]; then
          printf '%s\n' "$parked_session"
          return 0
        fi
      fi
    fi

    case "$session" in
      *-terms)
        while [[ "$session" == *-terms ]]; do
          session="${session%-terms}"
        done
        printf '%s\n' "$session"
        return 0
        ;;
    esac
  fi

  printf '%s\n' "$session"
}

current_or_main_session() {
  local current window

  if [[ -n "$session" ]]; then
    printf '%s\n' "$(workbench_session_for_context "$session")"
    return
  fi

  if [[ -n "${TMUX:-}" ]]; then
    current="$("$tmux_bin" display -p '#{session_name}')"
    window="$("$tmux_bin" display -p '#{window_id}')"
    workbench_session_for_context "$current" "$window"
  else
    printf '%s\n' main
  fi
}

list_projects() {
  local root dir

  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    if command -v fd >/dev/null 2>&1; then
      fd . "$root" --type d --exact-depth 1 2>/dev/null || true
    else
      find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true
    fi
  done

  if command -v zoxide >/dev/null 2>&1; then
    zoxide query -l 2>/dev/null | while IFS= read -r dir; do
      [[ -d "$dir" ]] && printf '%s\n' "$dir"
    done
  fi
}

normalize_project_paths() {
  local path normalized

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    normalized="$(realpath -m "$path" 2>/dev/null || true)"
    [[ -n "$normalized" && -d "$normalized" ]] || continue
    printf '%s\n' "$normalized"
  done
}

list_windows() {
  local target="$1"

  "$tmux_bin" list-windows -t "$target" -F 'window	#{window_id}	#{window_index}:#{window_name}	#{@task-root}' 2>/dev/null || true
}

list_choices() {
  local target="$1"

  list_windows "$target"
  list_projects |
    normalize_project_paths |
    awk '!seen[$0]++' |
    while IFS= read -r path; do
      printf 'project\t%s\t%s\t%s\n' "$path" "$(project_name "$path")" "$path"
    done
}

select_choice() {
  local target="$1"

  if [[ $# -gt 1 ]]; then
    local path="$2"
    path="$(realpath -m "$path")"
    printf 'project\t%s\t%s\t%s\n' "$path" "$(project_name "$path")" "$path"
    return
  fi

  list_choices "$target" |
    fzf \
      --reverse \
      --delimiter=$'\t' \
      --with-nth=3,4 \
      --prompt='window or project > ' \
      --preview='
        PATH="$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
        compact_home() {
          while IFS= read -r line; do
            if [ -n "$HOME" ]; then
              printf "%s\n" "${line//$HOME/~}"
            else
              printf "%s\n" "$line"
            fi
          done
        }

        kind=$(printf "%s" {} | cut -f1)
        target=$(printf "%s" {} | cut -f2)
        path=$(printf "%s" {} | cut -f4-)
        if [ "$kind" = window ]; then
          tmux list-panes -t "$target" -F "#{pane_index} #{pane_current_command} #{@pane-role} #{pane_current_path}" 2>/dev/null |
            compact_home
        else
          if command -v git >/dev/null 2>&1 && output=$(git -C "$path" status --short --branch 2>/dev/null); then
            printf "%s\n" "$output" | compact_home
            exit 0
          fi

          if command -v eza >/dev/null 2>&1; then
            if output=$(eza -la --group-directories-first "$path" 2>/dev/null); then
              printf "%s\n" "$output" | compact_home
              exit 0
            fi
          fi

          ls_bin=$(command -v ls 2>/dev/null || printf /run/current-system/sw/bin/ls)
          "$ls_bin" -la "$path" 2>/dev/null | compact_home
        fi
      ' \
      --preview-window='right:50%:wrap'
}

target_session="$(current_or_main_session)"

selected="$(select_choice "$target_session" "$@")"
[[ -n "${selected:-}" ]] || exit 0

kind="$(printf '%s' "$selected" | cut -f1)"
target="$(printf '%s' "$selected" | cut -f2)"
label="$(printf '%s' "$selected" | cut -f3)"
path="$(printf '%s' "$selected" | cut -f4-)"

case "$kind" in
  window)
    if [[ -n "${TMUX:-}" ]]; then
      "$tmux_bin" switch-client -t "$target_session"
      "$tmux_bin" select-window -t "$target"
    else
      exec "$tmux_bin" attach -t "$target_session"
    fi
    ;;
  project)
    "$workbench_bin" create "$target_session" "$label" "$path"
    if [[ -z "${TMUX:-}" ]]; then
      exec "$tmux_bin" attach -t "$target_session"
    fi
    ;;
  *)
    exit 2
    ;;
esac
