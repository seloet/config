{ inputs, ... }:

{
  imports = [
    ./apps-surface.nix
    # The service stays inactive until rclone.conf exists.
    ./gdrive.nix
    ./terminal.nix
    ./file-manager.nix
    ./zathura.nix

    ./hyprland-surface.nix
    ./noctalia-surface.nix

    # Provides the programs.noctalia option used by noctalia-surface.nix.
    # (Noctalia is a Home Manager module pulled from the flake input; it is not
    # part of the listed Surface profile imports above, so wire it here.)
    inputs.noctalia.homeModules.default
  ];

  home = {
    username = "severin";
    homeDirectory = "/home/severin";
    stateVersion = "23.11";
  };

  home.pointerCursor.enable = true;

  home.sessionPath = [
    "$HOME/.local/bin"
  ];

  home.sessionVariables = {
    EDITOR = "micro";
    VISUAL = "micro";
  };

  programs.home-manager.enable = true;

  programs.mpv = {
    enable = true;

    config = {
      hwdec = "auto-safe";
      vo = "gpu-next";
    };
  };
}
