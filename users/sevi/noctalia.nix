{ config, lib, pkgs, inputs, ... }:

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
#   * The `custom_button` widget runs its `command` via runAsync and DISCARDS
#     stdout — so it can launch things but can never display command output.
#     (No v5 widget renders dynamic shell output.) Hence pomodoro is a launcher.

let
  bash = "${pkgs.bash}/bin/bash";
in
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

          start = [ "workspaces" ];
          center = [
            "weather"
            {
              id = "clock";
              # Plain strftime (no {:%...} wrapper — noctalia parses that as
              # C++20 chrono and falls through to strftime with a literal,
              # which renders blank). Shows time + ISO week-of-year.
              format = "%H:%M  W%V";
            }
            {
              id = "custom_button";
              label = "🍅";
              tooltip = "Pomodoro — click to start a 25-min timer";
              # Launched in foot (absolute path, so it never depends on PATH
              # inside noctalia's spawned /bin/sh). ghostty is broken in this
              # session (GTK runtime crashes on spawn).
              command = "${pkgs.foot}/bin/foot -e ${./scripts/pomodoro.sh}";
            }
          ];
          end = [ "network" "bluetooth" "brightness" "battery" "session" ];
        };
      };
    };
  };
}
