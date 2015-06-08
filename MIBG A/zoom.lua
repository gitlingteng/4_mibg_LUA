-- ===========================================================================
-- A library that provides simple zoom behaviours
--
-- Developed by Adam Starkey, Ling Teng, and Roger Engelmann
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
  
  dofile(path_to_zoom_lib)
  mouse.initialize()
  
]]-- 


zoom = {}
  

-- Initializes the zoom library.  
function zoom.initialize()
  if mibg == nil then
    error("Missing MIBG library")
  end

  if mouse == nil then
    error("Missing mouse library")
  end
  
  mibg.addToolMode('zoomIn', "Zoom In", 1)
  mibg.addToolMode('zoomOut', "Zoom Out", 1)
    
  mibg.addToolModeChangedListener(zoom._toolModeChanged)
end


-- ===========================================================================
-- Private functions

function zoom._toolModeChanged(mode)
  if mode == "zoomIn" or mode == "zoomOut" then
    mouse.clear()
    mouse.setMouseDownHandler(zoom._mouseDown)
  end
end


function zoom._mouseDown(p, x, y, b, m)
  if (b ~= PopupButton) then
    local mode = mibg.getToolMode()
    if mode == "zoomIn" then
      zoom._zoomIn(p, x, y)
    elseif mode == "zoomOut" then
      zoom._zoomOut(p, x, y)
    end
  end
end


function zoom._zoomIn(p, x, y)
  local pos = point.new(x, y)
  pos = p:convertDisplayPixelToRegionCoordinate(pos)
  setZoomCenterPoint(pos)
  setZoomScaleFactor(getZoomScaleFactor() * 2)
end


function zoom._zoomOut(p, x, y)
  local pos = point.new(x, y)
  pos = p:convertDisplayPixelToRegionCoordinate(pos)
  setZoomCenterPoint(pos)
  setZoomScaleFactor(getZoomScaleFactor() / 2)    
end
