-- Zone Manager for Hammerspoon
-- Translated from FancyZones/BentoBox layouts
-- Layouts are percentage-based, so they work on any monitor at any resolution

require("hs.ipc")
hs.window.animationDuration = 0

--------------------------------------------------------------------------------
-- Layout definitions (loaded from layouts.lua)
--------------------------------------------------------------------------------

local layouts = require("layouts")

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local currentLayoutIndex = 1
local overlay = nil

--------------------------------------------------------------------------------
-- Show a brief overlay indicating the active layout
--------------------------------------------------------------------------------

local function showLayoutNotification(name)
  if overlay then overlay:delete() end
  local screen = hs.screen.mainScreen()
  local frame = screen:frame()
  overlay = hs.drawing.text(
    hs.geometry.rect(frame.x + frame.w / 2 - 150, frame.y + 40, 300, 40),
    hs.styledtext.new("Zone: " .. name, {
      font = { name = ".AppleSystemUIFont", size = 20 },
      color = { white = 1, alpha = 1 },
      paragraphStyle = { alignment = "center" },
    })
  )
  overlay:setBehavior(hs.drawing.windowBehaviors.canJoinAllSpaces)
  overlay:setLevel(hs.drawing.windowLevels.overlay)
  local bg = hs.drawing.rectangle(
    hs.geometry.rect(frame.x + frame.w / 2 - 160, frame.y + 35, 320, 50)
  )
  bg:setFillColor({ black = 0, alpha = 0.7 })
  bg:setStroke(false)
  bg:setRoundedRectRadii(10, 10)
  bg:setBehavior(hs.drawing.windowBehaviors.canJoinAllSpaces)
  bg:setLevel(hs.drawing.windowLevels.overlay)
  bg:show()
  overlay:show()
  hs.timer.doAfter(1.0, function()
    if overlay then overlay:delete() overlay = nil end
    bg:delete()
  end)
end

--------------------------------------------------------------------------------
-- Snap the focused window to a zone
--------------------------------------------------------------------------------

local function snapToZone(zoneIndex)
  local layout = layouts[currentLayoutIndex]
  local zone = layout.zones[zoneIndex]
  if not zone then
    print("[zones] no zone " .. zoneIndex .. " in layout " .. layout.name)
    return
  end

  local win = hs.window.focusedWindow()
  if not win then
    -- fallback: try via the frontmost application
    local app = hs.application.frontmostApplication()
    if app then
      print("[zones] focusedWindow() returned nil, trying frontmost app: " .. app:name())
      win = app:focusedWindow() or app:mainWindow()
    end
    if not win then
      print("[zones] no focused window (even via frontmost app)")
      return
    end
  end

  local screen = win:screen()
  local frame = screen:frame()

  win:setFrame(hs.geometry.rect(
    frame.x + (zone.x * frame.w),
    frame.y + (zone.y * frame.h),
    zone.w * frame.w,
    zone.h * frame.h
  ))
end

--------------------------------------------------------------------------------
-- Switch layout
--------------------------------------------------------------------------------

local function switchLayout(index)
  if index < 1 or index > #layouts then return end
  currentLayoutIndex = index
  showLayoutNotification(layouts[index].name)
end

--------------------------------------------------------------------------------
-- Hotkeys
--------------------------------------------------------------------------------

-- Cmd+Opt+Ctrl+1/2/3 to switch layouts
local layoutMods = { "cmd", "alt", "ctrl" }
for i = 1, #layouts do
  hs.hotkey.bind(layoutMods, tostring(i), function() switchLayout(i) end)
end

-- Ctrl+Opt+1-9 to snap focused window to zone N
local snapMods = { "ctrl", "alt" }
for i = 1, 9 do
  hs.hotkey.bind(snapMods, tostring(i), function() snapToZone(i) end)
end

-- Ctrl+Opt+F to maximize focused window
hs.hotkey.bind({ "ctrl", "alt" }, "f", function()
  local win = hs.window.focusedWindow()
  if not win then
    local app = hs.application.frontmostApplication()
    if app then win = app:focusedWindow() or app:mainWindow() end
    if not win then return end
  end
  win:setFrame(win:screen():frame())
end)

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------

showLayoutNotification(layouts[currentLayoutIndex].name)
