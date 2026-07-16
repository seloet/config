-- Click-to-open todo.txt (on the rclone GDrive mount) with tuxedo.
-- Mirrors the sevi/pomodoro plugin: a bar widget with an onClick() callback
-- that launches a terminal editor via noctalia.runInTerminal.

local ICON = "" -- Nerd Fonts: nf-fa-list (U+F0CA)
local TODO_PATH = "/home/severin/gdrive/todo.txt"

local function render()
  barWidget.setText(ICON .. " TODO")
  barWidget.setTooltip("Click to open todo.txt in tuxedo\n" .. TODO_PATH)
end

function onClick()
  -- runInTerminal (not runAsync): tuxedo is a TUI editor and needs a real
  -- PTY/terminal. runAsync spawns detached with no TTY, so it exits instantly.
  -- runInTerminal launches via $TERMINAL (ghostty) and shows the editor.
  noctalia.runInTerminal("tuxedo " .. TODO_PATH)
end

barWidget.setFont("FiraCode Nerd Font Mono")
render()
