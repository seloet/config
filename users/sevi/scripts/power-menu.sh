#!/usr/bin/env bash
set -u

choice=$(
  printf '%s\n' Shutdown Reboot Sleep Hibernate |
    fsel --dmenu --no-exec --only-match
)

case "$choice" in
  Shutdown) systemctl poweroff ;;
  Reboot)   systemctl reboot ;;
  Sleep)    systemctl suspend ;;
  Hibernate) systemctl hibernate ;;
esac
