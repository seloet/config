{ ... }:

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
    systemd.enable = true;
    configType = "lua";

    extraConfig = ''
      local mod = "SUPER"

      hl.monitor({
        output = "",
        mode = "1920x1080",
        position = "auto",
        scale = 1,
      })

      hl.env("XCURSOR_SIZE", "24")
      hl.env("HYPRCURSOR_SIZE", "24")

      hl.on("hyprland.start", function()
        hl.exec_cmd("noctalia")
      end)

      hl.config({
        input = {
          kb_layout = "ch",
        },
        general = {
          gaps_in = 0,
          gaps_out = 0,
          border_size = 0,
          layout = "master",
        },
      })

      hl.bind(mod .. " + SPACE", hl.dsp.exec_cmd("ghostty --title=fsel -e fsel --detach"))

      -- fsel can't be matched by Wayland class; identify it by window title.
      hl.window_rule({
        name = "fsel-window",
        match = { title = "^(fsel)$" },
        float = true,
        size = "850 500",
        center = true,
      })

      hl.window_rule({
        name = "zathura-opacity",
        match = { class = "^(org.pwmt.zathura)$" },
        opacity = 0.85,
      })

      hl.bind(mod .. " + RETURN", hl.dsp.exec_cmd("ghostty"))
      hl.bind(mod .. " + V", hl.dsp.exec_cmd("ghostty -e nvim"))
      hl.bind(mod .. " + B", hl.dsp.exec_cmd("brave"))
      hl.bind(mod .. " + SHIFT + F", hl.dsp.exec_cmd("ghostty -e yazi"))
      hl.bind(mod .. " + W", hl.dsp.window.close())
      hl.bind(mod .. " + F", hl.dsp.window.fullscreen())
      hl.bind(mod .. " + SPACE", hl.dsp.exec_cmd("ghostty --title=fsel -e fsel --detach"))

      hl.bind(mod .. " + H", hl.dsp.focus({ direction = "left" }))
      hl.bind(mod .. " + L", hl.dsp.focus({ direction = "right" }))
      hl.bind(mod .. " + K", hl.dsp.focus({ direction = "up" }))
      hl.bind(mod .. " + J", hl.dsp.focus({ direction = "down" }))

      for workspace = 1, 10 do
        local key = workspace % 10
        hl.bind(mod .. " + " .. key, hl.dsp.focus({ workspace = workspace }))
        hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = workspace }))
      end

      -- media keys work while locked and repeat while held
      local mediaBindOptions = { locked = true, repeating = true }
      hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), mediaBindOptions)
      hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), mediaBindOptions)
      hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), mediaBindOptions)
      hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set +5%"), mediaBindOptions)
      hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), mediaBindOptions)

      hl.bind(mod .. " + ESCAPE", hl.dsp.exec_cmd("foot --title=fsel --app-id=fsel ${./scripts/power-menu.sh}"))

      hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
      hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
    '';
  };
}
