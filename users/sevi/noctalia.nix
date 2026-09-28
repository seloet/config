{ config, lib, ... }:

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
          shadow = true;
          background_opacity = 0.85;
          capsule = false;
          auto_hide = false;
          reserve_space = true;

          start = [
            "pomodoro"
            "workspaces"
          ];
          center = [
            "weather"
            "todo"
          ]
          ++ lib.optionals config.workstation.localAssistant [ "local-assistant" ]
          ++ [ "clock" ];
          end = [
            "network"
            "bluetooth"
          ]
          ++ lib.optionals config.workstation.portableWidgets [
            "brightness"
            "battery"
          ]
          ++ [ "session" ];
        };
      };

      calendar = {
        enabled = true;
        refresh_minutes = 15;
        account.google = {
          type = "google";
          name = "Google";
        };
      };

      widget = {
        clock = {
          format = "{:%H:%M  W%V}";
          actions.left = "panel-toggle control-center calendar";
        };

        pomodoro = {
          type = "sevi/pomodoro:timer";
        };

        todo = {
          type = "sevi/todo:open";
        };
      }
      // lib.optionalAttrs config.workstation.localAssistant {
        local-assistant = {
          type = "sevi/local-assistant:toggle";
        };
      };

      plugins = {
        auto_update = "none";
        enabled = [
          "sevi/pomodoro"
          "sevi/todo"
        ]
        ++ lib.optionals config.workstation.localAssistant [ "sevi/local-assistant" ];
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
