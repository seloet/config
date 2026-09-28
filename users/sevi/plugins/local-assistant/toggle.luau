local ACTIVE_ICON = ""
local INACTIVE_ICON = ""
local UNIT = "local-assistant.service"

local active = false

local function render()
  if active then
    barWidget.setText(ACTIVE_ICON)
    barWidget.setTooltip(
      "LocalAssistant is on\nClick to stop it for this session\n" ..
      "It stays off at the next login."
    )
  else
    barWidget.setText(INACTIVE_ICON)
    barWidget.setTooltip("LocalAssistant is off\nClick to start it")
  end
end

function onClick()
  local action = active and "stop" or "start"
  local state = active and "stopped" or "started"
  local command =
    "if systemctl --user " .. action .. " " .. UNIT ..
    "; then notify-send --app-name=LocalAssistant 'LocalAssistant' " ..
    "'Service " .. state .. "'; else notify-send --urgency=critical " ..
    "--app-name=LocalAssistant 'LocalAssistant' 'Could not " .. action ..
    " service'; fi"

  noctalia.runAsync(command)
  active = not active
  render()
end

barWidget.setFont("FiraCode Nerd Font Mono")
render()
