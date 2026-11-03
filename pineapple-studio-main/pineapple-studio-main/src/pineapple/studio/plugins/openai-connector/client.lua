-- HTTP client for OpenAI-compatible chat completions.
--
-- One request is in flight at a time. CC's http events are matched by URL, so after a cancel
-- the old response is still awaited (and ignored) before the next request goes out; otherwise
-- the two could be mixed up. 429 and 5xx responses are retried with backoff.
--
-- A base URL of the form "mock:<path>" uses an offline script instead of a server: the file
-- holds { replies = { <assistant message>, ... } }, returned one per request, in order.
local files = require("pineapple.studio.core.files")

local M = {}

local MAX_ATTEMPTS = 3
local TIMEOUT = 180

-- CC's serialisers refuse a table that appears twice (even without a cycle), which happens
-- easily when tool schemas or messages share tables. Encode a fresh copy instead.
local function freshCopy(value, depth)
  if type(value) ~= "table" then return value end
  depth = depth or 0
  if depth > 64 then error("The data is nested too deeply (or refers to itself)", 0) end
  local out = {}
  for k, v in pairs(value) do out[k] = freshCopy(v, depth + 1) end
  return out
end
M.freshCopy = freshCopy

local function encode(value) return (textutils.serializeJSON or textutils.serialiseJSON)(freshCopy(value)) end
local function decode(value) return (textutils.unserializeJSON or textutils.unserialiseJSON)(value) end
M.encode, M.decode = encode, decode

local function readBody(response)
  if not response then return nil end
  local ok, body = pcall(response.readAll)
  pcall(response.close)
  if ok then return body end
end

local function errorMessage(body, fallback)
  local ok, value = pcall(decode, body or "")
  if ok and type(value) == "table" and type(value.error) == "table" and value.error.message then
    return tostring(value.error.message)
  end
  if ok and type(value) == "table" and type(value.error) == "string" then return value.error end
  return fallback
end

local function endpoint(base, path)
  base = base:gsub("/+$", "")
  if path == "/chat/completions" and base:match("/chat/completions$") then return base end
  return base .. path
end
M.endpoint = endpoint

function M.new(studio)
  local self = { pending = nil, queued = nil, mockIndex = 0 }
  local ui = studio.ui

  local function headers(key)
    local h = { ["Content-Type"] = "application/json" }
    if key and key ~= "" then h.Authorization = "Bearer " .. key end
    return h
  end

  local start

  local function finish(p, reply, err)
    if self.pending == p then self.pending = nil end
    if not p.cancelled then pcall(p.callback, reply, err) end
    if not self.pending and self.queued then
      local q = self.queued
      self.queued = nil
      start(q)
    end
  end

  function start(p)
    self.pending = p
    p.attempts = (p.attempts or 0) + 1
    local ok, accepted, err = pcall(http.request, {
      url = p.url, method = p.method, headers = p.headers, body = p.body, timeout = TIMEOUT,
    })
    if not ok then finish(p, nil, tostring(accepted)) return end
    if accepted == false then finish(p, nil, tostring(err or "The HTTP request was rejected")) end
  end

  local function retryDelay(p, response)
    local after
    if response and response.getResponseHeaders then
      local ok, h = pcall(response.getResponseHeaders)
      if ok and type(h) == "table" then after = tonumber(h["Retry-After"] or h["retry-after"]) end
    end
    return math.min(30, after or (2 * 2 ^ (p.attempts - 1)))
  end

  ui:onRawEvent(function(event, url, a, b)
    local p = self.pending
    if not p or p.mock or url ~= p.url then return end
    if event == "http_success" then
      local body = readBody(a)
      local ok, value = pcall(decode, body or "")
      if not ok or type(value) ~= "table" then
        finish(p, nil, "Couldn't read the provider's response: " .. tostring(body or ""):sub(1, 300))
      else
        finish(p, value, nil)
      end
    elseif event == "http_failure" then
      local response = b
      local code = response and response.getResponseCode and select(2, pcall(response.getResponseCode))
      code = tonumber(code)
      if not p.cancelled and code and (code == 429 or code >= 500) and p.attempts < MAX_ATTEMPTS then
        local delay = retryDelay(p, response)
        readBody(response)
        p.retrying = true
        if p.onRetry then pcall(p.onRetry, p.attempts, delay, code) end
        p.timer = studio.timers:after(delay, function()
          p.timer, p.retrying = nil, false
          if p.cancelled then finish(p, nil, "Cancelled") else start(p) end
        end)
        return
      end
      local message = errorMessage(readBody(response), tostring(a or "The HTTP request failed"))
      if code then message = message .. " (HTTP " .. code .. ")" end
      finish(p, nil, message)
    end
  end)

  local function mockReply(p, path)
    local ok, script = pcall(files.readTable, path)
    if not ok or type(script) ~= "table" or type(script.replies) ~= "table" then
      return finish(p, nil, "The test script " .. path .. " needs { replies = { ... } }")
    end
    self.mockIndex = self.mockIndex + 1
    local message = script.replies[self.mockIndex]
    if type(message) ~= "table" then
      message = { role = "assistant", content = "(The test script has no more replies.)" }
    end
    message.role = message.role or "assistant"
    finish(p, { choices = { { message = message } }, usage = { total_tokens = 0 } }, nil)
  end

  -- Sends a request and calls callback(replyTable, err) once, unless cancelled first.
  -- options.onRetry(attempt, delaySeconds, httpCode) reports retries.
  function self.request(config, method, path, body, callback, options)
    local p = {
      callback = callback, method = method,
      headers = headers(config.key), onRetry = options and options.onRetry,
    }
    if body then
      local ok, encoded = pcall(encode, body)
      if not ok then
        pcall(callback, nil, "Couldn't prepare the request: " .. tostring(encoded))
        return p
      end
      p.body = encoded
    end
    if config.base:match("^mock:") then
      p.mock = true
      local scriptPath = config.base:sub(6)
      self.pending = p
      p.timer = studio.timers:after(0.2, function() p.timer = nil; mockReply(p, scriptPath) end)
      return p
    end
    p.url = endpoint(config.base, path)
    if self.pending then
      if self.queued then self.queued.cancelled = true end
      self.queued = p
    else
      start(p)
    end
    return p
  end

  function self.chat(config, body, callback, options)
    return self.request(config, "POST", "/chat/completions", body, callback, options)
  end

  -- Lists model ids from GET /models; callback(list) with nil on failure.
  function self.models(config, callback)
    if config.base:match("^mock:") then callback({ "test-script" }) return end
    return self.request(config, "GET", "/models", nil, function(reply)
      local list = {}
      for _, model in ipairs(type(reply) == "table" and type(reply.data) == "table" and reply.data or {}) do
        if type(model) == "table" and type(model.id) == "string" then list[#list + 1] = model.id end
      end
      table.sort(list)
      callback(#list > 0 and list or nil)
    end)
  end

  -- Stops caring about the current request. Its response is ignored when it arrives.
  function self.cancel()
    if self.queued then self.queued.cancelled = true; self.queued = nil end
    local p = self.pending
    if not p then return end
    p.cancelled = true
    if p.timer then
      p.timer:dispose()
      p.timer = nil
      self.pending = nil
    elseif p.mock then
      self.pending = nil
    end
  end

  function self.resetScript() self.mockIndex = 0 end

  function self.busy() return self.pending ~= nil and not self.pending.cancelled end

  return self
end

return M
