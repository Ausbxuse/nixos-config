#
# recovery-backup — manual backup to USB recovery drive.
#
# Provides a systemd service that can be triggered via
# `just backup-bundle`. No auto-trigger on plug-in — this avoids
# accidentally overwriting good media backups with corrupted files.
#
# No-op when recoveryPartUuid is empty (drive not yet set up).
#
{
  config,
  lib,
  pkgs,
  hostDef,
  username,
  ...
}: let
  recoveryPartUuid = hostDef.recovery.partUuid or "";
  enabled = recoveryPartUuid != "";

  excludeFile = pkgs.copyPathToStore ../../scripts/restic-excludes.txt;

  recoveryBackup = pkgs.writeShellApplication {
    name = "recovery-backup";
    runtimeInputs = with pkgs; [
      coreutils
      git
      hostname
      restic
      rsync
      util-linux
      libnotify
      gnutar
      findutils
      gnused
    ];
    text = builtins.readFile ../../scripts/recovery-backup.sh;
  };
in
  lib.mkIf enabled {
    # Ensure mount point exists.
    systemd.tmpfiles.rules = ["d /mnt/recovery 0755 root root -"];

    systemd.services.recovery-backup = {
      description = "Backup to recovery USB drive";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${recoveryBackup}/bin/recovery-backup";
        Environment = [
          "RECOVERY_MOUNT=/mnt/recovery"
          "RECOVERY_UUID=${recoveryPartUuid}"
          "USERNAME=${username}"
          "HOME_DIR=/home/${username}"
          "RESTIC_REPOSITORY=/mnt/recovery/restic"
          "RESTIC_PASSWORD_FILE=${config.sops.secrets.recovery-restic-password.path}"
          "EXCLUDE_FILE=${excludeFile}"
        ];
        TimeoutStartSec = "2h";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
      wantedBy = [];
    };

    sops.secrets.recovery-restic-password = {};
  }
