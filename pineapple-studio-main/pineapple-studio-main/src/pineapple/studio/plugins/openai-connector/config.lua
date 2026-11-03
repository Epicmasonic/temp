-- Provider settings and the setup flow. Everything here is read from user settings only:
-- a project's own settings must never choose where the API key is sent, or widen file access.
local M = {}

M.DEFAULT_BASE = "https://api.openai.com/v1"

M.PRESETS = {
  { label = "OpenAI", detail = "api.openai.com", base = "https://api.openai.com/v1", key = true },
  { label = "OpenRouter", detail = "openrouter.ai", base = "https://openrouter.ai/api/v1", key = true },
  { label = "Ollama", detail = "localhost:11434", base = "http://localhost:11434/v1", key = false, mayBeBlocked = true },
  { label = "LM Studio", detail = "localhost:1234", base = "http://localhost:1234/v1", key = false, mayBeBlocked = true },
  { label = "Offline test script", detail = "for testing Studio", script = true },
  { label = "Other...", detail = "any OpenAI-compatible URL", custom = true },
}

local function userValue(settings, key, fallback)
  local value = settings:inspect(key, "user")
  if value == nil then return fallback end
  return value
end
M.userValue = userValue

local function trim(text) return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- { base, model, key, allowOutside, autoApprove, runTimeout }
function M.read(settings)
  return {
    base = trim(userValue(settings, "ai.baseUrl", M.DEFAULT_BASE)),
    model = trim(userValue(settings, "ai.model", "")),
    key = tostring(userValue(settings, "ai.apiKey", "") or ""),
    allowOutside = userValue(settings, "ai.allowOutsideProject", false) == true,
    autoApprove = userValue(settings, "ai.autoApprove", false) == true,
    runTimeout = tonumber(userValue(settings, "ai.runTimeout", 15)) or 15,
  }
end

function M.isConfigured(config) return config.base ~= "" and config.model ~= "" end

local function isLocal(base)
  local host = base:match("^%a+://([^/:]+)")
  return host == "localhost" or host == "127.0.0.1" or host == "[::1]"
end

-- True when an API key would travel unencrypted to another machine.
function M.insecure(config)
  return config.key ~= "" and config.base:match("^http://") ~= nil and not isLocal(config.base)
end

function M.configure(studio, client, onDone)
  local ui, settings = studio.ui, studio.settings
  local current = M.read(settings)

  local function save(base, model, key)
    settings:set("ai.baseUrl", base, "user")
    settings:set("ai.model", model, "user")
    if key ~= nil then settings:set("ai.apiKey", key, "user") end
    local saved = M.read(settings)
    if M.insecure(saved) then
      ui:notify("Warning: " .. base .. " isn't https, so your API key is sent unencrypted.", "warning", 6)
    else
      ui:notify("AI provider saved", "success", 2)
    end
    if onDone then onDone() end
  end

  local function chooseModel(base, key)
    local function typeIt()
      ui:prompt({ title = "Model", message = "Model name, as the provider spells it.", default = current.model },
        function(value)
          if value == nil then return end
          if trim(value) == "" then ui:notify("A model name is required", "warning") return end
          save(base, trim(value), key)
        end)
    end
    ui:notify("Fetching models...", "info", 2)
    client.models({ base = base, key = key or current.key }, function(list)
      if not list then typeIt() return end
      local items = { { label = "Type a model name...", typed = true } }
      for _, id in ipairs(list) do
        items[#items + 1] = { label = id, detail = id == current.model and "current" or nil, model = id }
      end
      ui:quickPick(items, { title = "Model", placeholder = "Model" }, function(item)
        if not item then return end
        if item.typed then typeIt() else save(base, item.model, key) end
      end)
    end)
  end

  local function askKey(base, preset)
    if preset and preset.key == false then chooseModel(base, nil) return end
    ui:prompt({
      title = "API Key",
      message = "Leave empty to keep the saved key. It's stored in your user settings on this computer, never in the project.",
      default = "", secret = true,
    }, function(value)
      if value == nil then return end
      local key = trim(value) ~= "" and trim(value) or nil
      chooseModel(base, key)
    end)
  end

  local items = {}
  for _, preset in ipairs(M.PRESETS) do
    local detail = preset.detail
    if preset.base and preset.base == current.base then detail = detail .. "  (current)" end
    items[#items + 1] = { label = preset.label, detail = detail, preset = preset }
  end
  ui:quickPick(items, { title = "AI Provider", placeholder = "Provider" }, function(item)
    if not item then return end
    local preset = item.preset
    if preset.script then
      ui:prompt({
        title = "Test Script",
        message = "Path of a Lua file returning { replies = { ... } } with one assistant message per request.",
        default = current.base:match("^mock:(.*)") or "/.pineapple/ai-test.lua",
      }, function(value)
        if value == nil or trim(value) == "" then return end
        save("mock:" .. trim(value), "test-script", nil)
      end)
    elseif preset.custom then
      ui:prompt({ title = "API Base URL", message = "OpenAI-compatible base URL, e.g. https://api.example.com/v1",
        default = current.base }, function(value)
        if value == nil then return end
        if trim(value) == "" then ui:notify("A base URL is required", "warning") return end
        askKey(trim(value), nil)
      end)
    else
      if preset.mayBeBlocked then
        ui:notify("CC: Tweaked blocks localhost by default; this works in CraftOS-PC or with an http rule allowing it.", "info", 6)
      end
      askKey(preset.base, preset)
    end
  end)
end

return M
