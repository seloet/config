local ICON = ""
local TODO_PATH = "/home/severin/gdrive/todo.txt"

local function render()
  barWidget.setText(ICON)
  barWidget.setTooltip("Click to open todo.txt in tuxedo\n" .. TODO_PATH)
end

function onClick()
  noctalia.runInTerminal("tuxedo " .. TODO_PATH)
end

barWidget.setFont("FiraCode Nerd Font Mono")
render()
