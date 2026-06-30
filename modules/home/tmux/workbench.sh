#!/usr/bin/env bash
set -euo pipefail

tmux_bin="${TMUX_BIN:-tmux}"
agent_cmd="${AGENT_CMD:-codex}"
workbench_bin="${WORKBENCH_BIN:-$HOME/.local/bin/tmux/workbench.sh}"
home_dir="${HOME:?}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/tmux-workbench"
preview_dir="$state_dir/previews"
event_dir="$state_dir/events"
sync_dir="$state_dir/sync"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

ensure_preview_dir() {
  mkdir -p "$preview_dir"
}

ensure_event_dir() {
  mkdir -p "$event_dir"
}

ensure_sync_dir() {
  mkdir -p "$sync_dir"
}

now_epoch() {
  date +%s
}

now_millis() {
  date +%s%3N
}

sync_interval_ms() {
  if [[ "${WORKBENCH_SYNC_INTERVAL_MS:-}" =~ ^[0-9]+$ && "${WORKBENCH_SYNC_INTERVAL_MS:-}" -gt 0 ]]; then
    printf '%s\n' "$WORKBENCH_SYNC_INTERVAL_MS"
    return
  fi

  if [[ "${WORKBENCH_SYNC_INTERVAL_SECS:-}" =~ ^[0-9]+$ && "${WORKBENCH_SYNC_INTERVAL_SECS:-}" -gt 0 ]]; then
    printf '%s\n' "$((WORKBENCH_SYNC_INTERVAL_SECS * 1000))"
    return
  fi

  printf '300\n'
}

current_session() {
  local pane

  if [[ -n "${TMUX_WORKBENCH_SESSION:-}" ]]; then
    printf '%s\n' "$TMUX_WORKBENCH_SESSION"
    return
  fi

  pane="$(context_pane || true)"
  if [[ -n "$pane" ]]; then
    "$tmux_bin" display -p -t "$pane" '#{session_name}'
    return
  fi

  "$tmux_bin" display -p '#{session_name}'
}

current_window() {
  local pane

  if [[ -n "${TMUX_WORKBENCH_WINDOW:-}" ]]; then
    printf '%s\n' "$TMUX_WORKBENCH_WINDOW"
    return
  fi

  pane="$(context_pane || true)"
  if [[ -n "$pane" ]]; then
    "$tmux_bin" display -p -t "$pane" '#{window_id}'
    return
  fi

  "$tmux_bin" display -p '#{window_id}'
}

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

context_pane() {
  local pane="${TMUX_WORKBENCH_PANE:-${TMUX_PANE:-}}"

  [[ -n "$pane" ]] || return 1
  pane_exists "$pane" || return 1
  printf '%s\n' "$pane"
}

window_option() {
  "$tmux_bin" show-options -wqv -t "$1" "$2" 2>/dev/null || true
}

set_window_option() {
  "$tmux_bin" set-option -wq -t "$1" "$2" "$3"
}

unset_window_option() {
  "$tmux_bin" set-option -wqu -t "$1" "$2" 2>/dev/null || true
}

pane_option() {
  "$tmux_bin" show-options -pqv -t "$1" "$2" 2>/dev/null || true
}

set_pane_option() {
  "$tmux_bin" set-option -pq -t "$1" "$2" "$3"
}

unset_pane_option() {
  "$tmux_bin" set-option -pqu -t "$1" "$2" 2>/dev/null || true
}

pane_exists() {
  local pane="$1" resolved

  resolved="$("$tmux_bin" display -p -t "$pane" '#{pane_id}' 2>/dev/null || true)"
  [[ -n "$resolved" && "$resolved" == "$pane" ]]
}

pane_in_window() {
  local pane="$1" window="$2" pane_window

  pane_exists "$pane" || return 1
  pane_window="$("$tmux_bin" display -p -t "$pane" '#{window_id}' 2>/dev/null || true)"
  [[ "$pane_window" == "$window" ]]
}

pane_cwd() {
  local pane="$1" fallback="${2:-$home_dir}" cwd

  cwd="$("$tmux_bin" display -p -t "$pane" '#{pane_current_path}' 2>/dev/null || true)"
  if [[ -n "$cwd" && -d "$cwd" ]]; then
    printf '%s\n' "$cwd"
  else
    printf '%s\n' "$fallback"
  fi
}

visible_primary_pane() {
  local window="$1" focus role owner

  focus="$(window_option "$window" @focus-pane)"
  if [[ -n "$focus" ]] && pane_in_window "$focus" "$window"; then
    role="$(pane_option "$focus" @pane-role)"
    owner="$(pane_option "$focus" @workbench-window)"
    if [[ "$owner" == "$window" && ( "$role" == agent || "$role" == editor ) ]]; then
      printf '%s\n' "$focus"
      return
    fi
  fi

  "$tmux_bin" list-panes -t "$window" -F '#{pane_id}	#{@pane-role}	#{@workbench-window}' 2>/dev/null |
    awk -F '\t' -v window="$window" '$3 == window && ($2 == "agent" || $2 == "editor") { print $1; exit }'
}

window_task_root() {
  local window="$1" root

  root="$(window_option "$window" @task-root)"
  [[ -n "$root" && -d "$root" ]] || return 1
  printf '%s\n' "$root"
}

is_workbench_window() {
  window_task_root "$1" >/dev/null
}

valid_terminal_session_name() {
  local session="$1" term_session="$2"

  [[ -n "$term_session" && "$term_session" != "$session" && "$term_session" != @* ]]
}

is_workbench_helper_session() {
  local session="${1:-}"

  [[ -n "$session" ]] || return 1
  [[ "$session" == "${WORKBENCH_PARK_SESSION:-__workbench-park}" ]] && return 0
  [[ "$session" == *-terms ]] && return 0
  return 1
}

is_paired_terminal_window() {
  local window="$1" paired workbench_window

  [[ -n "$window" ]] || return 1
  paired="$(window_option "$window" @paired-terminal)"
  [[ "$paired" == 1 ]] || return 1
  is_workbench_window "$window" && return 1
  workbench_window="$(window_option "$window" @workbench-window)"
  [[ -n "$workbench_window" && "$workbench_window" != "$window" ]]
}

is_paired_terminal_window_for() {
  local window="$1" workbench_window="$2"

  is_paired_terminal_window "$window" || return 1
  [[ "$(window_option "$window" @workbench-window)" == "$workbench_window" ]]
}

heal_workbench_pane() {
  local pane="$1" window="$2" role="$3"

  [[ -n "$pane" ]] || return 0
  pane_exists "$pane" || return 0
  set_pane_option "$pane" @pane-role "$role"
  set_pane_option "$pane" @workbench-window "$window"
}

heal_workbench_window() {
  local window="$1" session term_session default_term_session term_window
  local agent editor focus parked

  is_workbench_window "$window" || return 0

  unset_window_option "$window" @paired-terminal
  unset_window_option "$window" @workbench-session
  unset_window_option "$window" @workbench-window
  unset_window_option "$window" @term-root
  unset_window_option "$window" @parked-for

  agent="$(window_option "$window" @agent-pane)"
  editor="$(window_option "$window" @editor-pane)"
  focus="$(window_option "$window" @focus-pane)"
  parked="$(window_option "$window" @parked-primary-pane)"

  heal_workbench_pane "$agent" "$window" agent
  heal_workbench_pane "$editor" "$window" editor
  if [[ -n "$focus" && "$focus" != "$agent" && "$focus" != "$editor" ]]; then
    unset_window_option "$window" @focus-pane
  fi
  if [[ -n "$parked" && "$parked" != "$agent" && "$parked" != "$editor" ]]; then
    unset_window_option "$window" @parked-primary-pane
  fi

  session="$("$tmux_bin" display -p -t "$window" '#{session_name}' 2>/dev/null || true)"
  if is_workbench_helper_session "$session"; then
    unset_window_option "$window" @term-session
    unset_window_option "$window" @term-window
    return 0
  fi

  default_term_session="$(terminal_session_name "$session")"
  term_session="$(window_option "$window" @term-session)"
  if ! valid_terminal_session_name "$session" "$term_session"; then
    set_window_option "$window" @term-session "$default_term_session"
  fi

  term_window="$(window_option "$window" @term-window)"
  if [[ "$term_window" == "$window" ]] || ! is_paired_terminal_window_for "$term_window" "$window"; then
    unset_window_option "$window" @term-window
  fi
}

safe_key() {
  printf '%s' "$1" | tr -c '[:alnum:]_.:-' '_'
}

event_file_for_session() {
  printf '%s/%s.event\n' "$event_dir" "$(safe_key "$1")"
}

bump_event() {
  local session="${1:-}" file tmp

  [[ -n "$session" ]] || return 0
  ensure_event_dir
  file="$(event_file_for_session "$session")"
  tmp="$file.$$"
  printf '%s\t%s\n' "$(date +%s.%N)" "$$" > "$tmp" 2>/dev/null || return 0
  mv -f "$tmp" "$file" 2>/dev/null || true
}

bump_window_event() {
  local window="$1" session

  session="$("$tmux_bin" display -p -t "$window" '#{session_name}' 2>/dev/null || true)"
  bump_event "$session"
}

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

project_root_for_path() {
  local path="$1" root

  path="$(realpath -m "$path")"
  if command -v git >/dev/null 2>&1; then
    root="$(git -C "$path" rev-parse --show-toplevel 2>/dev/null || true)"
  fi

  printf '%s\n' "${root:-$path}"
}

unique_window_name() {
  local session="$1" base="$2" candidate n

  candidate="$base"
  n=2
  while "$tmux_bin" list-windows -t "$session" -F '#{window_name}' 2>/dev/null | grep -Fxq "$candidate"; do
    candidate="$base-$n"
    n=$((n + 1))
  done

  printf '%s\n' "$candidate"
}

find_window_by_root() {
  local session="$1" root="$2" name="$3"
  local id task_root window_name

  "$tmux_bin" list-windows -t "$session" -F '#{window_id}	#{@task-root}	#{window_name}' 2>/dev/null |
    while IFS=$'\t' read -r id task_root window_name; do
      if [[ "$task_root" == "$root" || "$window_name" == "$name" ]]; then
        printf '%s\n' "$id"
        return 0
      fi
    done
}

first_workbench_window() {
  local session="$1" window root agent

  while IFS=$'\t' read -r window root agent; do
    [[ -n "$window" && -n "$root" && -d "$root" && -n "$agent" ]] || continue
    printf '%s\n' "$window"
    return 0
  done < <("$tmux_bin" list-windows -t "$session" -F '#{window_id}	#{@task-root}	#{@agent-pane}' 2>/dev/null || true)
}

select_window() {
  local session="$1" window="$2"

  if [[ -n "${TMUX:-}" ]]; then
    "$tmux_bin" switch-client -t "$session" 2>/dev/null || true
    "$tmux_bin" select-window -t "$window" 2>/dev/null || true
  fi
}

capture_preview() {
  local pane="$1" window="$2" file tmp

  [[ -n "$pane" ]] || return 0
  pane_exists "$pane" || return 0

  ensure_preview_dir
  file="$preview_dir/$(safe_key "$window").txt"
  tmp="$file.tmp"

  "$tmux_bin" capture-pane -pJ -S -80 -t "$pane" > "$tmp" 2>/dev/null || true
  sed '/^[[:space:]]*$/d' "$tmp" | tail -n 24 > "$file" || true
  rm -f "$tmp"

  set_window_option "$window" @agent-preview-file "$file"
}

classify_state_summary() {
  local state="$1" summary="$2" lowered

  lowered="${summary,,}"
  case "$lowered" in
    *'"type":"task_started"'* | *agent-turn-start* | *turn-start* | *turn_start*)
      state=running
      [[ -n "$summary" && "$summary" != \{* ]] || summary=working
      ;;
    *'"type":"task_complete"'* | *agent-turn-complete* | *turn-complete* | *turn_complete*)
      state=done
      [[ -n "$summary" && "$summary" != \{* ]] || summary="needs review"
      ;;
    *'"type":"error"'* | *agent-turn-error* | *turn-error* | *failed* | *failure* | *blocked*)
      state=blocked
      [[ -n "$summary" && "$summary" != \{* ]] || summary=blocked
      ;;
    *approval* | *requires-input* | *needs-input* | *needs_input* | *user_attention* | *attention*)
      state=waiting
      [[ -n "$summary" && "$summary" != \{* ]] || summary="needs attention"
      ;;
  esac

  printf '%s\t%s\n' "$state" "$summary"
}

set_state() {
  local state="${1:-}" summary target window agent_pane updated owner
  shift || true
  summary="$*"
  summary="$(printf '%s' "$summary" | tr '\n' ' ' | cut -c 1-240)"

  [[ -n "$state" ]] || fail "usage: workbench.sh state STATE [summary]"
  case "$state" in
    needs-input) state=waiting ;;
    error) state=blocked ;;
    busy) state=running ;;
  esac
  IFS=$'\t' read -r state summary < <(classify_state_summary "$state" "$summary")

  target="${TMUX_WORKBENCH_TARGET_PANE:-${TMUX_PANE:-}}"
  if [[ -n "$target" ]] && pane_exists "$target"; then
    owner="$(pane_option "$target" @workbench-window)"
    if [[ -n "$owner" ]]; then
      window="$owner"
    else
      window="$("$tmux_bin" display -p -t "$target" '#{window_id}')"
    fi
  else
    window="$(current_window)"
  fi

  agent_pane="$(window_option "$window" @agent-pane)"
  if [[ -z "$agent_pane" && -n "$target" ]] && pane_exists "$target"; then
    agent_pane="$target"
    set_window_option "$window" @agent-pane "$agent_pane"
    set_pane_option "$agent_pane" @pane-role agent
    set_pane_option "$agent_pane" @workbench-window "$window"
  fi

  updated="$(now_epoch)"
  set_window_option "$window" @agent-state "$state"
  set_window_option "$window" @agent-summary "${summary:-$state}"
  set_window_option "$window" @agent-updated "$updated"

  case "$state" in
    waiting | needs-input | blocked | error | done)
      capture_preview "$agent_pane" "$window"
      ;;
  esac

  bump_window_event "$window"
  "$tmux_bin" refresh-client -S 2>/dev/null || true
}

descendant_pids() {
  local pid="$1" child

  [[ -n "$pid" && -d "/proc/$pid" ]] || return 0
  printf '%s\n' "$pid"
  command -v pgrep >/dev/null 2>&1 || return 0

  while IFS= read -r child; do
    [[ -n "$child" ]] || continue
    descendant_pids "$child"
  done < <(pgrep -P "$pid" 2>/dev/null || true)
}

codex_session_for_pane() {
  local pane="$1" root_pid pid fd target best="" best_mtime=0 mtime

  root_pid="$("$tmux_bin" display -p -t "$pane" '#{pane_pid}' 2>/dev/null || true)"
  [[ -n "$root_pid" ]] || return 0

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    for fd in "/proc/$pid/fd/"*; do
      [[ -e "$fd" ]] || continue
      target="$(readlink "$fd" 2>/dev/null || true)"
      case "$target" in
        "$HOME"/.codex/sessions/*.jsonl)
          mtime="$(stat -c %Y "$target" 2>/dev/null || printf '0')"
          if ((mtime >= best_mtime)); then
            best="$target"
            best_mtime="$mtime"
          fi
          ;;
      esac
    done
  done < <(descendant_pids "$root_pid")

  [[ -n "$best" ]] && printf '%s\n' "$best"
}

codex_state_from_session() {
  local file="$1" state="" summary="" updated="" line ts tail_lines

  [[ -n "$file" && -f "$file" ]] || return 0
  tail_lines="${WORKBENCH_CODEX_TAIL_LINES:-800}"
  [[ "$tail_lines" =~ ^[0-9]+$ && "$tail_lines" -gt 0 ]] || tail_lines=800

  while IFS= read -r line; do
    case "$line" in
      *'"type":"task_started"'*)
        state=running
        summary=working
        ts="$(printf '%s' "$line" | sed -n 's/.*"started_at":\([0-9][0-9]*\).*/\1/p')"
        [[ -n "$ts" ]] && updated="$ts"
        break
        ;;
      *'"type":"task_complete"'*)
        state=done
        summary="needs review"
        ts="$(printf '%s' "$line" | sed -n 's/.*"completed_at":\([0-9][0-9]*\).*/\1/p')"
        [[ -n "$ts" ]] && updated="$ts"
        break
        ;;
      *'"type":"turn_aborted"'* | *'"type":"task_aborted"'*)
        state=blocked
        summary=aborted
        updated="$(now_epoch)"
        break
        ;;
      *'"type":"agent_message"'* | *'"type":"reasoning"'* | *'"type":"function_call"'* | *'"type":"function_call_output"'* | *'"type":"response_item"'*)
        state=running
        summary=working
        updated="$(now_epoch)"
        break
        ;;
    esac
  done < <(
    if command -v tac >/dev/null 2>&1; then
      tail -n "$tail_lines" "$file" 2>/dev/null | tac 2>/dev/null || true
    else
      tail -n "$tail_lines" "$file" 2>/dev/null | sed '1!G;h;$!d' || true
    fi
  )

  [[ -n "$state" ]] || return 0
  printf '%s\t%s\t%s\n' "$state" "$summary" "${updated:-$(now_epoch)}"
}

codex_state_from_pane() {
  local pane="$1" capture lowered updated

  [[ -n "$pane" ]] || return 0
  capture="$("$tmux_bin" capture-pane -pJ -S -16 -t "$pane" 2>/dev/null | sed '/^[[:space:]]*$/d' | tail -n 8 || true)"
  [[ -n "$capture" ]] || return 0

  updated="$(now_epoch)"
  lowered="${capture,,}"
  case "$lowered" in
    *"esc to interrupt"* | *"working ("*)
      printf 'running\tworking\t%s\n' "$updated"
      ;;
    *"› "*)
      printf 'idle\tready\t%s\n' "$updated"
      ;;
  esac
}

sync_agent_states() {
  local session="${1:-}" stamp now last throttle window pane file state summary updated
  local current_state current_summary current_updated current_scan rescan_after needs_scan changed=0
  local file_sig current_sig pane_state pane_summary pane_updated

  [[ -n "$session" ]] || session="$(current_session 2>/dev/null || true)"
  [[ -n "$session" ]] || return 0

  throttle="$(sync_interval_ms)"
  ensure_sync_dir
  stamp="$sync_dir/$(safe_key "$session").stamp"
  now="$(now_millis)"
  last="$(cat "$stamp" 2>/dev/null || printf '0')"
  if [[ "$last" =~ ^[0-9]+$ ]] && ((now - last < throttle)); then
    return 0
  fi
  printf '%s\n' "$now" > "$stamp" 2>/dev/null || true

  while IFS=$'\t' read -r window pane current_state current_summary current_updated file current_scan current_sig; do
    [[ -n "$window" && -n "$pane" ]] || continue
    pane_exists "$pane" || continue

    rescan_after="${WORKBENCH_SESSION_RESCAN_SECS:-3}"
    needs_scan=0
    if [[ -z "$file" || ! -f "$file" || ! "$current_scan" =~ ^[0-9]+$ ]]; then
      needs_scan=1
    elif ((now / 1000 - current_scan >= rescan_after)); then
      needs_scan=1
    fi
    if ((needs_scan)); then
      file="$(codex_session_for_pane "$pane" || true)"
      [[ -n "$file" ]] && set_window_option "$window" @agent-session-scan "$((now / 1000))"
    fi
    if [[ -z "$file" ]]; then
      if [[ "${current_state:-}" == running || "${current_state:-}" == done || "${current_state:-}" == idle || -z "${current_state:-}" ]]; then
        IFS=$'\t' read -r state summary updated < <(codex_state_from_pane "$pane")
        if [[ -n "$state" && "$state" != "$current_state" ]]; then
          set_window_option "$window" @agent-state "$state"
          set_window_option "$window" @agent-summary "$summary"
          set_window_option "$window" @agent-updated "$updated"
          changed=1
        fi
      fi
      continue
    fi

    file_sig="$(stat -c '%Y:%s' "$file" 2>/dev/null || true)"
    if [[ -n "$file_sig" && "$file_sig" == "$current_sig" && -n "$current_state" && -n "$current_updated" ]]; then
      if [[ "$current_state" == done || "$current_state" == idle || "$current_state" == ready ]]; then
        IFS=$'\t' read -r state summary updated < <(codex_state_from_pane "$pane")
        if [[ "$state" == running && "$state" != "$current_state" ]]; then
          set_window_option "$window" @agent-state "$state"
          set_window_option "$window" @agent-summary "$summary"
          set_window_option "$window" @agent-updated "$updated"
          changed=1
        fi
      fi
      continue
    fi

    IFS=$'\t' read -r state summary updated < <(codex_state_from_session "$file")
    [[ -n "$state" ]] || continue
    if [[ "$state" == done || "$state" == idle || "$state" == ready ]]; then
      IFS=$'\t' read -r pane_state pane_summary pane_updated < <(codex_state_from_pane "$pane")
      if [[ "$pane_state" == running ]]; then
        state="$pane_state"
        summary="$pane_summary"
        updated="$pane_updated"
      fi
    fi

    if [[ "$state" == "$current_state" && "$summary" == "$current_summary" && "$updated" == "$current_updated" && "$file_sig" == "$current_sig" ]]; then
      continue
    fi

    set_window_option "$window" @agent-state "$state"
    set_window_option "$window" @agent-summary "$summary"
    set_window_option "$window" @agent-updated "$updated"
    set_window_option "$window" @agent-session-file "$file"
    [[ -n "$file_sig" ]] && set_window_option "$window" @agent-session-sig "$file_sig"

    case "$state" in
      waiting | blocked | done)
        capture_preview "$pane" "$window"
        ;;
    esac
    changed=1
  done < <("$tmux_bin" list-windows -t "$session" -F '#{window_id}	#{@agent-pane}	#{@agent-state}	#{@agent-summary}	#{@agent-updated}	#{@agent-session-file}	#{@agent-session-scan}	#{@agent-session-sig}' 2>/dev/null || true)

  if ((changed)); then
    bump_event "$session"
    "$tmux_bin" refresh-client -S 2>/dev/null || true
  fi
}

sync_all_agent_states() {
  local session

  "$tmux_bin" list-sessions -F '#{session_name}' 2>/dev/null |
    while IFS= read -r session; do
      [[ -n "$session" ]] || continue
      is_workbench_helper_session "$session" && continue
      sync_agent_states "$session" >/dev/null 2>&1 || true
    done
}

terminal_session_name() {
  local session="$1"

  printf '%s-terms\n' "$session"
}

workbench_session_for_context() {
  local session="$1" window="${2:-}" owner

  if is_workbench_helper_session "$session"; then
    if [[ -n "$window" ]]; then
      owner="$(window_option "$window" @workbench-session)"
      if [[ -n "$owner" && "$owner" != @* && "$owner" != "$session" ]]; then
        printf '%s\n' "$owner"
        return 0
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

set_roles_for_new_window() {
  local window="$1" agent="$2" editor="$3"

  set_pane_option "$agent" @pane-role agent
  set_pane_option "$editor" @pane-role editor

  set_pane_option "$agent" @workbench-window "$window"
  set_pane_option "$editor" @workbench-window "$window"

  set_window_option "$window" @agent-pane "$agent"
  set_window_option "$window" @editor-pane "$editor"
  set_window_option "$window" @focus-pane "$agent"
  set_window_option "$window" @parked-primary-pane "$editor"
  set_window_option "$window" @primary agent
}

create_parked_editor() {
  local window="$1" root name park_session park_name park_window pane

  root="$(window_option "$window" @task-root)"
  [[ -n "$root" && -d "$root" ]] || return 1

  name="$(window_option "$window" @task-name)"
  park_session="${WORKBENCH_PARK_SESSION:-__workbench-park}"
  park_name="$(safe_key "park-${window#@}-${name:-editor}")"

  if "$tmux_bin" has-session -t "$park_session" 2>/dev/null; then
    park_window="$("$tmux_bin" new-window -d -P -F '#{window_id}' -t "$park_session:" -n "$park_name" -c "$root" 'nvim .')"
  else
    park_window="$("$tmux_bin" new-session -d -P -F '#{window_id}' -s "$park_session" -n "$park_name" -c "$root" 'nvim .')"
  fi

  pane="$("$tmux_bin" list-panes -t "$park_window" -F '#{pane_id}' | head -n 1)"
  set_pane_option "$pane" @pane-role editor
  set_pane_option "$pane" @workbench-window "$window"

  set_window_option "$window" @park-session "$park_session"
  set_window_option "$window" @park-window "$park_window"
  set_window_option "$window" @editor-pane "$pane"
  set_window_option "$window" @parked-primary-pane "$pane"
  set_window_option "$park_window" @parked-for "$window"

  printf '%s\n' "$pane"
}

create_parked_agent() {
  local window="$1" root name park_session park_name park_window pane

  root="$(window_option "$window" @task-root)"
  [[ -n "$root" && -d "$root" ]] || return 1

  name="$(window_option "$window" @task-name)"
  park_session="${WORKBENCH_PARK_SESSION:-__workbench-park}"
  park_name="$(safe_key "park-${window#@}-${name:-agent}")"

  if "$tmux_bin" has-session -t "$park_session" 2>/dev/null; then
    park_window="$("$tmux_bin" new-window -d -P -F '#{window_id}' -t "$park_session:" -n "$park_name" -c "$root")"
  else
    park_window="$("$tmux_bin" new-session -d -P -F '#{window_id}' -s "$park_session" -n "$park_name" -c "$root")"
  fi

  pane="$("$tmux_bin" list-panes -t "$park_window" -F '#{pane_id}' | head -n 1)"
  set_pane_option "$pane" @pane-role agent
  set_pane_option "$pane" @workbench-window "$window"

  set_window_option "$window" @park-session "$park_session"
  set_window_option "$window" @park-window "$park_window"
  set_window_option "$window" @agent-pane "$pane"
  set_window_option "$window" @parked-primary-pane "$pane"
  set_window_option "$park_window" @parked-for "$window"

  "$tmux_bin" send-keys -t "$pane" "$agent_cmd" Enter
  printf '%s\n' "$pane"
}

ensure_agent_pane() {
  local window="$1" agent park_window

  agent="$(window_option "$window" @agent-pane)"
  if [[ -n "$agent" ]] && pane_exists "$agent"; then
    heal_workbench_pane "$agent" "$window" agent
    printf '%s\n' "$agent"
    return 0
  fi

  park_window="$(window_option "$window" @park-window)"
  if [[ -n "$park_window" ]] && window_exists "$park_window"; then
    "$tmux_bin" kill-window -t "$park_window" 2>/dev/null || true
  fi

  create_parked_agent "$window"
}

ensure_editor_pane() {
  local window="$1" editor park_window

  editor="$(window_option "$window" @editor-pane)"
  if [[ -n "$editor" ]] && pane_exists "$editor"; then
    heal_workbench_pane "$editor" "$window" editor
    printf '%s\n' "$editor"
    return 0
  fi

  park_window="$(window_option "$window" @park-window)"
  if [[ -n "$park_window" ]] && window_exists "$park_window"; then
    "$tmux_bin" kill-window -t "$park_window" 2>/dev/null || true
  fi

  create_parked_editor "$window"
}

window_exists() {
  local window="$1" resolved

  [[ -n "$window" ]] || return 1
  resolved="$("$tmux_bin" display -p -t "$window" '#{window_id}' 2>/dev/null || true)"
  [[ -n "$resolved" && "$resolved" == "$window" ]]
}

window_index() {
  local window="$1"

  [[ -n "$window" ]] || return 1
  "$tmux_bin" display -p -t "$window" '#{window_index}' 2>/dev/null || true
}

window_at_index() {
  local session="$1" index="$2"

  [[ -n "$session" && -n "$index" ]] || return 1
  "$tmux_bin" list-windows -t "$session" -F '#{window_index}	#{window_id}' 2>/dev/null |
    awk -F '\t' -v wanted_index="$index" '$1 == wanted_index { print $2; exit }'
}

mark_paired_terminal_window() {
  local term_window="$1" workbench_session="$2" workbench_window="$3" root="$4" pane

  unset_window_option "$term_window" @task-name
  unset_window_option "$term_window" @task-root
  unset_window_option "$term_window" @agent-pane
  unset_window_option "$term_window" @editor-pane
  unset_window_option "$term_window" @focus-pane
  unset_window_option "$term_window" @parked-primary-pane
  unset_window_option "$term_window" @primary
  unset_window_option "$term_window" @park-session
  unset_window_option "$term_window" @park-window
  unset_window_option "$term_window" @parked-for
  unset_window_option "$term_window" @term-session
  unset_window_option "$term_window" @term-window
  unset_window_option "$term_window" @agent-state
  unset_window_option "$term_window" @agent-summary
  unset_window_option "$term_window" @agent-updated
  set_window_option "$term_window" @paired-terminal 1
  set_window_option "$term_window" @workbench-session "$workbench_session"
  set_window_option "$term_window" @workbench-window "$workbench_window"
  set_window_option "$term_window" @term-root "$root"

  while IFS= read -r pane; do
    [[ -n "$pane" ]] || continue
    set_pane_option "$pane" @pane-role terminal
    set_pane_option "$pane" @workbench-window "$workbench_window"
  done < <("$tmux_bin" list-panes -t "$term_window" -F '#{pane_id}' 2>/dev/null || true)
}

find_paired_terminal_window() {
  local term_session="$1" workbench_window="$2" window paired paired_for

  while IFS=$'\t' read -r window paired paired_for; do
    [[ "$paired" == 1 && "$paired_for" == "$workbench_window" ]] || continue
    is_workbench_window "$window" && continue
    printf '%s\n' "$window"
    return 0
  done < <("$tmux_bin" list-windows -t "$term_session" -F '#{window_id}	#{@paired-terminal}	#{@workbench-window}' 2>/dev/null || true)
}

sync_terminal_window_index() {
  local workbench_window="$1" term_session="$2" term_window="$3"
  local target_index term_index occupant

  [[ -n "$workbench_window" && -n "$term_session" && -n "$term_window" ]] || return 0
  window_exists "$workbench_window" || return 0
  window_exists "$term_window" || return 0

  target_index="$(window_index "$workbench_window")"
  term_index="$(window_index "$term_window")"
  [[ -n "$target_index" && -n "$term_index" && "$target_index" != "$term_index" ]] || return 0

  occupant="$(window_at_index "$term_session" "$target_index")"
  if [[ -n "$occupant" && "$occupant" != "$term_window" ]]; then
    "$tmux_bin" swap-window -d -s "$term_window" -t "$occupant" 2>/dev/null || true
  else
    "$tmux_bin" move-window -d -s "$term_window" -t "$term_session:$target_index" 2>/dev/null || true
  fi
}

sync_paired_terminal_index() {
  local window="${1:-}" session root term_session term_window paired_for

  [[ -n "$window" ]] || window="$(current_window)"
  window_exists "$window" || return 0

  is_workbench_window "$window" || return 0
  heal_workbench_window "$window"
  root="$(window_task_root "$window")"

  session="$("$tmux_bin" display -p -t "$window" '#{session_name}' 2>/dev/null || true)"
  is_workbench_helper_session "$session" && return 0

  term_session="$(window_option "$window" @term-session)"
  if ! valid_terminal_session_name "$session" "$term_session"; then
    term_session="$(terminal_session_name "$session")"
    set_window_option "$window" @term-session "$term_session"
  fi
  term_window="$(window_option "$window" @term-window)"

  if ! is_paired_terminal_window_for "$term_window" "$window"; then
    unset_window_option "$window" @term-window
    term_window="$(ensure_paired_terminal_window "$window" || true)"
  fi
  [[ -n "$term_window" ]] || return 0

  paired_for="$(window_option "$term_window" @workbench-window)"
  [[ "$paired_for" == "$window" ]] || return 0
  sync_terminal_window_index "$window" "$term_session" "$term_window"
}

sync_paired_terminal_indexes() {
  local session="${1:-}" window root

  [[ -n "$session" ]] || session="$(current_session 2>/dev/null || true)"
  [[ -n "$session" ]] || return 0
  is_workbench_helper_session "$session" && return 0

  "$tmux_bin" list-windows -t "$session" -F '#{window_id}	#{@task-root}' 2>/dev/null |
    while IFS=$'\t' read -r window root; do
      [[ -n "$window" && -n "$root" && -d "$root" ]] || continue
      sync_paired_terminal_index "$window" >/dev/null 2>&1 || true
    done
}

ensure_paired_terminal_window() {
  local window="$1" session name root term_session term_window existing paired_for

  session="$("$tmux_bin" display -p -t "$window" '#{session_name}' 2>/dev/null || true)"
  name="$(window_option "$window" @task-name)"
  root="$(window_task_root "$window" || true)"
  [[ -n "$session" && -n "$name" && -n "$root" ]] || return 1
  if is_workbench_helper_session "$session"; then
    unset_window_option "$window" @term-session
    unset_window_option "$window" @term-window
    return 1
  fi

  term_session="$(window_option "$window" @term-session)"
  if ! valid_terminal_session_name "$session" "$term_session"; then
    term_session="$(terminal_session_name "$session")"
    set_window_option "$window" @term-session "$term_session"
  fi

  term_window="$(window_option "$window" @term-window)"
  if is_paired_terminal_window_for "$term_window" "$window"; then
    mark_paired_terminal_window "$term_window" "$session" "$window" "$root"
    sync_terminal_window_index "$window" "$term_session" "$term_window"
    printf '%s\n' "$term_window"
    return
  fi
  [[ -n "$term_window" ]] && set_window_option "$window" @term-window ""

  if "$tmux_bin" has-session -t "$term_session" 2>/dev/null; then
    existing="$(find_paired_terminal_window "$term_session" "$window")"
    if [[ -n "$existing" ]]; then
      mark_paired_terminal_window "$existing" "$session" "$window" "$root"
      set_window_option "$window" @term-session "$term_session"
      set_window_option "$window" @term-window "$existing"
      sync_terminal_window_index "$window" "$term_session" "$existing"
      printf '%s\n' "$existing"
      return
    fi
    term_window="$("$tmux_bin" new-window -d -P -F '#{window_id}' -t "$term_session:" -n "$name" -c "$root")"
  else
    if ! term_window="$("$tmux_bin" new-session -d -P -F '#{window_id}' -s "$term_session" -n "$name" -c "$root" 2>/dev/null)"; then
      term_window="$("$tmux_bin" new-window -d -P -F '#{window_id}' -t "$term_session:" -n "$name" -c "$root")"
    fi
  fi

  mark_paired_terminal_window "$term_window" "$session" "$window" "$root"
  set_window_option "$window" @term-session "$term_session"
  set_window_option "$window" @term-window "$term_window"
  sync_terminal_window_index "$window" "$term_session" "$term_window"
  printf '%s\n' "$term_window"
}

pane_matches_workbench_role() {
  local role="$1" command="$2" pane_role="${3:-}"

  case "$role" in
    agent)
      [[ "$command" == codex || "$command" == codex-raw || "$pane_role" == agent ]]
      ;;
    editor)
      [[ "$command" == nvim || "$pane_role" == editor ]]
      ;;
    *)
      return 1
      ;;
  esac
}

primary_workbench_pane_for_window() {
  local window="$1" pane command path role

  "$tmux_bin" list-panes -t "$window" -F '#{pane_id}	#{pane_current_command}	#{pane_current_path}	#{@pane-role}' 2>/dev/null |
    while IFS=$'\t' read -r pane command path role; do
      [[ -n "$pane" && -n "$path" && -d "$path" ]] || continue
      if pane_matches_workbench_role agent "$command" "$role"; then
        printf 'agent\t%s\t%s\n' "$pane" "$path"
        return 0
      fi
      if pane_matches_workbench_role editor "$command" "$role"; then
        printf 'editor\t%s\t%s\n' "$pane" "$path"
        return 0
      fi
    done
}

find_parked_pane_for_window() {
  local workbench_window="$1" task_name="$2" root="$3" wanted_role="$4"
  local park_session park_window window_name parked_for pane command path role owner

  park_session="${WORKBENCH_PARK_SESSION:-__workbench-park}"
  "$tmux_bin" has-session -t "$park_session" 2>/dev/null || return 0

  "$tmux_bin" list-windows -t "$park_session" -F '#{window_id}	#{window_name}	#{@parked-for}' 2>/dev/null |
    while IFS=$'\t' read -r park_window window_name parked_for; do
      [[ -n "$park_window" ]] || continue
      IFS=$'\t' read -r pane command path role owner < <(
        "$tmux_bin" list-panes -t "$park_window" -F '#{pane_id}	#{pane_current_command}	#{pane_current_path}	#{@pane-role}	#{@workbench-window}' 2>/dev/null |
          head -n 1
      )
      [[ -n "$pane" && -n "$path" && -d "$path" ]] || continue
      pane_matches_workbench_role "$wanted_role" "$command" "$role" || continue

      if [[ "$parked_for" == "$workbench_window" || "$owner" == "$workbench_window" ]]; then
        printf '%s\t%s\n' "$park_window" "$pane"
        return 0
      fi

      [[ "$path" == "$root" ]] || continue
      case "$window_name" in
        park-*-"$task_name")
          printf '%s\t%s\n' "$park_window" "$pane"
          return 0
          ;;
      esac
    done
}

find_terminal_window_for_workbench() {
  local session="$1" window="$2" term_session="$3"
  local index name candidate candidate_name

  "$tmux_bin" has-session -t "$term_session" 2>/dev/null || return 0

  candidate="$(find_paired_terminal_window "$term_session" "$window")"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  index="$(window_index "$window")"
  candidate="$(window_at_index "$term_session" "$index" || true)"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  name="$("$tmux_bin" display -p -t "$window" '#{window_name}' 2>/dev/null || true)"
  "$tmux_bin" list-windows -t "$term_session" -F '#{window_id}	#{window_name}' 2>/dev/null |
    while IFS=$'\t' read -r candidate candidate_name; do
      [[ -n "$candidate" && "$candidate_name" == "$name" ]] || continue
      printf '%s\n' "$candidate"
      return 0
    done
}

recover_restored_window() {
  local window="$1" session task_name primary_record primary_role primary_pane root
  local agent_pane editor_pane parked_record park_window parked_pane term_session term_window

  window_exists "$window" || return 0
  session="$("$tmux_bin" display -p -t "$window" '#{session_name}' 2>/dev/null || true)"
  [[ -n "$session" ]] || return 0
  is_workbench_helper_session "$session" && return 0

  primary_record="$(primary_workbench_pane_for_window "$window" | head -n 1)"
  [[ -n "$primary_record" ]] || return 0
  IFS=$'\t' read -r primary_role primary_pane root <<<"$primary_record"
  [[ -n "$primary_role" && -n "$primary_pane" && -n "$root" && -d "$root" ]] || return 0

  task_name="$(window_option "$window" @task-name)"
  [[ -n "$task_name" ]] || task_name="$("$tmux_bin" display -p -t "$window" '#{window_name}' 2>/dev/null || true)"
  [[ -n "$task_name" ]] || task_name="$(project_name "$root")"

  set_window_option "$window" @task-name "$task_name"
  set_window_option "$window" @task-root "$root"
  set_window_option "$window" @focus-pane "$primary_pane"
  set_window_option "$window" @primary "$primary_role"
  [[ -n "$(window_option "$window" @agent-state)" ]] || set_window_option "$window" @agent-state idle
  [[ -n "$(window_option "$window" @agent-summary)" ]] || set_window_option "$window" @agent-summary ready
  [[ -n "$(window_option "$window" @agent-updated)" ]] || set_window_option "$window" @agent-updated "$(now_epoch)"

  unset_window_option "$window" @paired-terminal
  unset_window_option "$window" @workbench-session
  unset_window_option "$window" @workbench-window
  unset_window_option "$window" @term-root
  unset_window_option "$window" @parked-for

  if [[ "$primary_role" == agent ]]; then
    agent_pane="$primary_pane"
    set_window_option "$window" @agent-pane "$agent_pane"
    set_pane_option "$agent_pane" @pane-role agent
    set_pane_option "$agent_pane" @workbench-window "$window"

    parked_record="$(find_parked_pane_for_window "$window" "$task_name" "$root" editor | head -n 1)"
    if [[ -n "$parked_record" ]]; then
      IFS=$'\t' read -r park_window parked_pane <<<"$parked_record"
      editor_pane="$parked_pane"
      set_window_option "$window" @editor-pane "$editor_pane"
      set_window_option "$window" @parked-primary-pane "$editor_pane"
    fi
  else
    editor_pane="$primary_pane"
    set_window_option "$window" @editor-pane "$editor_pane"
    set_pane_option "$editor_pane" @pane-role editor
    set_pane_option "$editor_pane" @workbench-window "$window"

    parked_record="$(find_parked_pane_for_window "$window" "$task_name" "$root" agent | head -n 1)"
    if [[ -n "$parked_record" ]]; then
      IFS=$'\t' read -r park_window parked_pane <<<"$parked_record"
      agent_pane="$parked_pane"
      set_window_option "$window" @agent-pane "$agent_pane"
      set_window_option "$window" @parked-primary-pane "$agent_pane"
    fi
  fi

  if [[ -n "${park_window:-}" && -n "${parked_pane:-}" ]]; then
    set_window_option "$window" @park-session "${WORKBENCH_PARK_SESSION:-__workbench-park}"
    set_window_option "$window" @park-window "$park_window"
    set_window_option "$park_window" @parked-for "$window"
    set_pane_option "$parked_pane" @pane-role "$([[ "$primary_role" == agent ]] && printf editor || printf agent)"
    set_pane_option "$parked_pane" @workbench-window "$window"
  fi

  term_session="$(terminal_session_name "$session")"
  set_window_option "$window" @term-session "$term_session"
  term_window="$(find_terminal_window_for_workbench "$session" "$window" "$term_session" | head -n 1)"
  if [[ -n "$term_window" && "$term_window" != "$window" ]]; then
    mark_paired_terminal_window "$term_window" "$session" "$window" "$root"
    set_window_option "$window" @term-window "$term_window"
    sync_terminal_window_index "$window" "$term_session" "$term_window"
  else
    unset_window_option "$window" @term-window
  fi
}

recover_restored_workbench() {
  local window

  "$tmux_bin" list-windows -a -F '#{window_id}' 2>/dev/null |
    while IFS= read -r window; do
      [[ -n "$window" ]] || continue
      recover_restored_window "$window" >/dev/null 2>&1 || true
    done
}

paired_terminal_spawn() {
  local window current root cwd new_pane

  window="$(current_window)"
  is_paired_terminal_window "$window" || return 1
  root="$(window_option "$window" @term-root)"
  mark_paired_terminal_window \
    "$window" \
    "$(window_option "$window" @workbench-session)" \
    "$(window_option "$window" @workbench-window)" \
    "$root"

  current="$(current_pane)"
  cwd="$(pane_cwd "$current" "${root:-$home_dir}")"
  new_pane="$("$tmux_bin" split-window -c "$cwd" -t "$current" -P -F '#{pane_id}')"
  set_pane_option "$new_pane" @pane-role terminal
  set_pane_option "$new_pane" @workbench-window "$(window_option "$window" @workbench-window)"
  "$tmux_bin" select-layout -t "$window" tiled >/dev/null 2>&1 || true
}

paired_terminal_close() {
  local window current count

  window="$(current_window)"
  is_paired_terminal_window "$window" || return 1

  count="$("$tmux_bin" list-panes -t "$window" 2>/dev/null | wc -l | tr -d ' ')"
  ((count > 1)) || return 0
  current="$(current_pane)"
  "$tmux_bin" kill-pane -t "$current" 2>/dev/null || return 0
  "$tmux_bin" select-layout -t "$window" tiled >/dev/null 2>&1 || true
}

paired_terminal_layout() {
  local window

  window="$(current_window)"
  is_paired_terminal_window "$window" || return 1
  "$tmux_bin" select-layout -t "$window" tiled >/dev/null 2>&1 || true
}

kill_windows_with_option() {
  local option="$1" value="$2" window opt_value

  [[ -n "$option" && -n "$value" ]] || return 0
  "$tmux_bin" list-windows -a -F '#{window_id}	#{'"$option"'}' 2>/dev/null |
    while IFS=$'\t' read -r window opt_value; do
      [[ -n "$window" && "$opt_value" == "$value" ]] || continue
      "$tmux_bin" kill-window -t "$window" 2>/dev/null || true
    done
}

kill_window_if_exists() {
  local window="$1"

  [[ -n "$window" ]] || return 0
  window_exists "$window" || return 0
  "$tmux_bin" kill-window -t "$window" 2>/dev/null || true
}

terminal_toggle() {
  local window

  window="$(current_window)"
  if is_workbench_window "$window"; then
    heal_workbench_window "$window"
    switch_to_paired_terminal "$window"
    return
  fi

  if is_paired_terminal_window "$window"; then
    paired_terminal_spawn
    return
  fi

  return 1
}

switch_to_paired_terminal() {
  local window="$1" term_window term_session

  is_workbench_window "$window" || return 0
  heal_workbench_window "$window"
  term_window="$(ensure_paired_terminal_window "$window")"
  [[ -n "$term_window" ]] || return 0
  term_session="$(window_option "$window" @term-session)"
  "$tmux_bin" switch-client -t "$term_session" 2>/dev/null || true
  "$tmux_bin" select-window -t "$term_window" 2>/dev/null || true
}

pair_toggle() {
  local window workbench_window workbench_session

  window="$(current_window)"
  if is_workbench_window "$window"; then
    heal_workbench_window "$window"
    switch_to_paired_terminal "$window"
    return 0
  fi

  if is_paired_terminal_window "$window"; then
    mark_paired_terminal_window \
      "$window" \
      "$(window_option "$window" @workbench-session)" \
      "$(window_option "$window" @workbench-window)" \
      "$(window_option "$window" @term-root)"
    workbench_window="$(window_option "$window" @workbench-window)"
    workbench_session="$(window_option "$window" @workbench-session)"
    [[ -n "$workbench_window" && -n "$workbench_session" ]] || return 0
    "$tmux_bin" switch-client -t "$workbench_session" 2>/dev/null || true
    "$tmux_bin" select-window -t "$workbench_window" 2>/dev/null || true
    show_primary "$workbench_window" agent || true
    return 0
  fi

  return 0
}

layout_window() {
  local window="${1:-}" agent editor

  [[ -n "$window" ]] || window="$(current_window)"
  is_workbench_window "$window" || return 0
  heal_workbench_window "$window"

  agent="$(window_option "$window" @agent-pane)"
  editor="$(window_option "$window" @editor-pane)"
  [[ -n "$agent" && -n "$editor" ]] || return 0
  if pane_in_window "$agent" "$window"; then
    "$tmux_bin" select-pane -t "$agent" 2>/dev/null || true
  elif pane_in_window "$editor" "$window"; then
    "$tmux_bin" select-pane -t "$editor" 2>/dev/null || true
  fi
}

create_window() {
  local session="${1:-}" name="${2:-}" root="${3:-}" mode="${4:-reuse}"
  local existing window agent editor

  [[ -n "$session" && -n "$name" && -n "$root" ]] || fail "usage: workbench.sh create SESSION NAME ROOT"
  is_workbench_helper_session "$session" && fail "refusing to create workbench window in helper session: $session"
  root="$(realpath -m "$root")"
  [[ -d "$root" ]] || fail "not a directory: $root"

  if "$tmux_bin" has-session -t "$session" 2>/dev/null; then
    if [[ "$mode" == reuse ]]; then
      existing="$(find_window_by_root "$session" "$root" "$name" | head -n 1)"
      if [[ -n "$existing" ]]; then
        select_window "$session" "$existing"
        return 0
      fi
    fi
    window="$("$tmux_bin" new-window -d -P -F '#{window_id}' -t "$session:" -n "$name" -c "$root")"
  else
    window="$("$tmux_bin" new-session -d -P -F '#{window_id}' -s "$session" -n "$name" -c "$root")"
  fi

  agent="$("$tmux_bin" list-panes -t "$window" -F '#{pane_id}' | head -n 1)"

  set_window_option "$window" @task-name "$name"
  set_window_option "$window" @task-root "$root"
  set_window_option "$window" @agent-state idle
  set_window_option "$window" @agent-summary "ready"
  set_window_option "$window" @agent-updated "$(now_epoch)"

  editor="$(create_parked_editor "$window")"
  set_roles_for_new_window "$window" "$agent" "$editor"
  ensure_paired_terminal_window "$window" >/dev/null

  "$tmux_bin" send-keys -t "$agent" "$agent_cmd" Enter
  layout_window "$window" || true
  bump_window_event "$window"
  "$tmux_bin" select-pane -t "$agent"
  select_window "$session" "$window"
}

new_current_window() {
  local pane window session cwd root name

  pane="$(current_pane)"
  window="$("$tmux_bin" display -p -t "$pane" '#{window_id}')"
  session="$("$tmux_bin" display -p -t "$pane" '#{session_name}')"
  session="$(workbench_session_for_context "$session" "$window")"
  cwd="$("$tmux_bin" display -p -t "$pane" '#{pane_current_path}')"
  root="$(project_root_for_path "$cwd")"
  name="$(unique_window_name "$session" "$(project_name "$root")")"

  create_window "$session" "$name" "$root" fresh
}

main_workspace() {
  local session="${1:-${TMUX_AGENT_MAIN_SESSION:-main}}" pane cwd root name window

  if "$tmux_bin" has-session -t "$session" 2>/dev/null; then
    window="$(first_workbench_window "$session")"
    if [[ -n "$window" ]]; then
      select_window "$session" "$window"
      show_primary "$window" agent || true
      return 0
    fi
  fi

  pane="$(current_pane 2>/dev/null || true)"
  if [[ -n "$pane" ]] && pane_exists "$pane"; then
    cwd="$("$tmux_bin" display -p -t "$pane" '#{pane_current_path}' 2>/dev/null || true)"
  fi
  cwd="${cwd:-$home_dir}"
  root="$(project_root_for_path "$cwd")"
  name="$(unique_window_name "$session" "$(project_name "$root")")"

  create_window "$session" "$name" "$root" reuse
}

toggle_primary() {
  local desired="${1:-}" window

  window="$(current_window)"
  heal_workbench_window "$window"
  show_primary "$window" "$desired"
}

show_primary() {
  local window="$1" desired="${2:-}" root current agent editor target target_role parked primary selected
  local swapped=0

  root="$(window_task_root "$window" || true)"
  [[ -n "$root" ]] || return 0
  heal_workbench_window "$window"

  case "$desired" in
    agent)
      agent="$(ensure_agent_pane "$window" || true)"
      [[ -n "$agent" ]] || return 0
      target="$agent"
      target_role=agent
      ;;
    editor)
      editor="$(ensure_editor_pane "$window" || true)"
      [[ -n "$editor" ]] || return 0
      target="$editor"
      target_role=editor
      ;;
    "")
      primary="$(window_option "$window" @primary)"
      if [[ "$primary" == editor ]]; then
        agent="$(ensure_agent_pane "$window" || true)"
        [[ -n "$agent" ]] || return 0
        target="$agent"
        target_role=agent
      else
        editor="$(ensure_editor_pane "$window" || true)"
        [[ -n "$editor" ]] || return 0
        target="$editor"
        target_role=editor
      fi
      ;;
    *) return 0 ;;
  esac

  if ! pane_in_window "$target" "$window"; then
    current="$(visible_primary_pane "$window")"
    [[ -n "$current" ]] || return 0
    parked="$(window_option "$window" @parked-primary-pane)"
    if [[ -z "$parked" || "$parked" != "$target" ]]; then
      parked="$target"
    fi
    pane_exists "$parked" || return 0
    "$tmux_bin" swap-pane -s "$current" -t "$parked" 2>/dev/null || return 0
    set_window_option "$window" @parked-primary-pane "$current"
    swapped=1
  fi

  set_window_option "$window" @focus-pane "$target"
  set_window_option "$window" @primary "$target_role"
  if ((swapped == 0)); then
    selected="$("$tmux_bin" display -p -t "$window" '#{pane_id}' 2>/dev/null || true)"
    [[ "$selected" == "$target" ]] || "$tmux_bin" select-pane -t "$target" 2>/dev/null || true
  fi
}

close_window() {
  local window="${1:-}" session park_window parked_for term_window paired_for preview_file

  [[ -n "$window" ]] || window="$(current_window)"
  [[ -n "$window" ]] || return 0
  "$tmux_bin" display -p -t "$window" '#{window_id}' >/dev/null 2>&1 || return 0

  paired_for="$(window_option "$window" @workbench-window)"
  if is_paired_terminal_window "$window" && [[ -n "$paired_for" ]]; then
    if window_exists "$paired_for"; then
      window="$paired_for"
    else
      "$tmux_bin" kill-window -t "$window" 2>/dev/null || true
      return 0
    fi
  fi

  parked_for="$(window_option "$window" @parked-for)"
  if [[ -n "$parked_for" ]]; then
    window="$parked_for"
    "$tmux_bin" display -p -t "$window" '#{window_id}' >/dev/null 2>&1 || return 0
  fi

  session="$("$tmux_bin" display -p -t "$window" '#{session_name}' 2>/dev/null || true)"
  park_window="$(window_option "$window" @park-window)"
  term_window="$(window_option "$window" @term-window)"
  preview_file="$(window_option "$window" @agent-preview-file)"

  kill_windows_with_option '@parked-for' "$window"
  [[ "$park_window" == "$window" ]] || kill_window_if_exists "$park_window"

  kill_windows_with_option '@workbench-window' "$window"
  [[ "$term_window" == "$window" ]] || kill_window_if_exists "$term_window"
  [[ -n "$preview_file" && "$preview_file" == "$preview_dir"/* ]] && rm -f "$preview_file" 2>/dev/null || true

  "$tmux_bin" kill-window -t "$window" 2>/dev/null || true
  bump_event "$session"
  "$tmux_bin" refresh-client -S 2>/dev/null || true
}

cleanup_orphaned_paired_terminals() {
  local window paired workbench_window

  "$tmux_bin" list-windows -a -F '#{window_id}	#{@paired-terminal}	#{@workbench-window}' 2>/dev/null |
    while IFS=$'\t' read -r window paired workbench_window; do
      [[ "$paired" == 1 && -n "$workbench_window" ]] || continue
      window_exists "$workbench_window" && continue
      "$tmux_bin" kill-window -t "$window" 2>/dev/null || true
    done
}

cleanup_orphaned_parked_windows() {
  local window parked_for

  "$tmux_bin" list-windows -a -F '#{window_id}	#{@parked-for}' 2>/dev/null |
    while IFS=$'\t' read -r window parked_for; do
      [[ -n "$parked_for" ]] || continue
      window_exists "$parked_for" && continue
      "$tmux_bin" kill-window -t "$window" 2>/dev/null || true
    done
}

cleanup_orphans() {
  cleanup_orphaned_paired_terminals
  cleanup_orphaned_parked_windows
}

state_priority() {
  case "$1" in
    waiting | needs-input) printf '10' ;;
    blocked | error) printf '20' ;;
    done) printf '30' ;;
    running | busy) printf '40' ;;
    *) printf '90' ;;
  esac
}

next_agent() {
  local session current target

  session="$(current_session)"
  current="$(current_window)"

  target="$(
    "$tmux_bin" list-windows -t "$session" -F '#{window_id}	#{@agent-state}	#{@agent-pane}' |
      while IFS=$'\t' read -r window state pane; do
        [[ -n "$pane" ]] || continue
        state="${state:-idle}"
        case "$state" in
          waiting | needs-input | blocked | error | done)
            printf '%s\t%s\t%s\n' "$(state_priority "$state")" "$window" "$state"
            ;;
        esac
      done |
      sort -n |
      awk -F '\t' -v current="$current" '$2 != current { print $2; exit } END { }'
  )"

  if [[ -z "$target" ]]; then
    target="$(
      "$tmux_bin" list-windows -t "$session" -F '#{window_id}	#{@agent-state}	#{@agent-pane}' |
        while IFS=$'\t' read -r window state pane; do
          [[ -n "$pane" ]] || continue
          state="${state:-idle}"
          case "$state" in
            waiting | needs-input | blocked | error | done)
              printf '%s\t%s\n' "$(state_priority "$state")" "$window"
              ;;
          esac
        done |
        sort -n |
        awk -F '\t' 'NR == 1 { print $2 }'
    )"
  fi

  [[ -n "$target" ]] || return 0
  "$tmux_bin" select-window -t "$target"
  show_primary "$target" agent || true
}

summary() {
  local session waiting=0 blocked=0 done=0 running=0 state pane

  session="$("$tmux_bin" display -p '#{session_name}' 2>/dev/null || true)"
  [[ -n "$session" ]] || return 0
  sync_agent_states "$session" >/dev/null 2>&1 || true

  while IFS=$'\t' read -r state pane; do
    [[ -n "$pane" ]] || continue
    case "${state:-idle}" in
      waiting | needs-input) waiting=$((waiting + 1)) ;;
      blocked | error) blocked=$((blocked + 1)) ;;
      done) done=$((done + 1)) ;;
      running | busy) running=$((running + 1)) ;;
    esac
  done < <("$tmux_bin" list-windows -t "$session" -F '#{@agent-state}	#{@agent-pane}' 2>/dev/null || true)

  if ((waiting + blocked + done + running > 0)); then
    printf 'A:'
    printf '#[fg=#d6a65d]%sW ' "$waiting"
    printf '#[fg=#ff5c57]%sB ' "$blocked"
    printf '#[fg=#9ece6a]%sD ' "$done"
    printf '#[fg=#5fb3c4]%sR' "$running"
  fi
}

status_sync() {
  local session

  session="${TMUX_WORKBENCH_SESSION:-}"
  [[ -n "$session" ]] || session="$(current_session 2>/dev/null || true)"
  [[ -n "$session" ]] || return 0

  WORKBENCH_SYNC_INTERVAL_MS="${WORKBENCH_STATUS_SYNC_INTERVAL_MS:-1000}" \
    sync_agent_states "$session" >/dev/null 2>&1 || true
}

cmd="${1:-}"
shift || true

case "$cmd" in
  create)
    create_window "$@"
    ;;
  new)
    new_current_window
    ;;
  main)
    main_workspace "${1:-}"
    ;;
  layout)
    layout_window "${1:-}"
    ;;
  toggle-primary)
    toggle_primary "${1:-}"
    ;;
  terminal-toggle)
    terminal_toggle
    ;;
  pair-toggle)
    pair_toggle
    ;;
  terminal-close)
    paired_terminal_close
    ;;
  terminal-layout)
    paired_terminal_layout
    ;;
  sync-paired-terminal-index)
    sync_paired_terminal_index "${1:-}"
    ;;
  sync-paired-terminals)
    sync_paired_terminal_indexes "${1:-}"
    ;;
  close-window)
    close_window "${1:-}"
    ;;
  cleanup)
    cleanup_orphans
    ;;
  next-agent)
    next_agent
    ;;
  sync)
    sync_agent_states "${1:-}"
    ;;
  sync-all)
    sync_all_agent_states
    ;;
  event)
    bump_event "${1:-$(current_session 2>/dev/null || true)}"
    "$tmux_bin" refresh-client -S 2>/dev/null || true
    ;;
  state)
    set_state "$@"
    ;;
  summary)
    summary
    ;;
  status-sync)
    status_sync
    ;;
  recover-restored)
    recover_restored_workbench
    ;;
  *)
    cat >&2 <<'EOF'
usage: workbench.sh COMMAND

commands:
  create SESSION NAME ROOT
  new
  main [SESSION]
  layout [WINDOW]
  toggle-primary [agent|editor]
  terminal-toggle
  pair-toggle
  terminal-close
  terminal-layout
  sync-paired-terminal-index [WINDOW]
  sync-paired-terminals [SESSION]
  close-window [WINDOW]
  cleanup
  next-agent
  sync [SESSION]
  sync-all
  event [SESSION]
  state STATE [summary]
  summary
  status-sync
  recover-restored
EOF
    exit 2
    ;;
esac
