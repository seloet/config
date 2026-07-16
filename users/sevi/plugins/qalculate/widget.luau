local function render()
  local result = noctalia.state.get("result")
  local expression = noctalia.state.get("expression")
  local busy = noctalia.state.get("busy") == true

  barWidget.setGlyph(busy and "loader" or "calculator")
  if busy then
    barWidget.setText("…")
    barWidget.setTooltip("Qalculate is working…")
  elseif result and result ~= "" then
    barWidget.setText(result)
    barWidget.setTooltip(
      "Qalculate\n" .. (expression or "") .. " = " .. result ..
      "\nLeft click: calculate\nRight click: copy result"
    )
  else
    barWidget.setText("")
    barWidget.setTooltip("Qalculate\nClick to enter a natural-language calculation")
  end
end

noctalia.state.watch("result", function(_value) render() end)
noctalia.state.watch("expression", function(_value) render() end)
noctalia.state.watch("busy", function(_value) render() end)

function onClick()
  noctalia.togglePanel("sevi/qalculate:panel")
end

function onRightClick()
  local result = noctalia.state.get("result")
  if result and result ~= "" then
    noctalia.copyToClipboard(result, "text/plain")
    noctalia.notify("Qalculate", "Result copied")
  else
    noctalia.togglePanel("sevi/qalculate:panel")
  end
end

render()
