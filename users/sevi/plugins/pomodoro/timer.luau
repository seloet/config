local FOCUS_DURATION = POMODORO_FOCUS_SECONDS or (25 * 60)
local BREAK_DURATION = POMODORO_BREAK_SECONDS or (5 * 60)
local ICON = ""

local phase = "focus"
local remaining = FOCUS_DURATION
local running = false

local function formatTime(seconds)
    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d", minutes, secs)
end

local function render()
    local phaseName = phase == "focus" and "Focus" or "Break"
    local state = running and "running" or "paused"
    barWidget.setText(ICON .. " " .. formatTime(remaining))
    barWidget.setTooltip(phaseName .. ": " .. state .. "\nLeft click: pause/resume\nRight click: reset focus")
end

function update()
    if running and remaining > 0 then
        remaining = remaining - 1
        if remaining == 0 then
            if phase == "focus" then
                noctalia.notify("Pomodoro", "Focus complete — break started")
                phase = "break"
                remaining = BREAK_DURATION
            else
                noctalia.notify("Pomodoro", "Break complete — focus started")
                phase = "focus"
                remaining = FOCUS_DURATION
            end
        end
    end
    render()
end

function onClick()
    running = not running
    render()
end

function onRightClick()
    running = false
    phase = "focus"
    remaining = FOCUS_DURATION
    render()
end

noctalia.setUpdateInterval(1000)
barWidget.setFont("FiraCode Nerd Font Mono")
render()
