{ config, pkgs, lib, ... }:

{
  options.modules.desktop.hyprland.enable = lib.mkEnableOption "Hyprland";

  config = lib.mkIf config.modules.desktop.hyprland.enable {
    # 1. Systemweite Hyprland-Infrastruktur aktivieren
    # NOTE: only the system-level binary + start-hyprland launcher live here.
    # All Hyprland window/keybind settings are owned by home-manager's
    # wayland.windowManager.hyprland (users/sevi/hyprland.nix). Do NOT set
    # programs.hyprland.settings here, or you'll get two competing configs.
    programs.hyprland.enable = true;

    # 2. Hardware-Grafikbeschleunigung (zwingend erforderlich für unstable-Kanäle)
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    # 3. Greetd Display-Manager zur Sitzungsinitialisierung einrichten
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          # tuigreet übergibt die Ausführung direkt an die Hyprland-Sitzung
          command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd start-hyprland";
          user = "greeter";
        };
      };
    };


    # XDG-Portals für Interprozesskommunikation (Screen-Sharing, File-Picker)
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
    };

    security.polkit.enable = true;
    
    # Systemweite Wayland-Werkzeuge bereitstellen
    environment.systemPackages = with pkgs; [
      tuigreet
      hyprpolkitagent
      wl-clipboard
      brightnessctl        # screen-brightness backend for Noctalia + media keys
    ];
  };
}
