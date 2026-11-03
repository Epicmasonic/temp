local function absolute(path)
  if path == "" or path == "." then return "/" end
  if path:sub(1, 1) ~= "/" then return "/" .. path end
  return path
end

local scriptDir = fs.getDir(shell.getRunningProgram())
local projectDir = absolute(fs.combine(scriptDir, "../.."))
local sourceDir = absolute(fs.combine(projectDir, "src"))
local libraryDir = absolute(fs.combine(projectDir, "lib"))
package.path = sourceDir .. "/?.lua;" .. sourceDir .. "/?/init.lua;"
  .. libraryDir .. "/?.lua;" .. libraryDir .. "/?/init.lua;" .. package.path

local args = { ... }
local root
if args[1] and args[1] ~= "" then
  root = shell.resolve(args[1])
  if not fs.isDir(root) then
    printError("Not a folder: " .. root)
    return
  end
end

local studio = require("pineapple.studio")
local ok, err = pcall(studio.run, { root = root })
if not ok then
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  printError("Studio crashed:")
  printError(tostring(err))
end
