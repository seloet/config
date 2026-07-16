-- opens ~/gdrive/todo.txt (rclone mount) in tuxedo from the bar
local ICON = "" -- Nerd Fonts: nf-fa-list (U+F0CA)
local TODO_PATH = "/home/severin/gdrive/todo.txt"

local function render()
  barWidget.setText(ICON .. " TODO")
  barWidget.setTooltip("Click to open todo.txt in tuxedo\n" .. TODO_PATH)
end

function onClick()
  -- runInTerminal (not runAsync): tuxedo is a TUI and needs a real PTY
  noctalia.runInTerminal("tuxedo " .. TODO_PATH)
end

barWidget.setFont("FiraCode Nerd Font Mono")
render()
