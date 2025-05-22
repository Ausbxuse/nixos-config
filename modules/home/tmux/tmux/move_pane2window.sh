#!/usr/bin/env bash

current=$(tmux display -p "#{window_index}")
target="$1"

# guard: if we're already in $target do nothing
if [ "$current" != "$target" ]; then
  if tmux list-windows | grep -q "^${target}:"; then
    tmux select-pane -m
    tmux join-pane -s "{marked}" -t ":${target}"
    tmux select-layout main-vertical
  else
    tmux break-pane -t "${target}"
  fi
fi
