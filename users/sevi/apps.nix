{ pkgs, ... }:

{
  home.packages = with pkgs; [
    brave
    zed-editor
    zathura
    glow
    fsel
    fastfetch
    btop
  ];
}
