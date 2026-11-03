local disposable = require("pineapple.studio.core.disposable")

local M = {}

local MODIFIERS = {
  leftctrl = "ctrl", rightctrl = "ctrl",
  leftshift = "shift", rightshift = "shift",
  leftalt = "alt", rightalt = "alt",
}
local ORDER = { "ctrl", "alt", "shift" }

function M.normalize(chord)
  if type(chord) ~= "string" or chord == "" then error("invalid key chord: " .. tostring(chord), 2) end
  local mods, key = {}, nil
  for part in chord:lower():gmatch("[^+]+") do
    part = part:gsub("^%s+", ""):gsub("%s+$", "")
    if part == "ctrl" or part == "alt" or part == "shift" then
      mods[part] = true
    elseif key then
      error("key chord has two non-modifier keys: " .. chord, 2)
    else
      key = part
    end
  end
  if not key then error("key chord has no key: " .. chord, 2) end
  local out = {}
  for _, m in ipairs(ORDER) do if mods[m] then out[#out + 1] = m end end
  out[#out + 1] = key
  return table.concat(out, "+")
end

local Bindings = {}
Bindings.__index = Bindings

function M.new(commands, getName)
  return setmetatable({
    _commands = commands,
    _getName = getName or (keys and keys.getName),
    _all = {},
    _index = nil,
    _keymap = {},
    _overrides = {},
    _down = { ctrl = false, alt = false, shift = false },
    _swallowChar = false,
    _capture = nil,
    onError = nil,
  }, Bindings)
end

local function chordList(value)
  if value == nil then return nil end
  if value == false then return {} end
  if type(value) == "string" then return { M.normalize(value) } end
  local out = {}
  for _, c in ipairs(value) do out[#out + 1] = M.normalize(c) end
  return out
end

function Bindings:_remap(commandId)
  local v = self._overrides[commandId]
  if v ~= nil then return chordList(v) end
  v = self._keymap[commandId]
  if v ~= nil then return chordList(v) end
  return nil
end

function Bindings:_rebuild()
  local index = {}
  local function push(chord, b)
    local stack = index[chord]
    if not stack then stack = {}; index[chord] = stack end
    stack[#stack + 1] = b
  end

  local remapped = {}
  for _, b in ipairs(self._all) do
    local chords = remapped[b.command]
    if chords == nil then chords = self:_remap(b.command) or false; remapped[b.command] = chords end
    if chords then
      for _, c in ipairs(chords) do push(c, b) end
    else
      push(b.chord, b)
    end
  end

  local function extra(map)
    for id, v in pairs(map) do
      if remapped[id] == nil and not (map == self._keymap and self._overrides[id] ~= nil) then
        local chords = chordList(v) or {}
        remapped[id] = chords
        for _, c in ipairs(chords) do push(c, { command = id, chord = c }) end
      end
    end
  end
  extra(self._overrides)
  extra(self._keymap)
  self._index = index
end

function Bindings:_stack(chord)
  if not self._index then self:_rebuild() end
  return self._index[chord]
end

function Bindings:bind(chord, commandId, when)
  local b = { chord = M.normalize(chord), command = commandId, when = when }
  local all = self._all
  all[#all + 1] = b
  self._index = nil
  return disposable.new(function()
    for i = #all, 1, -1 do
      if all[i] == b then table.remove(all, i) break end
    end
    self._index = nil
  end)
end

function Bindings:setKeymap(map)
  self._keymap = map or {}
  self._index = nil
end

function Bindings:setOverrides(map)
  self._overrides = map or {}
  self._index = nil
end

function Bindings:lookup(chord)
  local stack = self:_stack(M.normalize(chord))
  if not stack then return nil end
  local fallback
  for i = #stack, 1, -1 do
    local b = stack[i]
    if not b.when or b.when() ~= false then
      local cmds = self._commands
      if not cmds or not cmds.isEnabled or not cmds:has(b.command) or cmds:isEnabled(b.command) then
        return b.command
      end
      fallback = fallback or b.command
    end
  end
  return fallback
end

function Bindings:chordsFor(commandId)
  if not self._index then self:_rebuild() end
  local out, seen = {}, {}
  for chord, stack in pairs(self._index) do
    for _, b in ipairs(stack) do
      if b.command == commandId and not seen[chord] then seen[chord] = true; out[#out + 1] = chord end
    end
  end
  table.sort(out, function(a, b) if #a ~= #b then return #a < #b end return a < b end)
  return out
end

function Bindings:chordFor(commandId)
  return self:chordsFor(commandId)[1]
end

function Bindings:defaultChordsFor(commandId)
  local out, seen = {}, {}
  for _, b in ipairs(self._all) do
    if b.command == commandId and not seen[b.chord] then seen[b.chord] = true; out[#out + 1] = b.chord end
  end
  table.sort(out, function(a, b) if #a ~= #b then return #a < #b end return a < b end)
  return out
end

function Bindings:boundCommands()
  local seen, out = {}, {}
  for _, b in ipairs(self._all) do if not seen[b.command] then seen[b.command] = true; out[#out + 1] = b.command end end
  for _, map in ipairs({ self._keymap, self._overrides }) do
    for id in pairs(map) do if not seen[id] then seen[id] = true; out[#out + 1] = id end end
  end
  return out
end

function Bindings:commandsOn(chord)
  local stack = self:_stack(M.normalize(chord)) or {}
  local out, seen = {}, {}
  for _, b in ipairs(stack) do
    if not seen[b.command] then seen[b.command] = true; out[#out + 1] = b.command end
  end
  return out
end

function Bindings:capture(fn)
  self._capture = fn
  return function() if self._capture == fn then self._capture = nil end end
end

function Bindings:isCapturing() return self._capture ~= nil end

function Bindings:isDown(modifier)
  return self._down[modifier] == true
end

function Bindings:handle(event, a)
  if event == "char" and self._swallowChar then
    self._swallowChar = false
    return true
  end
  self._swallowChar = false

  if event == "key_up" then
    local name = self._getName and self._getName(a)
    local mod = name and MODIFIERS[name:lower()]
    if mod then self._down[mod] = false end
    return false
  end
  if event ~= "key" then return false end

  local name = self._getName and self._getName(a)
  if not name then return false end
  local lower = name:lower()
  local mod = MODIFIERS[lower]
  if mod then
    self._down[mod] = true
    return false
  end

  local parts = {}
  for _, m in ipairs(ORDER) do if self._down[m] then parts[#parts + 1] = m end end
  parts[#parts + 1] = lower
  local chord = table.concat(parts, "+")

  if self._capture then
    local fn = self._capture
    self._capture = nil
    self._swallowChar = true
    local ok, err = pcall(fn, chord)
    if not ok and self.onError then self.onError(err, "capture") end
    return true
  end

  local command = self:lookup(chord)
  if not command then return false end

  self._swallowChar = not (self._down.ctrl or self._down.alt)
  local ok, err = pcall(self._commands.execute, self._commands, command)
  if not ok and self.onError then self.onError(err, command) end
  return true
end

return M
