{ pkgs, ... }:

{
  home.packages = with pkgs; [
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
