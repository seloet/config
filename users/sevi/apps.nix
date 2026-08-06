{ pkgs, ... }:

{
  home.packages = with pkgs; [
    brave
    zed-editor
    glow
    fsel
    fastfetch
    btop
    fd
    ripgrep
    jq
    gh
    codex
    tuxedo
    rclone
    llama-cpp

    yt-dlp
    qbittorrent
    vlc
    cliamp
    kaggle
  ];
}
