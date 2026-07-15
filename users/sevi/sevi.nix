{ config, pkgs, ... }:

{
  imports = [
    ./apps.nix
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

  programs.home-manager.enable = true;
}
