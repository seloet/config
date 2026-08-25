# Mount the Synology DS214 (DiskStation) as a local FUSE drive when sevi logs in.
# Mirrors gdrive.nix: Nix owns ONLY the mount service. The remote ("nas") lives
# in ~/.config/rclone/rclone.conf; create it once after install with:
#     rclone config   # choose "smb" (or "nfs"), host = DiskStation's Tailscale IP,
#                     # user/password, share = the DSM shared folder name
# The unit no-ops until ~/.config/rclone/rclone.conf exists.
{ pkgs, lib, ... }:

{
  systemd.user.services.nas-mount = {
    Unit = {
      Description = "Synology DiskStation (rclone FUSE mount)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      ConditionPathExists = "%h/.config/rclone/rclone.conf";
    };

    Service = {
      Type = "simple";
      Environment = "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/nas";
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.rclone}/bin/rclone mount nas: %h/nas"
        "--vfs-cache-mode writes"
        "--cache-dir %C/rclone"
        "--vfs-cache-max-size 5G"
        "--dir-cache-time 30s"
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
