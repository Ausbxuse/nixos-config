#
# phone-media-sort — moves files from ~/Media/Phone into the organized
# ~/Media/{Pictures,Videos,Audio} tree, sorted by MIME type.
#
# ~/Media/Phone is a syncthing receive-only folder mirroring the phone's
# DCIM. Moved files won't re-download (receive-only doesn't auto-revert
# local changes). Empty Phone/ = everything sorted, safe to delete on phone.
#
{
  config,
  lib,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
  phoneDir = "${home}/Media/Phone";
  picturesDir = "${home}/Media/Pictures";
  videosDir = "${home}/Media/Videos";
  audioDir = "${home}/Media/Audio";

  sortScript = pkgs.writeShellScript "phone-media-sort" ''
    set -euo pipefail
    src=${lib.escapeShellArg phoneDir}
    [[ -d "$src" ]] || exit 0

    find "$src" -type f -mmin +1 | while IFS= read -r f; do
      mime=$(${pkgs.file}/bin/file -b --mime-type "$f")
      case "$mime" in
        image/*)  dest=${lib.escapeShellArg picturesDir} ;;
        video/*)  dest=${lib.escapeShellArg videosDir}   ;;
        audio/*)  dest=${lib.escapeShellArg audioDir}    ;;
        *)        continue ;;
      esac
      mkdir -p "$dest"
      mv -n "$f" "$dest/"
    done
  '';
in {
  systemd.user.services.phone-media-sort = {
    Unit.Description = "Sort phone media into organized directories";
    Service = {
      Type = "oneshot";
      ExecStart = "${sortScript}";
    };
  };

  systemd.user.timers.phone-media-sort = {
    Unit.Description = "Sort phone media periodically";
    Timer = {
      OnBootSec = "5m";
      OnUnitActiveSec = "15m";
    };
    Install.WantedBy = ["timers.target"];
  };
}
