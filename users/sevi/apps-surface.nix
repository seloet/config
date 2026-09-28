{ pkgs, ... }:

{
  home.packages = with pkgs; [
    brave
    micro
    tuxedo
    rclone
    playerctl
    pavucontrol
    libva-utils
    yt-dlp
    qbittorrent
    vlc
    cliamp
  ];
}
