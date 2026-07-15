#!/usr/bin/env bash
# Power menu launched from Hyprland ($mod+ESC).
# Pipes the three choices into fsel's dmenu mode and acts on the selection.
# fsel --dmenu reads lines from stdin; --no-exec prints the chosen line to
# stdout instead of launching it, so we can branch on it here.
set -u

choice=$(printf '%s\n' Shutdown Reboot Suspend | fsel --dmenu --no-exec)

case "$choice" in
  Shutdown) systemctl poweroff ;;
  Reboot)   systemctl reboot ;;
  Suspend)  systemctl suspend ;;
esac
