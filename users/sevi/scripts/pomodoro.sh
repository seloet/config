#!/usr/bin/env bash
# Noctalia custom_button pomodoro timer.
# No arguments  -> print current timer state (MM:SS + label). This output
#                  becomes the widget's label (refreshed every interval).
# "toggle"      -> start/pause the timer, then print the new state. Bound to
#                  the widget's left-click (command), so clicking updates label.
#
# State lives in ~/.local/state/noctalia-pomodoro so each refresh sees a stable
# value across invocations.
set -u

STATE="${HOME}/.local/state/noctalia-pomodoro"
mkdir -p "$(dirname "$STATE")"

WORK=25
BREAK=5

now() { date +%s; }

read_state() {
  if [ -f "$STATE" ]; then printf '%s\n' "$(cat "$STATE")"; else echo "0 0 work"; fi
}

write_state() { printf '%s\n' "$1" > "$STATE"; }

toggle() {
  read -r running end mode < <(read_state)
  if [ "$running" = "1" ]; then
    rem=$(( end - $(now) )); [ "$rem" -lt 0 ] && rem=0
    write_state "0 $rem $mode"
  else
    read -r _ val mode < <(read_state)
    if [ "${val:-0}" -gt 0 ] 2>/dev/null; then
      end=$(( $(now) + val ))
    else
      if [ "$mode" = "work" ]; then dur=$WORK; else dur=$BREAK; fi
      end=$(( $(now) + dur * 60 ))
    fi
    write_state "1 $end $mode"
  fi
}

show() {
  read -r running end mode < <(read_state)
  if [ "$running" = "1" ]; then
    rem=$(( end - $(now) )); [ "$rem" -lt 0 ] && rem=0
  else
    read -r _ val mode < <(read_state)
    rem=${val:-0}
  fi
  mm=$(( rem / 60 )); ss=$(( rem % 60 ))
  if [ "$mode" = "work" ]; then icon="🍅"; else icon="☕"; fi
  printf '%s %02d:%02d\n' "$icon" "$mm" "$ss"
}

case "${1:-}" in
  toggle) toggle ;;
esac
show
