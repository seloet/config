local DURATION = 25 * 60
local ICON = "" -- Nerd Fonts: pom-pomodoro_ticking (U+E003)

local remaining = DURATION
local running = false

local function formatTime(seconds)
    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d", minutes, secs)
end

local function render()
    local state = running and "Running" or (remaining == DURATION and "Ready" or "Paused")
    local text = running and (ICON .. " " .. formatTime(remaining)) or ICON
    barWidget.setText(text)
    barWidget.setTooltip("Pomodoro: " .. state .. "\nLeft click: start/pause\nRight click: reset")
end

function update()
    if running and remaining > 0 then
        remaining -= 1
        if remaining == 0 then
            running = false
            noctalia.notify("Pomodoro", "Focus session complete")
        end
    end
    render()
end

function onClick()
    if remaining == 0 then
        remaining = DURATION
    end
    running = not running
    render()
end

function onRightClick()
    running = false
    remaining = DURATION
    render()
end

noctalia.setUpdateInterval(1000)
barWidget.setFont("FiraCode Nerd Font Mono")
render()
