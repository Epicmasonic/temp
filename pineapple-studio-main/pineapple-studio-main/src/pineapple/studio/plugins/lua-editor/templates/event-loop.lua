local running = true

while running do
  local event, a, b, c = os.pullEvent()
  if event == "key" and a == keys.q then
    running = false
  elseif event == "mouse_click" then
    print("Clicked at " .. b .. ", " .. c)
  end
end
