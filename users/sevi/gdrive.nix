{ pkgs, lib, ... }:

{
  systemd.user.services.gdrive-mount = {
    Unit = {
      Description = "Google Drive (rclone FUSE mount)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = "%h/.config/rclone/rclone.conf";
    };

    Service = {
      Type = "simple";
      Environment = "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/gdrive";
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.rclone}/bin/rclone mount Org: %h/gdrive"
        "--vfs-cache-mode full"
        "--cache-dir %C/rclone"
        "--vfs-cache-max-size 10G"
        "--vfs-cache-max-age 7d"
        "--dir-cache-time 1h"
        "--poll-interval 15s"
        "--log-level INFO"
      ];
      Restart = "on-failure";
      RestartSec = 30;
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
