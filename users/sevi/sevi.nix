{ config, pkgs, ... }:

{
  imports = [
    ./apps.nix
    ./gdrive.nix
    ./terminal.nix
    ./file-manager.nix
    ./editor.nix
    ./noctalia.nix
    ./hyprland.nix
    ./zathura.nix
  ];

  home = {
    username = "severin";
    homeDirectory = "/home/severin";
    stateVersion = "23.11";
  };

  home.pointerCursor.enable = true;

  # ad-hoc scripts like keep-awake survive `nixos-rebuild switch`
  home.sessionPath = [ "$HOME/.local/bin" ];

  programs.home-manager.enable = true;
}
