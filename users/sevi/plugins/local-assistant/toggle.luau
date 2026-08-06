-- Starts/stops the Home Manager LocalAssistant user service for this session.
-- The service remains enabled in Home Manager, so it starts again at the next
-- graphical login. Noctalia's command API is detached, so the widget reflects
-- the requested state immediately and the controller reports any failure via a
-- desktop notification.

local ACTIVE_ICON = "" -- Nerd Fonts: nf-fa-microphone (U+F130)
local INACTIVE_ICON = "" -- Nerd Fonts: nf-fa-microphone_slash (U+F131)
local UNIT = "local-assistant.service"

local active = true

local function render()
  if active then
    barWidget.setText(ACTIVE_ICON)
    barWidget.setTooltip(
      "LocalAssistant is on\nClick to stop it for this session\n" ..
      "It will start again at the next login."
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
