local basalt = require("basalt")

local main = basalt.getMainFrame()

main:addLabel({ x = 2, y = 2, text = "Hello from Basalt!" })
main:addButton({ x = 2, y = 4, text = "Quit" })
  :onClick(function() basalt.stop() end)

basalt.run()
