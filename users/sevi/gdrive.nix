# Mount Google Drive as a local FUSE drive when severin logs in.
# Remote name in rclone.conf is "Org" (created via `rclone config`).
# Nix owns ONLY the mount service here. The actual remote + OAuth token
# live in ~/.config/rclone/rclone.conf, created once by:
#     rclone config  (choose "drive", headless-friendly, accept the OAuth URL)
# We deliberately do NOT use programs.rclone.remotes/mounts: that module
# generates a rclone-config.service which rewrites rclone.conf from Nix,
# which would nuke the interactive OAuth token on every rebuild.
{ pkgs, lib, ... }:

{
  # fusermount3 setuid helper lives in /run/wrappers/bin on NixOS
  # (programs.fuse is enabled by default). User services get a clean
  # environment, so point PATH at it explicitly.
  systemd.user.services.gdrive-mount = {
    Unit = {
      Description = "Google Drive (rclone FUSE mount)";
      # Best-effort: don't hard-fail if the network target isn't present
      # in the user session; Restart handles the offline case.
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
      # rclone exits non-zero if Drive is unreachable at start; retry.
      Restart = "on-failure";
      RestartSec = 30;
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
