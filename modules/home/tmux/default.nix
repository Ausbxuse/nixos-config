{
  pkgs,
  lib,
  ...
}: {
  programs.tmux = {
    enable = true;
  };

  home.packages = with pkgs; [
    lm_sensors
  ];

  xdg.configFile."tmux/theme-dark.conf".source = ./theme-dark.conf;
  xdg.configFile."tmux/theme-light.conf".source = ./theme-light.conf;
  home.file.".local/bin/tmux/agent-workflow.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      main_session="''${TMUX_AGENT_MAIN_SESSION:-main}"
      cmd="''${1:-}"

      current_session="$(tmux display -p '#{session_name}')"
      window_id="$(tmux display -p '#{window_id}')"

      project_name_for_path() {
        local path repo name

        path="$(tmux display -p '#{pane_current_path}')"
        repo=""
        if command -v git >/dev/null 2>&1; then
          repo="$(git -C "$path" rev-parse --show-toplevel 2>/dev/null || true)"
        fi

        name="$(basename "''${repo:-$path}")"
        printf '%s\n' "''${name//[.:]/_}"
      }

      unique_window_name() {
        local base candidate existing id n

        base="$1"
        candidate="$base"
        n=2

        while true; do
          existing=false
          while IFS='|' read -r id name; do
            if [[ "$id" != "$window_id" && "$name" == "$candidate" ]]; then
              existing=true
              break
            fi
          done < <(tmux list-windows -t "$main_session" -F '#{window_id}|#{window_name}' 2>/dev/null || true)

          if [[ "$existing" == false ]]; then
            printf '%s\n' "$candidate"
            return 0
          fi

          candidate="$base-$n"
          n=$((n + 1))
        done
      }

      ensure_main_session() {
        if ! tmux has-session -t "$main_session" 2>/dev/null; then
          tmux new-session -d -s "$main_session"
        fi
      }

      session_has_window() {
        tmux list-windows -t "$1" -F '#{window_id}' 2>/dev/null | grep -Fxq "$window_id"
      }

      find_linked_session() {
        local home_session
        home_session="$(tmux show-window-option -v @agent-home-session 2>/dev/null || true)"
        if [[ -n "$home_session" && "$home_session" != "$main_session" ]] && session_has_window "$home_session"; then
          printf '%s\n' "$home_session"
          return 0
        fi

        tmux list-sessions -F '#{session_name}' |
          while IFS= read -r session; do
            [[ "$session" == "$main_session" ]] && continue
            if session_has_window "$session"; then
              printf '%s\n' "$session"
              return 0
            fi
          done
      }

      case "$cmd" in
        link)
          if [[ "$current_session" == "$main_session" ]]; then
            exit 0
          fi

          ensure_main_session
          tmux set-window-option -q @agent-home-session "$current_session"
          tmux rename-window "$(unique_window_name "$(project_name_for_path)")"

          if ! session_has_window "$main_session"; then
            tmux link-window -d -s "$window_id" -t "$main_session:"
          fi

          tmux switch-client -t "$main_session"
          tmux select-window -t "$window_id"
          ;;
        jump)
          target_session="$(find_linked_session | head -n 1)"
          if [[ -z "''${target_session:-}" ]]; then
            exit 0
          fi

          tmux switch-client -t "$target_session"
          tmux select-window -t "$window_id"
          ;;
        unlink)
          if [[ "$current_session" != "$main_session" ]]; then
            exit 0
          fi

          target_session="$(find_linked_session | head -n 1)"
          if [[ -z "''${target_session:-}" ]]; then
            exit 0
          fi

          tmux unlink-window -t "$main_session:$window_id"
          ;;
        *)
          exit 2
          ;;
      esac
    '';
  };
  home.file.".local/bin/tmux/last-command.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      cmd="''${1:-copy}"
      max_lines="''${TMUX_LAST_COMMAND_LINES:-5000}"

      fail() {
        tmux display-message "$1"
        exit 1
      }

      log_dir_for_pane() {
        tmux display -p -t "$1" '#{@command-log-dir}' 2>/dev/null || true
      }

      pane_has_completed_command() {
        local dir
        dir="$(log_dir_for_pane "$1")"
        [[ -n "$dir" && -d "$dir" ]] || return 1

        for file in output.log cmd cwd start end status; do
          [[ -f "$dir/$file" ]] || return 1
        done
      }

      previous_pane() {
        local current previous

        current="$(tmux display -p '#{pane_id}')"
        tmux select-pane -l 2>/dev/null || return 1
        previous="$(tmux display -p '#{pane_id}')"
        tmux select-pane -t "$current"

        [[ "$previous" != "$current" ]] || return 1
        printf '%s\n' "$previous"
      }

      resolve_source_pane() {
        local current previous

        if [[ -n "''${TMUX_LAST_COMMAND_SOURCE:-}" ]]; then
          printf '%s\n' "$TMUX_LAST_COMMAND_SOURCE"
          return 0
        fi

        current="$(tmux display -p '#{pane_id}')"
        if pane_has_completed_command "$current"; then
          printf '%s\n' "$current"
          return 0
        fi

        previous="$(previous_pane || true)"
        if [[ -n "$previous" ]] && pane_has_completed_command "$previous"; then
          printf '%s\n' "$previous"
          return 0
        fi

        printf '%s\n' "$current"
      }

      source_pane="$(resolve_source_pane)"
      log_dir="$(log_dir_for_pane "$source_pane")"

      [[ -n "$log_dir" && -d "$log_dir" ]] || fail "No command log for $source_pane"

      for file in output.log cmd cwd start end status; do
        [[ -f "$log_dir/$file" ]] || fail "No completed command captured for $source_pane"
      done

      log_file="$log_dir/output.log"
      command_text="$(cat "$log_dir/cmd")"
      cwd="$(cat "$log_dir/cwd")"
      start="$(cat "$log_dir/start")"
      end="$(cat "$log_dir/end")"
      status="$(cat "$log_dir/status")"

      [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ && "$end" -ge "$start" ]] ||
        fail "Invalid command log offsets for $source_pane"

      tmp="$(mktemp)"
      trap 'rm -f "$tmp"' EXIT

      {
        printf 'Last command from tmux pane %s\n\n' "$source_pane"
        printf 'cwd: %s\n' "$cwd"
        printf 'exit status: %s\n\n' "$status"
        printf '```sh\n'
        printf '$ %s\n' "$command_text"
        printf '```\n\n'
        printf 'Output'
        if [[ "$max_lines" != "0" ]]; then
          printf ' (last %s lines)' "$max_lines"
        fi
        printf ':\n\n```text\n'
        if [[ "$end" -gt "$start" ]]; then
          tail -c +"$((start + 1))" "$log_file" |
            head -c "$((end - start))" |
            ${pkgs.perl}/bin/perl -pe 's/\e\[[0-?]*[ -\/]*[@-~]//g; s/\e\].*?(\a|\e\\)//g; s/\r//g' |
            if [[ "$max_lines" == "0" ]]; then cat; else tail -n "$max_lines"; fi
        fi
        printf '\n```\n'
      } > "$tmp"

      tmux load-buffer -w "$tmp"

      case "$cmd" in
        copy)
          ;;
        paste-last-pane)
          current_pane="$(tmux display -p '#{pane_id}')"
          if [[ "$source_pane" == "$current_pane" ]]; then
            target_pane="$(previous_pane || true)"
          else
            target_pane="$current_pane"
          fi
          if [[ "$source_pane" == "$current_pane" && "$target_pane" == "$current_pane" ]]; then
            fail "No previous pane to paste into"
          fi
          [[ -n "''${target_pane:-}" ]] || fail "No target pane to paste into"
          tmux paste-buffer -t "$target_pane"
          ;;
        *)
          printf 'usage: %s {copy|paste-last-pane}\n' "$0" >&2
          exit 2
          ;;
      esac
    '';
  };

  programs.tmux = {
    extraConfig = builtins.readFile ./tmux.conf;
    shortcut = lib.mkDefault "f";
    keyMode = "vi";
    baseIndex = 1;
    escapeTime = 20;
    historyLimit = 30000;
    aggressiveResize = true;
    clock24 = true;
    terminal = "tmux-256color";
    mouse = true;

    plugins = with pkgs.tmuxPlugins; [
      sensible
      {
        plugin = resurrect;
        extraConfig = ''

          resurrect_dir="$HOME/.local/share/tmux/resurrect"
          set -g @resurrect-dir $resurrect_dir
          set -g @resurrect-hook-post-save-all 'target=$(readlink -f $HOME/.local/share/tmux/resurrect/last); sed "s|\(.*bin/nvim\) .*|\1|; s|/etc/profiles/per-user/$USER/bin/||g; s|/home/$USER/.nix-profile/bin/||g" $target | sponge $target'
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-processes '"~nvim"'
        '';
      }
      {
        plugin = continuum; # needs resurrect present
        extraConfig = ''
            set -g status-interval 60         # update the status bar every 10 seconds
            set -g status-justify centre
            set -g status-position top
            set -g status-style 'bg=default'  # transparent background
            set -g status-left-length 50
            set -g status-right-length 70
            set -g status-bg 'default'
            if-shell 'command -v gsettings >/dev/null 2>&1 && gsettings get org.gnome.desktop.interface color-scheme | grep -q prefer-light' \
              'source-file ~/.config/tmux/theme-light.conf' \
              'source-file ~/.config/tmux/theme-dark.conf'


            set -g @continuum-restore 'on'
            set -g @continuum-save-interval '5'
            set -g @continuum-boot 'on'
            set -g @continuum-boot-options 'ghostty'
          # set -g @continuum-systemd-start-cmd 'start-server'
        '';
      }
    ];
  };
}
