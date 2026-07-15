{ config, lib, pkgs, inputs, ... }:

# Noctalia v5 config is TOML read from ~/.config/noctalia/config.toml.
# The supported way to provide it is via programs.noctalia.settings (attrset),
# which the home-module converts to TOML AND validates against the binary at
# build time. (Hand-writing xdg.configFile skips that validation and a bad
# file silently falls back to defaults -> bar looks unchanged.)
#
# Verified v5 schema (from noctalia-dev/noctalia@3137323 config_schema.cpp and
# widget_factory.cpp):
#   Bar keys: margin_ends (horizontal L+R gap), margin_edge (gap on the bar's
#   own edge, e.g. top), margin_opposite_edge, thickness, padding, etc. There
#   is NO margin_h / margin_v in v5 — the old config's margin_h=0 was silently
#   ignored, which is why the bar never reached the screen edges.
#   Widget ids (lowercase): launcher, wallpaper, workspaces, clock, media,
#   tray, notifications, clipboard, network, bluetooth, volume, brightness,
#   battery, control-center, session, weather, custom_button, caffeine,
#   spacer, taskbar, sysmon, privacy, screenshot, settings, plugin.
#   custom_button options: glyph, label, tooltip, command (left-click),
#   right_command, middle_command. `command`'s stdout becomes the label.
#
# Notes on the user's requests vs v5 reality:
#   * Timezone: handled at the NixOS level (time.timeZone = "Europe/Zurich"),
#     not here. Noctalia's clock reads local time.
#   * Weather: the built-in `weather` widget is supported. Its city/units live
#     in Noctalia *state* (set once in the control-center); there are no TOML
#     keys for them, so we only add the widget to the bar.
#   * Pomodoro: there is NO built-in pomodoro/timer widget in v5. We implement
#     a focus timer with a `custom_button` whose `command` prints the remaining
#     time and whose left-click toggles start/pause (state in a dotfile).
#   * Clickable clock (time/date/week-of-year): the built-in `clock` widget only
#     middle-clicks to settings. We add a `custom_button` that prints the
#     current view and cycles it on left-click.

let
  # Shared state files for the scripted widgets.
  clockState = "${config.home.homeDirectory}/.local/state/noctalia-clock-view";
  pomodoroState = "${config.home.homeDirectory}/.local/state/noctalia-pomodoro";
  bash = "${pkgs.bash}/bin/bash";
in
{
  imports = [ inputs.noctalia.homeModules.default ];

  programs.noctalia = {
    enable = true;

    # Validate the generated TOML against the binary at build time (catches
    # schema errors that would otherwise silently revert to defaults).
    validateConfig = true;

    settings = {
      theme = {
        mode = "dark";
        # The noctalia flake's hm.nix sets theme.source = "custom" by default
        # (plain value, priority 100). Force our local choice so it wins the
        # conflicting-definition check without editing the flake module.
        source = lib.mkForce "builtin";
        builtin = "Tokyo-Night";
      };

      bar.main = {
        position = "top";
        thickness = 34;
        background_opacity = 1.0;
        radius = 0;
        # Real v5 keys: margin_ends = horizontal gap (L+R), margin_edge = gap
        # on the bar's own edge (top). 0 = full-bleed to the screen edges.
        margin_ends = 0;
        margin_edge = 0;
        padding = 14;
        widget_spacing = 6;
        scale = 1.0;
        shadow = true;
        auto_hide = false;
        reserve_space = true;    # reserve a strut so windows don't overlap
        capsule = false;

        start = [ "workspaces" ];
        center = [
          "weather"
          "clock"
          # Clickable clock: left-click cycles time / date / ISO week-of-year.
          {
            id = "custom_button";
            glyph = "calendar";
            tooltip = "Clock — click to cycle time / date / week";
            command = "${bash} -c 'idx=$(cat ${clockState} 2>/dev/null || echo 0); idx=$(( (idx + 1) % 3 )); echo -n $idx > ${clockState}; case $idx in 0) date +%H:%M;; 1) date +\"%a %d %b\";; 2) echo \"W$(date +%-V)\";; esac'";
          }
          # Pomodoro-style focus timer (25/5) via custom_button.
          # Left-click toggles start/pause; the label shows the running state.
          {
            id = "custom_button";
            glyph = "player-play";
            tooltip = "Pomodoro — click to start / pause";
            command = "${bash} -c '${./scripts/pomodoro.sh} toggle'";
          }
        ];
        end = [ "network" "bluetooth" "brightness" "battery" "session" ];
      };
    };
  };
}
