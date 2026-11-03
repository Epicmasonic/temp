-- Languages the code editor knows how to colour, looked up by file extension.
--   tokenize(line, state) -> tokens, endState  (see lexer.lua for the token shape)
--   structure = "lua" turns on Lua-aware editing: block matching, folding by block,
--   auto-indent and auto-inserted `end`. Languages without it only get colours.
local lexer = require("pineapple.studio.ui.codeedit.lexer")
local xml = require("pineapple.studio.ui.codeedit.xmllexer")

local M = {}
local byId, byExtension = {}, {}

function M.register(spec)
  if type(spec) ~= "table" or type(spec.id) ~= "string" or type(spec.tokenize) ~= "function" then
    error("language needs an id and a tokenize function", 2)
  end
  byId[spec.id] = spec
  for _, ext in ipairs(spec.extensions or {}) do byExtension[ext:lower()] = spec end
  return spec
end

function M.get(id) return byId[id] end

function M.forPath(path)
  local ext = type(path) == "string" and path:match("%.([%w_]+)$")
  return ext and byExtension[ext:lower()] or nil
end

M.register({ id = "lua", title = "Lua", extensions = { "lua", "view" }, tokenize = lexer.tokenize, structure = "lua" })
M.register({ id = "xml", title = "XML", extensions = { "xml" }, tokenize = xml.tokenize })

return M
