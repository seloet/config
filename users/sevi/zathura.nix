{ pkgs, ... }:

{
  programs.zathura = {
    enable = true;
    # Fit each page to the window (portrait pages fill top-to-bottom).
    extraConfig = ''
      set zoom-to-fit true
      set continuous-hist-save true
    '';
  };
}
