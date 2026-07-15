#!/usr/bin/env bash
# Pomodoro focus timer — launched from the noctalia bar (ghostty window).
# 25 min work / 5 min break, looping. Press 'q' or Ctrl-C to quit.
# Live MM:SS countdown is drawn in the terminal; a desktop notification fires
# at each phase change.
set -u

WORK=25
BREAK=5

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$1" "$2" 2>/dev/null
  fi
}

phase() {
  local name="$1" mins="$2"
  local total mm ss rem ch=""
  total=$(( mins * 60 ))
  rem=$total
  notify "Pomodoro" "$name — $mins min"
  while [ "$rem" -gt 0 ]; do
    mm=$(( rem / 60 )); ss=$(( rem % 60 ))
    printf '\r\033[K%s %02d:%02d  (q to quit)' "$name" "$mm" "$ss"
    sleep 1
    rem=$(( rem - 1 ))
    # quit on 'q' if a key was pressed (non-blocking)
    if read -r -t 0 -n 1 ch 2>/dev/null; then
      if [ "$ch" = "q" ]; then
        printf '\nBye.\n'; exit 0
      fi
    fi
  done
  printf '\n'
}

while true; do
  phase "🍅 Work" "$WORK"
  phase "☕ Break" "$BREAK"
done
