{ config, pkgs, lib, ... }:

{
  options.modules.desktop.hyprland.enable = lib.mkEnableOption "Hyprland";

  config = lib.mkIf config.modules.desktop.hyprland.enable {
    programs.hyprland.enable = true;

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd start-hyprland";
          user = "greeter";
        };
      };
    };
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
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
