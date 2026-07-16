local query = ""
local expression = ""
local result = ""
local status = "Ask a calculation in plain language."
local busy = false
local inputKey = 0

local function render()
  local resultChildren = {}
  if expression ~= "" then
    table.insert(resultChildren, ui.label({
      text = expression,
      color = "on_surface_variant",
      maxLines = 2,
    }))
  end
  if result ~= "" then
    table.insert(resultChildren, ui.label({
      text = result,
      fontSize = 24,
      fontWeight = "bold",
      color = "primary",
      maxLines = 3,
    }))
  end

  panel.render(ui.column({ flexGrow = 1, gap = 16 }, {
    ui.row({ align = "center", justify = "space_between", gap = 8 }, {
      ui.row({ align = "center", gap = 8, flexGrow = 1 }, {
        ui.glyph({ name = "calculator", size = 20, color = "primary" }),
        ui.label({ text = "Qalculate", fontSize = 16, fontWeight = "bold" }),
      }),
      ui.button({ glyph = "close", variant = "ghost", onClick = "onCloseClicked" }),
    }),
    ui.input({
      key = "query-" .. tostring(inputKey),
      value = query,
      placeholder = "e.g. convert 100 kilometers to miles",
      focus = true,
      enabled = not busy,
      controlSize = "lg",
      onChange = "onQueryChanged",
      onSubmit = "onSubmit",
    }),
    ui.row({ gap = 8 }, {
      ui.button({
        text = busy and "Calculating…" or "Calculate",
        glyph = busy and "loader" or "equal",
        variant = "primary",
        enabled = not busy and noctalia.string.trim(query) ~= "",
        flexGrow = 1,
        onClick = "onCalculateClicked",
      }),
      ui.button({
        glyph = "copy",
        tooltip = "Copy result",
        enabled = result ~= "",
        onClick = "onCopyClicked",
      }),
      ui.button({ glyph = "trash", tooltip = "Clear", onClick = "onClearClicked" }),
    }),
    ui.column({
      flexGrow = 1,
      gap = 8,
      padding = 14,
      fill = "surface_variant/0.45",
      radius = 10,
      align = "stretch",
    }, #resultChildren > 0 and resultChildren or {
      ui.label({ text = status, color = "on_surface_variant", maxLines = 3 }),
    }),
    ui.label({ text = status, color = busy and "primary" or "on_surface_variant", maxLines = 2 }),
  }))
end

local function calculate()
  local trimmed = noctalia.string.trim(query)
  if busy or trimmed == "" then return end

  local body, encodeError = noctalia.json.encode({ query = trimmed })
  if body == nil then
    status = "Could not encode request: " .. tostring(encodeError)
    render()
    return
  end

  busy = true
  status = "Calculating…"
  noctalia.state.set("busy", true)
  render()

  local accepted = noctalia.http({
    url = noctalia.getConfig("endpoint"),
    method = "POST",
    body = body,
    headers = { "Content-Type: application/json", "Accept: application/json" },
  }, function(response)
    busy = false
    noctalia.state.set("busy", false)

    if not response.ok then
      status = response.status == 0
        and "Service unavailable. Start qalc-needle on port 8765."
        or "Request failed with HTTP " .. tostring(response.status)
      noctalia.notifyError("Qalculate", status)
      render()
      return
    end

    local payload, decodeError = noctalia.json.decode(response.body)
    if payload == nil then
      status = "Invalid server response: " .. tostring(decodeError)
      render()
      return
    end
    if payload.error then
      status = tostring(payload.error)
      noctalia.notifyError("Qalculate", status)
      render()
      return
    end

    expression = tostring(payload.expression or "")
    result = tostring(payload.result or "")
    local latency = payload.latency_ms and payload.latency_ms.total
    status = latency and ("Completed in " .. tostring(latency) .. " ms") or "Completed"
    noctalia.state.set("expression", expression)
    noctalia.state.set("result", result)
    render()
  end)

  if not accepted then
    busy = false
    noctalia.state.set("busy", false)
    status = "Noctalia could not start the HTTP request."
    render()
  end
end

function onOpen(_context)
  expression = tostring(noctalia.state.get("expression") or "")
  result = tostring(noctalia.state.get("result") or "")
  render()
end

function onQueryChanged(value) query = value end
function onSubmit(value) query = value; calculate() end
function onCalculateClicked() calculate() end

function onCopyClicked()
  if result ~= "" then
    noctalia.copyToClipboard(result, "text/plain")
    status = "Result copied to clipboard."
    render()
  end
end

function onClearClicked()
  query = ""
  expression = ""
  result = ""
  status = "Ask a calculation in plain language."
  inputKey += 1
  noctalia.state.set("expression", "")
  noctalia.state.set("result", "")
  render()
end

function onCloseClicked() panel.close() end

