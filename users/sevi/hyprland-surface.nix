{ ... }:

# Reduced Hyprland setup for the Surface. Based on the laptop's
# wayland.windowManager.hyprland config but using the lean app set:
# Micro (not Neovim), Brave, Yazi, Zathura. Blur/shadows/animations off,
# VFR on, single scaled display. Touchpad defaults are set; touchscreen
# tuning is deferred until after on-device hardware testing.
{
  programs.hyprlock.enable = true;

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      listener = [
        {
          timeout = 300;
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 330;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          timeout = 1800;
          on-timeout = "systemctl suspend";
        }
      ];
    };
  };

  wayland.windowManager.hyprland = {
    enable = true;
    # Preserve the existing Home Manager (< 26.05) Hyprlang behavior explicitly.
    configType = "hyprlang";
    systemd.enable = true;

    settings = {
      # $mod must be defined before it can be used in binds below.
      "$mod" = "SUPER";

      # Launch the reduced Noctalia bar once on session start.
      exec-once = [ "noctalia" ];

      monitor = [
        ",preferred,auto,1.5"
      ];

      general = {
        gaps_in = 0;
        gaps_out = 0;
        border_size = 1;
      };

      decoration = {
        rounding = 0;

        blur = {
          enabled = false;
        };

        shadow = {
          enabled = false;
        };
      };

      animations = {
        enabled = false;
      };

      misc = {
        vfr = true;
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        force_default_wallpaper = 0;
      };

      input = {
        kb_layout = "ch";

        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
        };
      };

      bind = [
        "$mod, RETURN, exec, ghostty"
        "$mod, B, exec, brave"
        "$mod, E, exec, ghostty -e yazi"
        "$mod, M, exec, ghostty -e micro"
        "$mod, Z, exec, zathura"
        "$mod SHIFT, Q, killactive"
        "$mod SHIFT, E, exit"
      ];

      bindel = [
        ", XF86MonBrightnessUp, exec, brightnessctl set +5%"
        ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
        ", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
      ];

      bindl = [
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
      ];
    };
  };
}
