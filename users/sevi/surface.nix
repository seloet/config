{ inputs, ... }:

{
  imports = [
    ./common.nix
    ./apps-surface.nix
    ./gdrive.nix
    ./hyprland-surface.nix
    ./noctalia-surface.nix

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
