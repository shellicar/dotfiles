require("hs.ipc")
hs.window.animationDuration = 0

--------------------------------------------------------------------------------
-- Zone layout manager (FancyZones-style window tiling).
-- Comment out the next line to disable ALL layout-switch / zone-snap hotkeys.
-- Everything below this stays active regardless.
--------------------------------------------------------------------------------

-- require("zones")

--------------------------------------------------------------------------------
-- Manual window placement (independent of the zone manager, and of macOS's own
-- tiling — these are plain AX resizes, no fn key involved).
--   Ctrl+Opt+Left  -> left half
--   Ctrl+Opt+Right -> right half
--   Ctrl+Opt+F     -> maximize
--------------------------------------------------------------------------------

-- Resolve the focused window, falling back via the frontmost application.
local function focusedWindow()
  local win = hs.window.focusedWindow()
  if win then return win end
  local app = hs.application.frontmostApplication()
  if app then return app:focusedWindow() or app:mainWindow() end
  return nil
end

local function place(apply)
  return function()
    local win = focusedWindow()
    if win then apply(win) end
  end
end

hs.hotkey.bind({ "ctrl", "alt" }, "left",  place(function(w) w:moveToUnit(hs.geometry.rect(0, 0, 0.5, 1)) end))
hs.hotkey.bind({ "ctrl", "alt" }, "right", place(function(w) w:moveToUnit(hs.geometry.rect(0.5, 0, 0.5, 1)) end))
hs.hotkey.bind({ "ctrl", "alt" }, "f",     place(function(w) w:setFrame(w:screen():frame()) end))
