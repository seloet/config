{ ... }:

{
  imports = [
    ./terminal.nix
    ./file-manager.nix
    ./zathura.nix
  ];

  home = {
    username = "severin";
    homeDirectory = "/home/severin";
    stateVersion = "23.11";
    pointerCursor.enable = true;
    sessionPath = [ "$HOME/.local/bin" ];
  };

  gtk = {
    enable = true;
    gtk3.extraConfig.gtk-enable-primary-paste = true;
    gtk4.extraConfig.gtk-enable-primary-paste = true;
  };

  programs.home-manager.enable = true;
}
