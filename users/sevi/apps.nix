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
  ];
}
