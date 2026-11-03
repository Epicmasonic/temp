local images = require("images")

local plugin = {}

local EXTENSIONS = { nfp = true, nft = true, bimg = true }

function plugin.activate(ctx)
  local studio = ctx.studio

  studio.editors:register({
    id = "pineapple.image-viewer",
    title = "Image Viewer",
    score = function(path)
      local ext = path:match("%.(%w+)$")
      return (ext and EXTENSIONS[ext:lower()]) and 10 or 0
    end,
    create = function(host, doc, opts)
      local theme = opts.theme
      local image, err
      local frame, playing, timer = 1, false, nil
      local scrollX, scrollY = 0, 0
      local view
      local dragging
      local canvas
      local hits = {}

      local function reload()
        image, err = images.load(doc.path, table.concat(doc.lines, "\n"))
        if image then frame = math.min(frame, #image.frames) end
        if canvas then canvas:markRenderDirty() end
      end

      local function stopTimer()
        if timer then timer:dispose(); timer = nil end
      end
      local function setPlaying(on)
        stopTimer()
        playing = on and image ~= nil and #image.frames > 1
        if playing then
          timer = studio.timers:every(math.max(0.05, image.secondsPerFrame or 0.5), function()
            frame = frame % #image.frames + 1
            canvas:markRenderDirty()
          end)
        end
        canvas:markRenderDirty()
      end

      local function step(delta)
        if not image then return end
        setPlaying(false)
        frame = (frame - 1 + delta) % #image.frames + 1
        canvas:markRenderDirty()
      end

      local function draw(_, buf)
        local w, h = canvas.width, canvas.height
        local bg = theme.editorBackground
        local barBg, barFg = theme.panelHeaderBackground, theme.panelHeaderForeground
        hits = {}
        buf:fill(1, 1, w, h, " ", theme.foreground, bg)

        buf:fill(1, 1, w, 1, " ", barFg, barBg)
        local name = fs.getName(doc.path)
        local info = image and (" " .. name .. "  " .. image.width .. "x" .. image.height .. "  " .. image.format)
          or (" " .. name)
        local controls = image and #image.frames > 1
          and (" < " .. frame .. "/" .. #image.frames .. " > " .. (playing and "Pause " or "Play ")) or ""
        if #info + #controls + 1 > w then info = " " .. name end
        buf:blit(1, 1, info:sub(1, w), barFg, barBg)
        if controls ~= "" then
          local x = w - #controls + 1
          if x > #info + 1 then
            buf:blit(x, 1, controls, theme.tabActiveForeground, theme.tabActiveBackground)
            hits[#hits + 1] = { x1 = x, x2 = x + 2, action = function() step(-1) end }
            local nx = x + 3 + #(frame .. "/" .. #image.frames)
            hits[#hits + 1] = { x1 = nx, x2 = nx + 2, action = function() step(1) end }
            hits[#hits + 1] = { x1 = nx + 3, x2 = w, action = function() setPlaying(not playing) end }
          end
        end

        if not image then
          buf:blit(2, 3, ("Can't show this image: " .. tostring(err)):sub(1, w - 2), colors.red, bg)
          buf:blit(2, 4, ("Reopen With > Code Editor to edit it as text."):sub(1, w - 2), theme.muted, bg)
          return
        end

        local needV = image.height > h - 1
        local needH = image.width > w - (needV and 1 or 0)
        needV = image.height > h - 1 - (needH and 1 or 0)
        local viewW, viewH = w - (needV and 1 or 0), h - 1 - (needH and 1 or 0)
        view = { w = viewW, h = viewH, needV = needV, needH = needH, totalW = w, totalH = h }
        local maxX, maxY = math.max(0, image.width - viewW), math.max(0, image.height - viewH)
        scrollX, scrollY = math.max(0, math.min(scrollX, maxX)), math.max(0, math.min(scrollY, maxY))
        local ox = image.width <= viewW and math.floor((viewW - image.width) / 2) or -scrollX
        local oy = 1 + (image.height <= viewH and math.floor((viewH - image.height) / 2) or -scrollY)
        local areaH = viewH
        w = viewW
        local checker = studio.settings:get("imageViewer.checkerboard", true)
        local rows = image.frames[frame]
        local map = images.paletteMap(rows.palette)
        for y = 1, image.height do
          local sy = oy + y
          if sy >= 2 and sy <= areaH + 1 then
            local row = rows[y] or { "", "", "" }
            local text, fgs, bgs = {}, {}, {}
            local count = 0
            for x = 1, image.width do
              local sx = ox + x
              if sx >= 1 and sx <= w then
                count = count + 1
                if count == 1 then text.start = sx end
                local ch = row[1]:sub(x, x)
                local f, b = row[2]:sub(x, x), row[3]:sub(x, x)
                local bcol = images.colour(map[b] or b)
                local fcol = images.colour(map[f] or f) or colors.white
                if not bcol then

                  local dark = (x + y) % 2 == 0
                  bcol = checker and (dark and colors.lightGray or colors.white) or bg
                  if ch == "" or ch == " " then ch = " " end
                end
                if ch == "" then ch = " " end
                text[count], fgs[count], bgs[count] = ch, fcol, bcol
              end
            end
            if count > 0 then buf:colorBlit(text.start, sy, table.concat(text), fgs, bgs) end
          end
        end

        local track, thumb = theme.scrollbarTrack or colors.lightGray, theme.scrollbarThumb or colors.gray
        if needV then
          local size = math.max(1, math.floor(viewH * viewH / image.height))
          local start = math.floor((viewH - size) * scrollY / math.max(1, maxY) + 0.5)
          for row = 1, viewH do
            local on = row - 1 >= start and row - 1 < start + size
            buf:blit(view.totalW, row + 1, " ", colors.white, on and thumb or track)
          end
        end
        if needH then
          local size = math.max(1, math.floor(viewW * viewW / image.width))
          local start = math.floor((viewW - size) * scrollX / math.max(1, maxX) + 0.5)
          for col = 1, viewW do
            local on = col - 1 >= start and col - 1 < start + size
            buf:blit(col, view.totalH, " ", colors.white, on and thumb or track)
          end
        end
      end

      canvas = host:addCanvas({
        x = 1, y = 1,
        width = function() return host.width end,
        height = function() return host.height end,
        background = theme.editorBackground,
        draw = draw,
      })

      local function jump(x, y)
        if not view or not image then return false end
        if view.needV and x == view.totalW and y >= 2 then
          scrollY = math.floor((y - 2) / math.max(1, view.h - 1) * (image.height - view.h) + 0.5)
          return true
        end
        if view.needH and y == view.totalH then
          scrollX = math.floor((x - 1) / math.max(1, view.w - 1) * (image.width - view.w) + 0.5)
          return true
        end
        return false
      end
      canvas:onClick(function(_, _, x, y)
        canvas:focus()
        if y == 1 then
          for _, hit in ipairs(hits) do
            if x >= hit.x1 and x <= hit.x2 then hit.action() return end
          end
          return
        end
        if jump(x, y) then dragging = { bar = true }; canvas:markRenderDirty() return end
        dragging = { x = x, y = y, sx = scrollX, sy = scrollY }
      end)
      canvas:onDrag(function(_, _, x, y)
        if not dragging then return end
        if dragging.bar then jump(x, y)
        else
          scrollX = dragging.sx - (x - dragging.x)
          scrollY = dragging.sy - (y - dragging.y)
        end
        canvas:markRenderDirty()
      end)
      canvas:onClickUp(function() dragging = nil end)
      canvas:onScroll(function(_, dir)
        local root = canvas:getRoot()
        local shift = root.isKeyDown and (root:isKeyDown(keys.leftShift) or root:isKeyDown(keys.rightShift))
        if shift then scrollX = scrollX + dir * 3 else scrollY = scrollY + dir end
        canvas:markRenderDirty()
      end)
      canvas:onKey(function(_, key)
        local pageH = view and view.h or 5
        if key == keys.left then scrollX = scrollX - 2
        elseif key == keys.right then scrollX = scrollX + 2
        elseif key == keys.up then scrollY = scrollY - 1
        elseif key == keys.down then scrollY = scrollY + 1
        elseif key == keys.pageUp then scrollY = scrollY - pageH
        elseif key == keys.pageDown then scrollY = scrollY + pageH
        elseif key == keys.home then scrollX, scrollY = 0, 0
        elseif key == keys.comma or key == keys.leftBracket then step(-1)
        elseif key == keys.period or key == keys.rightBracket then step(1)
        elseif key == keys.space then setPlaying(not playing)
        else return end
        canvas:markRenderDirty()
      end)

      reload()
      local listener = doc:on("change", reload)
      if image and image.animated and #image.frames > 1 then setPlaying(true) end

      return {
        focus = function() canvas:focus() end,
        applyTheme = function(_, t) theme = t; canvas.background = t.editorBackground; canvas:markRenderDirty() end,
        dispose = function()
          stopTimer()
          listener:dispose()
          canvas:destroy()
        end,

        image = function() return image, err end,
        frame = function() return frame end,
        playing = function() return playing end,
        scroll = function() return scrollX, scrollY end,
      }
    end,
  })
end

return plugin
