{ config, lib, ... }:

let
  colors = config.lib.stylix.colors;
  rgb = color:
    "rgb(${colors."${color}-rgb-r"}, ${colors."${color}-rgb-g"}, ${colors."${color}-rgb-b"})";
in
{
  programs.zathura = {
    enable = true;
    options = {
      adjust-open = "best-fit";

      page-v-padding = 0;
      page-h-padding = 0;

      # Hyprland blends the whole window, so keep both surfaces equally opaque
      default-bg = lib.mkForce (rgb "base00");
      render-loading-bg = rgb "base00";
      recolor = true;
      recolor-keephue = true;
      recolor-lightcolor = lib.mkForce (rgb "base00");

      continuous-hist-save = true;
    };
  };
}
