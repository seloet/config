{ ... }:

# Noctalia v5 reads TOML from ~/.config/noctalia/config.toml; provided here via
# programs.noctalia.settings (serialised to [bar.X] / [<widget>] tables).
# v5 schema gotchas (verified against noctalia 5.0.0):
#   * Full-width bar uses margin_ends (L/R) + margin_edge. margin_h/margin_v are
#     silently ignored in v5 — that was the original gap bug.
#   * clock only takes a strftime `format`; clicking it opens the calendar.
#     No click-to-cycle support.
#   * Dynamic widgets live in plugins (pomodoro/todo below render in the bar).

{
  programs.noctalia = {
    enable = true;
    # fail the build on bad schema
    settings = {
      bar = {
        main = {
          position = "top";
          thickness = 34;
          margin_ends = 0;     # horizontal margin -> full width
          margin_edge = 0;     # vertical margin from screen edge
          padding = 14;
          widget_spacing = 6;
          radius = 0;
          shadow = true;
          background_opacity = 0.85;
          capsule = false;
          auto_hide = false;
          reserve_space = true;

          start = [ "pomodoro" "workspaces" ];
          # lanes are string lists; widget settings go under [widget.<name>]
          center = [ "weather" "todo" "clock" ];
          end = [ "network" "bluetooth" "brightness" "battery" "session" ];
        };
      };

      widget = {
        clock = {
          # chrono-style replacement field
          format = "{:%H:%M  W%V}";
        };

        pomodoro = {
          type = "sevi/pomodoro:timer";
        };

        todo = {
          type = "sevi/todo:open";
        };
      };

      plugins = {
        enabled = [ "sevi/pomodoro" "sevi/todo" ];
        source = [
          {
            name = "sevi-config";
            kind = "path";
            location = "${./plugins}";
            auto_update = false;
            enabled = true;
          }
        ];
      };
    };
  };
}
