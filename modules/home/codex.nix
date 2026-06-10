{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  system = pkgs.stdenv.hostPlatform.system;
  codex = inputs.codex-cli-nix.packages.${system}.default;
in {
  home.packages = [codex];

  home.activation.configureCodexNotify = lib.hm.dag.entryAfter ["writeBoundary"] ''
    config_file="${config.home.homeDirectory}/.codex/config.toml"
    notify_line='notify = ["${config.home.homeDirectory}/.local/bin/tmux/codex-notify.sh"]'
    status_line='status_line = ["model-with-reasoning", "current-dir", "weekly-limit", "five-hour-limit", "fast-mode"]'
    status_line_use_colors='status_line_use_colors = true'

    mkdir -p "$(dirname "$config_file")"

    if [ -L "$config_file" ]; then
      tmp="$(${pkgs.coreutils}/bin/mktemp)"
      ${pkgs.coreutils}/bin/cat "$config_file" > "$tmp"
      ${pkgs.coreutils}/bin/rm -f "$config_file"
      ${pkgs.coreutils}/bin/install -m 600 "$tmp" "$config_file"
      ${pkgs.coreutils}/bin/rm -f "$tmp"
    elif [ ! -e "$config_file" ]; then
      ${pkgs.coreutils}/bin/install -m 600 /dev/null "$config_file"
    fi

    export CODEX_NOTIFY_LINE="$notify_line"
    ${pkgs.perl}/bin/perl -0pi -e '
      my $notify = $ENV{CODEX_NOTIFY_LINE};
      if (!s/\A(.*?)(^notify\s*=.*$)(.*?)(?=^\[|\z)/$1$notify$3/ms) {
        s/\A(.*?)(?=^\[|\z)/$1$notify\n\n/ms;
      }
    ' "$config_file"

    export CODEX_STATUS_LINE="$status_line"
    export CODEX_STATUS_LINE_USE_COLORS="$status_line_use_colors"
    ${pkgs.perl}/bin/perl -0pi -e '
      my $status_line = $ENV{CODEX_STATUS_LINE};
      my $use_colors = $ENV{CODEX_STATUS_LINE_USE_COLORS};

      if (!/^\[tui\]\s*$/m) {
        $_ .= "\n[tui]\n";
      }

      s{
        (^\[tui\]\s*\n)
        (.*?)
        (?=^\[|\z)
      }{
        my ($header, $body) = ($1, $2);

        if ($body =~ s/^status_line\s*=.*$/$status_line/m) {
        } else {
          $body = "$status_line\n$body";
        }

        if ($body =~ s/^status_line_use_colors\s*=.*$/$use_colors/m) {
        } else {
          $body = "$body$use_colors\n";
        }

        "$header$body";
      }msxe;
    ' "$config_file"
  '';
}
