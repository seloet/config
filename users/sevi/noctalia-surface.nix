{ pkgs, ... }:

# Reduced Noctalia bar for the Surface. Kept: todo plugin, clock, battery,
# network, bluetooth, volume, brightness, session. Removed: weather + pomodoro
# (and the pomodoro plugin) to cut background activity, polling and storage.
# Heavy transparency / large shadows disabled to suit the tablet form factor.
# Same v5 schema as noctalia.nix.
{
  programs.noctalia = {
    enable = true;
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
          shadow = false;            # no large shadows
          background_opacity = 0.92; # light transparency (was 0.85)
          capsule = false;
          auto_hide = false;
          reserve_space = true;

          start = [ "workspaces" ];
          center = [ "todo" "clock" ];
          end = [ "bluetooth" "volume" "network" "brightness" "battery" "session" ];
        };
      };

      widget = {
        clock = {
          format = "{:%H:%M  W%V}";
        };

        todo = {
          type = "sevi/todo:open";
        };
      };

      plugins = {
        enabled = [ "sevi/todo" ];
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
