#!/usr/bin/env bash
set -euo pipefail

tmux_bin="${TMUX_BIN:-tmux}"
workbench_bin="${WORKBENCH_BIN:-$HOME/.local/bin/tmux/workbench.sh}"
cmd="${1:-open}"
shift || true

current_pane() {
  if [[ -n "${TMUX_WORKBENCH_PANE:-}" ]]; then
    printf '%s\n' "$TMUX_WORKBENCH_PANE"
    return
  fi

  if [[ -n "${TMUX_PANE:-}" ]]; then
    printf '%s\n' "$TMUX_PANE"
    return
  fi

  "$tmux_bin" display -p '#{pane_id}'
}

current_window() {
  local pane

  if [[ -n "${TMUX_WORKBENCH_WINDOW:-}" ]]; then
    printf '%s\n' "$TMUX_WORKBENCH_WINDOW"
    return
  fi

  pane="$(current_pane 2>/dev/null || true)"
  if [[ -n "$pane" ]]; then
    "$tmux_bin" display -p -t "$pane" '#{window_id}'
    return
  fi

  "$tmux_bin" display -p '#{window_id}'
}

run_workbench() {
  local -a workbench_cmd

  read -r -a workbench_cmd <<< "$workbench_bin"
  "${workbench_cmd[@]}" "$@"
}

is_workbench_window() {
  local window task_root

  window="$(current_window 2>/dev/null || true)"
  [[ -n "$window" ]] || return 1
  task_root="$("$tmux_bin" show-options -wqv -t "$window" @task-root 2>/dev/null || true)"
  [[ -n "$task_root" && -d "$task_root" ]]
}

is_paired_terminal_window() {
  local window paired task_root

  window="$(current_window 2>/dev/null || true)"
  [[ -n "$window" ]] || return 1
  paired="$("$tmux_bin" show-options -wqv -t "$window" @paired-terminal 2>/dev/null || true)"
  task_root="$("$tmux_bin" show-options -wqv -t "$window" @task-root 2>/dev/null || true)"
  [[ -z "$task_root" || ! -d "$task_root" ]] || return 1
  [[ "$paired" == 1 ]]
}

pane_left() {
  "$tmux_bin" display -p -t "$1" '#{pane_left}' 2>/dev/null || printf '0'
}

pane_cwd() {
  local pane="$1" fallback="${2:-$HOME}" cwd

  cwd="$("$tmux_bin" display -p -t "$pane" '#{pane_current_path}' 2>/dev/null || true)"
  if [[ -n "$cwd" && -d "$cwd" ]]; then
    printf '%s\n' "$cwd"
  else
    printf '%s\n' "$fallback"
  fi
}

bottom_stack_pane() {
  local window="$1"

  "$tmux_bin" list-panes -t "$window" -F '#{pane_id}	#{pane_left}	#{pane_top}	#{pane_index}' 2>/dev/null |
    awk -F '\t' '$2 > 0 { print $1 "\t" $2 "\t" $3 "\t" $4 }' |
    sort -t $'\t' -k2,2nr -k3,3n -k4,4n |
    tail -n 1 |
    cut -f1
}

fallback_open() {
  local current window pane_count left target cwd

  current="$(current_pane)"
  window="$("$tmux_bin" display -p -t "$current" '#{window_id}')"
  pane_count="$("$tmux_bin" list-panes -t "$window" 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$pane_count" == 1 ]]; then
    cwd="$(pane_cwd "$current")"
    "$tmux_bin" split-window -h -c "$cwd" -t "$current"
  else
    left="$(pane_left "$current")"
    if ((left > 0)); then
      target="$current"
      cwd="$(pane_cwd "$target")"
    else
      target="$(bottom_stack_pane "$window")"
      [[ -n "$target" ]] || return 0
      cwd="$(pane_cwd "$target")"
    fi
    "$tmux_bin" split-window -v -c "$cwd" -t "$target"
  fi
}

fallback_close() {
  local current window pane_count left

  current="$(current_pane)"
  window="$("$tmux_bin" display -p -t "$current" '#{window_id}')"
  pane_count="$("$tmux_bin" list-panes -t "$window" 2>/dev/null | wc -l | tr -d ' ')"
  ((pane_count > 1)) || return 0
  left="$(pane_left "$current")"
  ((left > 0)) || return 0
  "$tmux_bin" kill-pane -t "$current"
}

fallback_swap() {
  local direction="${1:-next}" current window left target_index=-1 count i target
  local panes=()

  current="$(current_pane)"
  window="$("$tmux_bin" display -p -t "$current" '#{window_id}')"
  left="$(pane_left "$current")"
  ((left > 0)) || return 0

  mapfile -t panes < <(
    "$tmux_bin" list-panes -t "$window" -F '#{pane_id}	#{pane_left}	#{pane_top}	#{pane_index}' 2>/dev/null |
      awk -F '\t' -v left="$left" '$2 == left { print $1 "\t" $3 "\t" $4 }' |
      sort -t $'\t' -k2,2n -k3,3n |
      cut -f1
  )

  count="${#panes[@]}"
  ((count > 1)) || return 0

  for i in "${!panes[@]}"; do
    if [[ "${panes[$i]}" == "$current" ]]; then
      case "$direction" in
        prev | previous | up) target_index=$((i - 1)) ;;
        next | down) target_index=$((i + 1)) ;;
        *) return 2 ;;
      esac
      break
    fi
  done

  ((target_index >= 0 && target_index < count)) || return 0
  target="${panes[$target_index]}"
  "$tmux_bin" swap-pane -s "$current" -t "$target"
  "$tmux_bin" select-pane -t "$current"
}

rotate_panes() {
  local direction="${1:-next}" current window count flag

  current="$(current_pane)"
  window="$("$tmux_bin" display -p -t "$current" '#{window_id}')"
  count="$("$tmux_bin" list-panes -t "$window" 2>/dev/null | wc -l | tr -d ' ')"
  ((count > 1)) || return 0

  case "$direction" in
    prev | previous | up) flag=-U ;;
    next | down) flag=-D ;;
    *) return 2 ;;
  esac

  "$tmux_bin" rotate-window "$flag" -t "$window"
  "$tmux_bin" select-pane -t "$current" 2>/dev/null || true
}

fallback_layout() {
  local window

  window="$(current_window)"
  "$tmux_bin" select-layout -t "$window" main-vertical >/dev/null 2>&1 || true
}

target_window_for_index() {
  local current="$1" target="$2" session

  session="$("$tmux_bin" display -p -t "$current" '#{session_name}' 2>/dev/null || true)"
  [[ -n "$session" ]] || return 1
  "$tmux_bin" list-windows -t "$session" -F '#{window_index}	#{window_id}' 2>/dev/null |
    awk -F '\t' -v target="$target" '$1 == target { print $2; exit }'
}

move_window_to_index() {
  local current="$1" target="$2" select_after="${3:-1}" current_index session target_window

  current_index="$("$tmux_bin" display -p -t "$current" '#{window_index}' 2>/dev/null || true)"
  [[ -n "$current_index" && "$current_index" != "$target" ]] || return 0
  session="$("$tmux_bin" display -p -t "$current" '#{session_name}' 2>/dev/null || true)"
  [[ -n "$session" ]] || return 0

  target_window="$(target_window_for_index "$current" "$target")"
  if [[ -n "$target_window" ]]; then
    "$tmux_bin" swap-window -d -s "$current" -t "$target_window"
  else
    "$tmux_bin" move-window -s "$current" -t "$session:$target"
  fi

  if [[ "$select_after" == 1 ]]; then
    "$tmux_bin" select-window -t "$current" 2>/dev/null || true
  fi
  run_workbench layout "$current" >/dev/null 2>&1 || true
  run_workbench sync-paired-terminal-index "$current" >/dev/null 2>&1 || true
}

move_current_window_to_index() {
  local target="$1" current

  current="$(current_window)"
  move_window_to_index "$current" "$target" 1
}

move_current_pane_to_index() {
  local target="$1" current window current_index session target_window

  current="$(current_pane)"
  window="$("$tmux_bin" display -p -t "$current" '#{window_id}')"
  current_index="$("$tmux_bin" display -p -t "$window" '#{window_index}' 2>/dev/null || true)"
  [[ -n "$current_index" && "$current_index" != "$target" ]] || return 0
  session="$("$tmux_bin" display -p -t "$window" '#{session_name}' 2>/dev/null || true)"
  [[ -n "$session" ]] || return 0

  target_window="$(target_window_for_index "$window" "$target")"
  if [[ -z "$target_window" ]]; then
    "$tmux_bin" break-pane -s "$current" -t "$session:$target"
    return 0
  fi

  "$tmux_bin" join-pane -s "$current" -t "$target_window"
  "$tmux_bin" select-layout -t "$target_window" main-vertical >/dev/null 2>&1 || true
}

can_move_current_pane() {
  local current window task_root left

  current="$(current_pane)"
  window="$("$tmux_bin" display -p -t "$current" '#{window_id}')"
  task_root="$("$tmux_bin" show-options -wqv -t "$window" @task-root 2>/dev/null || true)"
  if [[ -n "$task_root" && -d "$task_root" ]]; then
    return 1
  fi

  left="$(pane_left "$current")"
  ((left > 0))
}

move_window() {
  local target="${1:-}" current window task_root paired workbench_window resolved

  [[ -n "$target" ]] || return 2

  current="$(current_pane)"
  window="$("$tmux_bin" display -p -t "$current" '#{window_id}')"
  task_root="$("$tmux_bin" show-options -wqv -t "$window" @task-root 2>/dev/null || true)"
  if [[ -n "$task_root" && -d "$task_root" ]]; then
    move_current_window_to_index "$target"
    return 0
  fi

  paired="$("$tmux_bin" show-options -wqv -t "$window" @paired-terminal 2>/dev/null || true)"
  if [[ "$paired" == 1 ]]; then
    workbench_window="$("$tmux_bin" show-options -wqv -t "$window" @workbench-window 2>/dev/null || true)"
    resolved="$("$tmux_bin" display -p -t "$workbench_window" '#{window_id}' 2>/dev/null || true)"
    if [[ -n "$workbench_window" && "$resolved" == "$workbench_window" ]]; then
      move_window_to_index "$workbench_window" "$target" 0
      run_workbench sync-paired-terminal-index "$workbench_window" >/dev/null 2>&1 || true
      "$tmux_bin" select-window -t "$window" 2>/dev/null || true
    fi
    return 0
  fi

  can_move_current_pane || return 0
  move_current_pane_to_index "$target"
}

case "$cmd" in
  open)
    if is_paired_terminal_window; then
      run_workbench terminal-toggle >/dev/null 2>&1 || true
    elif is_workbench_window; then
      run_workbench terminal-toggle >/dev/null 2>&1 || true
    else
      fallback_open
    fi
    ;;
  terminal)
    if is_paired_terminal_window || is_workbench_window; then
      run_workbench terminal-toggle >/dev/null 2>&1 || true
    else
      fallback_open
    fi
    ;;
  close)
    if is_paired_terminal_window; then
      run_workbench terminal-close >/dev/null 2>&1 || true
    elif is_workbench_window; then
      :
    else
      fallback_close
    fi
    ;;
  swap-next)
    if is_paired_terminal_window; then
      rotate_panes next
    elif is_workbench_window; then
      :
    else
      fallback_swap next
    fi
    ;;
  swap-prev)
    if is_paired_terminal_window; then
      rotate_panes prev
    elif is_workbench_window; then
      :
    else
      fallback_swap prev
    fi
    ;;
  layout)
    if is_paired_terminal_window; then
      run_workbench terminal-layout >/dev/null 2>&1 || true
    elif is_workbench_window; then
      run_workbench layout >/dev/null 2>&1 || true
    else
      fallback_layout
    fi
    ;;
  move-window)
    move_window "${1:-}"
    ;;
  *)
    printf 'usage: pane-manager.sh open|terminal|close|swap-next|swap-prev|layout|move-window TARGET\n' >&2
    exit 2
    ;;
esac
