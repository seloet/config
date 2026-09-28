{ ... }:

{
  programs.noctalia = {
    enable = true;
    settings = {
      bar = {
        main = {
          position = "top";
          thickness = 34;
          margin_ends = 0;
          margin_edge = 0;
          padding = 14;
          widget_spacing = 6;
          radius = 0;
          shadow = false;
          background_opacity = 0.92;
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
        auto_update = "none";
        enabled = [ "sevi/todo" ];
        source = [
          {
            name = "sevi-config";
            kind = "path";
            location = "${./plugins}";
            enabled = true;
          }
        ];
      };
    };
  };
}
