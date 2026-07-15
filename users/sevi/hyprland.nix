{ ... }:

{
  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = true;
    settings = {
      monitor = [",1920x1080,auto,1"];
      env = [ 
      "XCURSOR_SIZE,24"
      "HYPRCURSOR_SIZE,24"
      ];
      "exec-once" = [
        "noctalia"
      ];
      input = { 
      kb_layout = "ch";
      };
      layout = "master";
      general = {
        gaps_in = 0;
        gaps_out = 0;
        border_size = 0;
      };
      "$mod" = "SUPER";
	windowrule = [
  "match:class ^(fsel)$, float on"
  "match:class ^(fsel)$, center on"
  "match:class ^(fsel)$, size 850 500"
];
      # Format: width height (pixels or percentages like 50% 50%)
      bind = [
        "$mod, Return, exec, ghostty"
        "$mod, V, exec, ghostty -e nvim"
        "$mod, B, exec, brave"
	"$mod SHIFT, F, exec, ghostty -e yazi"
        "$mod, W, killactive"
        "$mod, F, fullscreen"
	"$mod, space, exec, ghostty --class=fsel -e fsel"
        
        # Navigation
        "$mod, h, movefocus, l"
        "$mod, l, movefocus, r"
        "$mod, k, movefocus, u"
        "$mod, j, movefocus, d"

	"$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"

	"$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        "$mod SHIFT, 0, movetoworkspace, 10"

        # Audio (wpctl — already present on the system).
        # NOTE: hyprland bind syntax is MODS, KEY, DISPATCHER, ARGS. Media keys
        # have no modifier, so the mods field is left empty (leading comma).
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"

        # Brightness (brightnessctl — added to system packages)
        ", XF86MonBrightnessUp, exec, brightnessctl set +5%"
        ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"

        # Power menu via fsel in dmenu mode (pick Shutdown / Reboot / Suspend).
        # fsel --dmenu is a TUI that needs a real PTY (raw mode); hyprland's
        # exec gives it a pipe, so launch it inside a ghostty window.
        "$mod, ESC, exec, ghostty -e ${./scripts/power-menu.sh}"
        ];
    };
  };
}
