{ config, pkgs, lib, ... }:

{
  options.modules.desktop.hyprland.enable = lib.mkEnableOption "Hyprland";

  config = lib.mkIf config.modules.desktop.hyprland.enable {
    programs.hyprland.enable = true;

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    xdg.portal = {
      enable = true;
    };

    security.polkit.enable = true;

    environment.systemPackages = with pkgs; [
      hyprpolkitagent
      wl-clipboard
      cliphist
      brightnessctl
    ];
  };
}
