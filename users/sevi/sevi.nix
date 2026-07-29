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

  services.local-assistant = {
    enable = true;
    speechConfig = "/home/severin/LocalAssistant/config/speech.yaml";
    playChime = true;
    notifications = true;
  };

  programs.home-manager.enable = true;
}
