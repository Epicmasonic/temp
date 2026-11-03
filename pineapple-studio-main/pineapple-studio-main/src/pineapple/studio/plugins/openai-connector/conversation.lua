-- Chat state for the AI Assistant, one chat per project.
--   history   messages sent to the provider (no system prompt), in OpenAI chat format; the whole
--             conversation is kept until New Chat
--   items     what the chat panel shows: user/assistant text, tool activity, change summaries
--   prompts   the user's recent prompts, for Up/Down recall
--   lastTurn  files the most recent turn changed, for "Undo AI changes"
local files = require("pineapple.studio.core.files")

local M = {}

local VERSION = 2
local MAX_PROMPTS = 30


local function messageSize(message)
  local size = #tostring(message.content or "")
  for _, call in ipairs(type(message.tool_calls) == "table" and message.tool_calls or {}) do
    local fn = call["function"] or {}
    size = size + #tostring(fn.name or "") + #tostring(fn.arguments or "")
  end
  return size
end

-- Every assistant message that calls tools must be followed by one tool message per call.
-- Adds "cancelled" results for calls that never got one and drops tool messages that don't
-- belong to a call (both make providers reject the whole request).
function M.repair(history)
  local out, i = {}, 1
  while i <= #history do
    local message = history[i]
    i = i + 1
    if message.role ~= "tool" then
      out[#out + 1] = message
      local calls = message.role == "assistant" and type(message.tool_calls) == "table" and message.tool_calls or nil
      if calls and #calls > 0 then
        local wanted, answered = {}, {}
        for _, call in ipairs(calls) do if call.id then wanted[call.id] = true end end
        while history[i] and history[i].role == "tool" do
          local id = history[i].tool_call_id
          if wanted[id] and not answered[id] then
            out[#out + 1] = history[i]
            answered[id] = true
          end
          i = i + 1
        end
        for _, call in ipairs(calls) do
          if call.id and not answered[call.id] then
            out[#out + 1] = { role = "tool", tool_call_id = call.id, content = "Cancelled before this tool ran." }
          end
        end
      end
    end
  end
  return out
end

local function sanitize(saved)
  local chat = { history = {}, items = {}, prompts = {}, lastTurn = nil }
  if type(saved) ~= "table" then return chat end
  for _, message in ipairs(type(saved.history) == "table" and saved.history or {}) do
    if type(message) == "table" and type(message.role) == "string" and message.role ~= "system" then
      chat.history[#chat.history + 1] = message
    end
  end
  chat.history = M.repair(chat.history)
  -- Version 1 stored display messages as `messages` with { role, text }.
  for _, item in ipairs(type(saved.items) == "table" and saved.items or saved.messages or {}) do
    if type(item) == "table" and type(item.role) == "string" then
      chat.items[#chat.items + 1] = {
        role = item.role, text = tostring(item.text or ""), turn = item.turn, undone = item.undone,
        done = item.done,
      }
    end
  end
  for _, prompt in ipairs(type(saved.prompts) == "table" and saved.prompts or {}) do
    if type(prompt) == "string" then chat.prompts[#chat.prompts + 1] = prompt end
  end
  if type(saved.lastTurn) == "table" and type(saved.lastTurn.id) == "string" and type(saved.lastTurn.files) == "table" then
    chat.lastTurn = saved.lastTurn
  end
  return chat
end

local Store = {}
Store.__index = Store

function M.open(path)
  local self = setmetatable({ path = path, data = { version = VERSION, chats = {} } }, Store)
  if not path then return self end
  local ok, data = pcall(files.readTable, path)
  if ok and type(data) == "table" then
    if data.version == VERSION and type(data.chats) == "table" then
      self.data = data
    else
      -- Version 1: the file was a table of chat key -> { history, messages }.
      for key, value in pairs(data) do
        if type(key) == "string" and type(value) == "table" then self.data.chats[key] = value end
      end
    end
  end
  return self
end

function Store:chat(key)
  return sanitize(self.data.chats[key])
end

local function freshCopy(value, depth)
  if type(value) ~= "table" then return value end
  depth = depth or 0
  if depth > 64 then return nil end
  local out = {}
  for k, v in pairs(value) do out[k] = freshCopy(v, depth + 1) end
  return out
end

function Store:put(key, chat)
  -- A fresh copy, so shared tables can't make the serialiser refuse the whole file.
  self.data.chats[key] = freshCopy({
    history = chat.history, items = chat.items, prompts = chat.prompts, lastTurn = chat.lastTurn,
  })
  if self.path then pcall(files.writeTable, self.path, self.data) end
end

function M.addItem(chat, item)
  item.text = tostring(item.text or "")
  chat.items[#chat.items + 1] = item
  return item
end

function M.addPrompt(chat, text)
  if chat.prompts[#chat.prompts] ~= text then chat.prompts[#chat.prompts + 1] = text end
  while #chat.prompts > MAX_PROMPTS do table.remove(chat.prompts, 1) end
end

return M
