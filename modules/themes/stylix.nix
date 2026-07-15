{ pkgs, ... }:

{
  stylix = {
    enable = true;
    # Ensure this file exists in this directory, or change to a valid URL/Path
    image = ./Wallpaper.png; 
    polarity = "dark";
    
    base16Scheme = "${pkgs.base16-schemes}/share/themes/tokyo-night-dark.yaml";

    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Ice";
      size = 24;
    };
    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.fira-code;
        name = "FiraCode Nerd Font Mono";
      };
      sizes.terminal = 11;
    };
  };
}
