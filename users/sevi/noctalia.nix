{ ... }:

# Noctalia v5 config is TOML read from ~/.config/noctalia/config.toml.
# The supported way to provide it is via programs.noctalia.settings (attrset),
# which the hm module serialises to TOML under [bar.X] / [<widget>] tables.
#
# IMPORTANT v5 schema gotchas (verified against noctalia 5.0.0 source):
#   * Bar full-width uses [bar.main] margin_ends (L/R) and margin_edge (the edge
#     it sits on, e.g. 0 for top). The old config used margin_h/margin_v, which
#     are NOT valid in v5 and are silently ignored — that was the gap bug.
#   * The built-in `clock` widget only takes a strftime `format`; clicking it
#     opens the control-centre calendar. There is NO click-to-cycle support.
#   * Dynamic widgets belong in Noctalia plugins. The local Pomodoro plugin is
#     sourced declaratively below and renders its countdown directly in the bar.

{
  programs.noctalia = {
    enable = true;
    # Validate the generated TOML at build time (fails the build on bad schema).
    settings = {
      bar = {
        main = {
          position = "top";
          thickness = 34;
          margin_ends = 0;     # horizontal margin -> bar spans full width
          margin_edge = 0;     # vertical margin from the screen edge
          padding = 14;
          widget_spacing = 6;
          radius = 0;
          shadow = true;
          background_opacity = 1.0;
          capsule = false;
          auto_hide = false;
          reserve_space = true;

          start = [ "pomodoro" "workspaces" ];
          # Bar lanes are string lists. Widget settings belong under
          # [widget.<name>]; inline tables in this list are ignored by v5.
          center = [ "weather" "todo" "clock" ];
          end = [ "network" "bluetooth" "brightness" "battery" "session" ];
        };
      };

      widget = {
        clock = {
          # Noctalia's clock formatter expects a chrono-style replacement field.
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
