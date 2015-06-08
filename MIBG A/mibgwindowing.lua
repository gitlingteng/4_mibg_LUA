-- ===========================================================================
-- A library that provides a basic MIBG aware windowing model
--
-- Developed by Adam Starkey, Roger Engelmann, and Ling Teng
-- 
-- Copyright (c) The University of Chicago - 2012 - 2013
-- All rights reserved.
--
-- ---------------------------------------------------------------------------
--
-- Version 1.1
--
-- ===========================================================================

-- To use, call

--[[
  
  dofile(path_to_mibgwindowing_lib)
  mibgwindowing.initialize()
  
]]--


mibgwindowing = {}


-- Initializes the mibgwindowing library.  
function mibgwindowing.initialize()
  if mibg == nil then
    error("Missing MIBG library")
  end
  
  if mouse == nil then
    error("Missing mouse library")
  end

  mibg.addToolMode('windowing', "Windowing", 1)
  mibg.addToolModeChangedListener(mibgwindowing._modeChanged)
end


-- Call this function when the case changes to ensure that a suitable 
-- windowing profile is used for the case.
function mibgwindowing.update()
  local mi = medicalimage.new(getCurrentPrimaryFileName())
  if mi ~= nil then
    local h = mi:height()
    local w = mi:width()
    local sum = 0
    local sumCount = 0
    local max = 0
    local min = 32768
    for y = 1, h do
      for x = (w / 4) - 10, (w / 4) + 10 do
        local v = mi:pixelAt(x, y)
        if v > 0 then
          sum = sum + v
          sumCount = sumCount + 1
          max = math.max(max, v)
        end
        min = math.min(min, v)
      end
    end
  
    local avg = sum / sumCount

    mibgwindowing._defaultWidth = max
    mibgwindowing._defaultCenter = avg
    mibgwindowing._maxValue = max
    mibgwindowing._minValue = min
  
    lockWindowing(false)
    setWindowing(windowing.new(mibgwindowing.getDefaultWidth(), 
                               mibgwindowing.getDefaultCenter()))
    lockWindowing(true) 
  else
    mibgwindowing._defaultWidth = nil
    mibgwindowing._defaultCenter = nil
    mibgwindowing._maxValue = nil
    mibgwindowing._minValue = nil
  end
end
  

-- Returns the preferred width for the windowing
function mibgwindowing.getDefaultWidth()
  return mibgwindowing._defaultWidth
end


-- Returns the preferred center for the windowing
function mibgwindowing.getDefaultCenter()
  return mibgwindowing._defaultCenter
end


-- Resets the current windowing to the preferred defaults.
function mibgwindowing.resetWindowing()
  if mibgwindowing.getDefaultWidth() ~= nil then
    lockWindowing(false) 
    setWindowing(windowing.new(mibgwindowing.getDefaultWidth(), 
                               mibgwindowing.getDefaultCenter()))
    lockWindowing(true)
  else 
    setWindowing(windowing.new(50, 5))
  end  
end


-- ===========================================================================
-- Private functions

function mibgwindowing._modeChanged(mode)
  if mode == "windowing" then
    mouse.clear()
    mouse.setMouseDownHandler(mibgwindowing._mouseDown)
    mouse.setMouseDragHandler(mibgwindowing._mouseDrag)
  end
end


function mibgwindowing._mouseDown(p, x, y, b, m)
  local w = getBaseWindowing()
  mibgwindowing._startWinWidth = w:width()
  mibgwindowing._startWinCenter = w:center()
end


function mibgwindowing._mouseDrag(p, x, y)
  local w = getBaseWindowing()
  local dx = mouse.horizontalDragDistance()
  local dy = mouse.verticalDragDistance()
  local width = math.max(10, math.min(mibgwindowing._defaultWidth, mibgwindowing._startWinWidth + (dy / 8)))
  local center = math.max(10, math.min(mibgwindowing._defaultWidth - 10, mibgwindowing._startWinCenter + (dx / 8)))
  lockWindowing(false)
  setWindowing(windowing.new(width, center))
  lockWindowing(true)
end
