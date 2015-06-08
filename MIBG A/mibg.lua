-- ===========================================================================
-- The main library for MIBG interfaces.
--
-- Developed by Ling Teng, Adam Starkey, and Roger Engelmann.
-- 
-- Copyright (c) The University of Chicago - 2012 - 2013
-- All rights reserved.
--
-- ---------------------------------------------------------------------------
--
-- Version 1.3
--
--   * Added an implementation of filter()
--
-- Version 1.2 
--
--   * A quick fix to stop nil functions being registered as handlers.
--
-- Version 1.1
--
-- ===========================================================================

-- To use, call:

--[[

  dofile(path_to_mibg_lib)
  mibg.initialize(true)
  
]]--

 
mibg = {}

mibg._modes = {}
mibg._modeButtonStyles = {}


-- Call this function to initialize the MIBG library. 
function mibg.initialize()
  setRegionAutoRepeatEnabled(false)
  
  mibg._regionSelectionsChangedListeners = {}
  mibg._regionChangedListeners = {}
  mibg._regionListChangedListeners = {}
  mibg._toolModeChangedListeners = {}
      
  local p = getDisplayPanel()

  -- Add title bars above image pair
  mibg._overlay = panel.new()
  mibg._overlay:setBackground(0x80E0E0FF)
  
  local l = label.new(".        Anterior")
  l:setColour(0xFF000000)
  mibg._overlay:addChild(l)
  l = label.new(".        Posterior")
  l:setColour(0xFF000000)
  mibg._overlay:addChild(l)
  p:addChild(mibg._overlay)
  
  -- Add left panel
  mibg._leftPanel = panel.new()
  mibg._leftPanel:addChild(panel.new())
  mibg._leftPanel:setOnResized("_mibg_sidePanelResized")
  p:addChild(mibg._leftPanel)

  -- Add right panel
  mibg._rightPanel = panel.new()
  mibg._rightPanel:addChild(panel.new())
  mibg._rightPanel:setOnResized("_mibg_sidePanelResized")
  p:addChild(mibg._rightPanel)

  -- Register region event handlers    
  setOnRegionListChanged("_mibg_regionListChanged")
  setOnRegionSelectionsChanged("_mibg_regionSelectionsChanged")
  setOnRegionChanged("_mibg_regionChanged")
  
  -- Register other event handlers
  p:setOnDisplayChanged("_mibg_displayChanged")
  p:setOnResized("_mibg_resized")
  
  if (p:width() > 0 and p:height() > 0) then
    _mibg_resized(p)
  end
end


-- Sets the tool mode.
function mibg.setToolMode(mode)
  if not table.contains(mibg._modes, mode) then
    mibg.logError("Attempt to set invalid tool mode: " .. tostring(mode))
    return 
  end
  
  if mibg._toolMode ~= mode then
    mibg._toolMode = mode
    if mibg._toolComponent ~= nil then
      mibg._toolComponent:getChild(mode):setDown(true)
    end
    mibg.callListeners(mibg._toolModeChangedListeners, mode)
  end
end


-- Returns the current mode.
function mibg.getToolMode()
  return mibg._toolMode
end


-- Adds a new mode to the tool mode set, and adds a corresponding button to 
-- the button panel.
function mibg.addToolMode(modeName, buttonText, preferredRow)
  table.insert(mibg._modes, modeName)
  mibg._modeButtonStyles[modeName] = {preferredRow, buttonText}
  mibg._updateToolComponent()
end


-- Returns a component containing a palette of basic editing tools. 
function mibg.getToolPanel()
  if mibg._toolComponent == nil then
    mibg._createToolComponent()
  end
  return mibg._toolComponent
end


-- Returns a panel instance that can be used to place tools and widgets to the
-- left of the image display.
function mibg.getLeftPanel()
  return mibg._leftPanel:getChild(1)
end


-- Returns a panel instance that can be used to place tools and widgets to the
-- right of the image display.
function mibg.getRightPanel()
  return mibg._rightPanel:getChild(1)
end


-- ===========================================================================
-- General helper functions

-- Call this function to write an error message to the log file.
function mibg.logError(error)
  local f = file.getScriptDataDirectory():child("log.txt")
  f = io.open(f:fullPathName(), "a")
  f:write(error .. "\n")
  f:close()
end


-- Calls a list of functions in a table passing the optional paramter p to 
-- each of them.  
-- This function is mostly of use when implementing listener/broadcaster 
-- patterns.
function mibg.callListeners(list, p)
  local i = 1
  while true do
    local n = #list
    if i <= n then
      if p == nil then
        list[i]()
      else
        list[i](p)      
      end
      i = i + 1
    else 
      break
    end
  end  
end


-- Adds a value to an indexed table if it is not already there.  The search is
-- a brute force N operation.
function mibg.addToListIfNotPresent(list, f)
  if f == nil then
    mibg.logError("Attempt to register event handler as nil function")
    return
  end

  local found = false
  for _, v in ipairs(list) do
    if v == f then
      found = true
      break
    end
  end
  if not found then
    table.insert(list, f)
  end
end


-- Removes a value from an indexed table.  No action is taken if the item is 
-- not found.  The search is a brute force N operation.
function mibg.removeFromList(list, f)
  for _, v in ipairs(list) do
    if v == f then
      table.remove(list, i)
      break
    end
  end
end


-- An implementation of filter()
function mibg.filter(list, f)
  local t = {}
  local i = 1
  for _, v in ipairs(list) do
    if f(v) then
      t[i] = v
      i = i + 1
    end
  end
  return t
end


-- ===========================================================================
-- Events

-- Adds a listener function that will be called when the user adds or deletes
-- regions.
function mibg.addRegionListChangedListener(listenerFunc)
  mibg.addToListIfNotPresent(mibg._regionListChangedListeners, listenerFunc)    
end


-- Removes a previously registered listener.
function mibg.removeRegionListChangedListener(listenerFunc)
  mibg.removeFromList(mibg._regionListChangedListeners, listenerFunc)    
end


-- Adds a listener function that will be called when the user selects or 
-- deselects regions
function mibg.addRegionSelectionsChangedListener(listenerFunc)
  mibg.addToListIfNotPresent(mibg._regionSelectionsChangedListeners, listenerFunc)    
end


-- Removes a previously registered listener.
function mibg.removeRegionSelectionsChangedListener(listenerFunc)
  mibg.removeFromList(mibg._regionSelectionsChangedListeners, listenerFunc)    
end


-- Adds a listener function that will be called when a non-lesion region 
-- changes.  
function mibg.addRegionChangedListener(listenerFunc)
  mibg.addToListIfNotPresent(mibg._regionChangedListeners, listenerFunc)    
end


-- Removes a previously registered listener.
function mibg.removeRegionChangedListener(listenerFunc)
  mibg.removeFromList(mibg._regionChangedListeners, listenerFunc)    
end


-- Adds a listener function that will be called when the tool mode changes.  
function mibg.addToolModeChangedListener(listenerFunc)
  mibg.addToListIfNotPresent(mibg._toolModeChangedListeners, listenerFunc)    
end


-- Removes a previously registered listener.
function mibg.removeToolModeChangedListener(listenerFunc)
  mibg.removeFromList(mibg._toolModeChangedListeners, listenerFunc)    
end


-- ===========================================================================
-- Private event handlers

function _mibg_regionSelectionsChanged()
  mibg.callListeners(mibg._regionSelectionsChangedListeners, nil)
end


function _mibg_regionListChanged()
  mibg.callListeners(mibg._regionListChangedListeners, nil)
end


function _mibg_regionChanged(index)
  mibg.callListeners(mibg._regionChangedListeners, index)
end


function _mibg_displayChanged(p)
  -- Relocate title bar
  local tl = p:convertRegionCoordinateToDisplayPixel(point.new(0, 1))
  local br = p:convertRegionCoordinateToDisplayPixel(point.new(1, 0.999))
  mibg._overlay:setBounds(tl:x(), tl:y(), br:x() - tl:x(), 25)
  pwidth = mibg._overlay:width() / 2
  mibg._overlay:getChild(1):setBounds(1, 0, pwidth, 25)
  mibg._overlay:getChild(2):setBounds(pwidth + 1, 0, pwidth, 25)
end


function _mibg_resized(p)
  -- Relocate left and right panels, and redraw background
  local w = p:width()
  local h = p:height()

  local im = image.new(w, h)
  im:drawRectangle(0, 0, w, h, colour.new(0xFF404040), colour.new(0xFFC0C0C0), 1)
  mibg._sidePanelBackground = im

  local pw = math.min(300, (w * 0.3) - 12)
  mibg._leftPanel:setBounds(6, 6, pw, h - 12)  
  mibg._rightPanel:setBounds(w - pw - 6, 6, pw, h - 12)
  _mibg_sidePanelResized(mibg._leftPanel)
  _mibg_sidePanelResized(mibg._rightPanel)
end


function _mibg_sidePanelResized(p)
  -- Relocate child panel, and set background
  local w = p:width()
  local h = p:height()
  p:setBackground(mibg._sidePanelBackground)
  p:getChild(1):setBounds(6, 6, w - 12, h - 12)
end


function _mibg_toolPanelResized(p)
  local rows = mibg._getToolButtonsAsRowTable()

  local w = p:width()
  local h = p:height()
  local rowHeight = math.min(24, h / #rows)
  local colWidth = w / 3
  for row, t in ipairs(rows) do
    local colWidth = w / #t
    for col, k in ipairs(t) do
      local b = p:getChild(k)
      b:setBounds((col - 1) * colWidth, (row - 1) * rowHeight, colWidth, rowHeight)
    end  
  end
end 


function _mibg_radioClicked(b)
  mibg.setToolMode(b:name())
end


-- ===========================================================================
-- Tool mode helpers

function mibg._createToolComponent()
  local p = panel.new()
  p:setOnResized("_mibg_toolPanelResized")
  mibg._toolComponent = p
    
  mibg._updateToolComponent()

  if table.contains(mibg._modes, mibg._toolMode) then
    local b = p:getChild(mibg._toolMode)
    if b then
      b:setDown(true)
    end
  end
end


function mibg._getToolButtonsAsRowTable()
  local t = {}
  local max = 0
  for _, mode in ipairs(mibg._modes) do
    local style = mibg._modeButtonStyles[mode]    

    if style[1] > max then
      max = style[1]
    end

    if t[style[1]] == nil then
      t[style[1]] = {mode}
    else
      table.insert(t[style[1]], mode) 
    end  
  end
  
  local j = 1
  local t2 = {}
  for i = 1, max do
    if t[i] ~= nil then
      t2[j] = t[i]
      j = j + 1
    end
  end
  
  return t2
end


function mibg._updateToolComponent()
  local p = mibg._toolComponent
  
  if p == nil then 
    return
  end
  
  -- remove unecessary buttons and index
  local buttons = {}
  local j = p:numberOfChildren()
  for i = j, 1, -1 do
    local b = p:getChild(i)
    if type(b) == 'button' and b:radioId() == 1 then
      if table.contains(mibg._modes, b:name()) then
        buttons[b:name()] = b
      else
        p:removeChild(b)
      end
    end
  end
 
  -- add missing buttons, and restyle all edges
  local rows = mibg._getToolButtonsAsRowTable()
  for row, t in ipairs(rows) do
    for col, k in ipairs(t) do
      local b = buttons[k]
      if b == nil then
        b = button.new(mibg._modeButtonStyles[k][2])
        b:setName(k)
        b:setRadioId(1)
        b:setOnClicked("_mibg_radioClicked")
        b:setBackgroundColour(SAFE_BUTTON)
        p:addChild(b)
      end
      b:setConnectedEdges(col > 1, row > 1, col < #t, row < #rows)
    end
  end
 
   -- force a resize to update layout 
  _mibg_toolPanelResized(p)
end


-- ===========================================================================
-- Other library extensions

function table.contains(t, v)
  local result = false
  for _, tv in pairs(t) do
    if tv == v then
      result = true
      break
    end
  end
  return result
end

