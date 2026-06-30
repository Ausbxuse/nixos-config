#!/usr/bin/env bash
set -euo pipefail

tmux_bin="${TMUX_BIN:-tmux}"
resurrect_dir="${TMUX_RESURRECT_DIR:-$HOME/.local/share/tmux/resurrect}"
last_link="$resurrect_dir/last"
workbench_state="$resurrect_dir/workbench.tsv"

mkdir -p "$resurrect_dir"

normalize_resurrect_file() {
  local target tmp

  target="$(readlink -f "$last_link" 2>/dev/null || true)"
  [[ -n "$target" && -f "$target" ]] || return 0

  tmp="$(mktemp "$target.XXXXXX")"
  awk -F '\t' -v OFS='\t' '
    function filtered_session(session) {
      return session == "__workbench-park-terms" || session ~ /-terms-terms$/
    }

    ($1 == "pane" || $1 == "window") && filtered_session($2) {
      next
    }

    $1 == "grouped_session" && (filtered_session($2) || filtered_session($3)) {
      next
    }

    $1 == "state" && (filtered_session($2) || filtered_session($3)) {
      next
    }

    $1 == "pane" {
      pane_command = $10
      full_command = $11

      if (pane_command == "nvim" || full_command ~ /^:.*\/bin\/nvim([[:space:]]|$)/) {
        $11 = ":nvim ."
      } else if (pane_command == "codex" || pane_command == "codex-raw" || full_command ~ /^:.*\/bin\/codex([[:space:]]|$)/ || full_command ~ /^:.*\/bin\/codex-raw([[:space:]]|$)/) {
        $11 = ":codex"
      }
    }

    { print }
  ' "$target" > "$tmp"
  mv -f "$tmp" "$target"
}

save_workbench_state() {
  local tmp

  tmp="$(mktemp "$workbench_state.XXXXXX")"
  {
    printf 'version\t1\n'

    "$tmux_bin" list-windows -a -F 'window	#{session_name}	#{window_index}	#{window_id}	#{@task-name}	#{@task-root}	#{@agent-pane}	#{@editor-pane}	#{@focus-pane}	#{@parked-primary-pane}	#{@primary}	#{@park-session}	#{@park-window}	#{@parked-for}	#{@term-session}	#{@term-window}	#{@paired-terminal}	#{@workbench-session}	#{@workbench-window}	#{@term-root}	#{@agent-state}	#{@agent-summary}	#{@agent-updated}	#{@agent-session-file}	#{@agent-session-scan}	#{@agent-session-sig}	#{@agent-preview-file}	#{@agent-home-session}' 2>/dev/null |
      awk -F '\t' -v OFS='\t' '
        function filtered_session(session) {
          return session == "__workbench-park-terms" || session ~ /-terms-terms$/
        }

        filtered_session($2) {
          next
        }

        {
          has_option = 0
          for (i = 5; i <= NF; i++) {
            if ($i != "") {
              has_option = 1
              break
            }
          }
          if (has_option) {
            print
          }
        }
      '

    "$tmux_bin" list-panes -a -F 'pane	#{session_name}	#{window_index}	#{pane_index}	#{pane_id}	#{@pane-role}	#{@workbench-window}' 2>/dev/null |
      awk -F '\t' -v OFS='\t' '
        function filtered_session(session) {
          return session == "__workbench-park-terms" || session ~ /-terms-terms$/
        }

        !filtered_session($2) && ($6 != "" || $7 != "") {
          print
        }
      '
  } > "$tmp"

  mv -f "$tmp" "$workbench_state"
}

normalize_resurrect_file
save_workbench_state
