#!/usr/bin/env bash

pane_count=$(tmux list-panes | wc -l)

if [ "$1" = "open" ]; then
	if [ "$pane_count" -eq 1 ]; then
		tmux split-window -h -c "#{pane_current_path}"
	else
		tmux split-window -v -c "#{pane_current_path}"
	fi
else
	tmux kill-pane
fi

# half_width=$(tmux display -t 0 -p '#{window_width}' | awk '{print int($1/2)}')
# tmux resize-pane -t 0 -x $half_width
tmux select-layout main-vertical
# tmux split-window -dhf ''
# tmux swap-pane -d -s {right} -t {left}
# tmux kill-pane -t {left}

# tmux rotate-window -D
# tmux select-pane -t {next}
# tmux select-layout main-vertical
# tmux split-window -dhf ''
# tmux swap-pane -d -s {right} -t {left}
# tmux kill-pane -t {left}
