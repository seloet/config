{ config, pkgs, inputs, ... }:

{
  imports = [
    inputs.local-assistant.homeManagerModules.default
    ./apps.nix
    ./gdrive.nix
    ./terminal.nix
    ./file-manager.nix
    ./editor.nix
    ./noctalia.nix
    ./hyprland.nix
    ./cliphist.nix
    ./zathura.nix
  ];

  home = {
    username = "severin";
    homeDirectory = "/home/severin";
    stateVersion = "23.11";
  };

  home.pointerCursor.enable = true;

  # User scripts remain directly runnable from ~/.local/bin.
  home.sessionPath = [ "$HOME/.local/bin" ];

  home.file.".local/bin/keep-awake" = {
    source = ./scripts/keep-awake;
    executable = true;
    # Replace the former unmanaged script on the first activation.
    force = true;
  };

  services.local-assistant = {
    enable = true;
    speechConfig = "/home/severin/LocalAssistant/config/speech.yaml";
    playChime = true;
    notifications = true;
  };

  programs.home-manager.enable = true;
}
