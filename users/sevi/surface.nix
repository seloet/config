{ inputs, ... }:

{
  imports = [
    ./common.nix
    ./apps-surface.nix
    # The service stays inactive until rclone.conf exists.
    ./gdrive.nix
    ./hyprland-surface.nix
    ./noctalia-surface.nix

    # Provides the programs.noctalia option used by noctalia-surface.nix.
    # (Noctalia is a Home Manager module pulled from the flake input; it is not
    # part of the listed Surface profile imports above, so wire it here.)
    inputs.noctalia.homeModules.default
  ];

  home.sessionVariables = {
    EDITOR = "micro";
    VISUAL = "micro";
  };

  programs.mpv = {
    enable = true;

    config = {
      hwdec = "auto-safe";
      vo = "gpu-next";
    };
  };
}
