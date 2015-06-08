-- ===========================================================================
-- A library that provides an extended set of mouse behaviours
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
  
  dofile(path_to_mouse_lib)
  mouse.initialize()
  
]]-- 


mouse = {}
  
-- Initializes the mouse library.  
-- This library takes ownership of all normal mouse events for the display 
-- panel, and provides new more expressive ones in their place.  
-- Do not attempt to implement display panel mouse handlers directly in your
-- script if you are using this library!
function mouse.initialize()
  if mibg == nil then
    error("Missing MIBG library")
  end  
end


-- Call this function to clear the mouse state, and release the mouse.
-- Typically you should call this function whenever the tool state changes.
function mouse.clear()
  local p = getDisplayPanel()
  p:setOnMouseDown()
  p:setOnMouseUp()
  p:setOnMouseMove()
  mouse._mouseDownHandler = nil
  mouse._mouseUpHandler = nil
  mouse._mouseMoveHandler = nil
  mouse._mouseDragHandler = nil
  mouse._clearMouseDownPosition()
end


-- Returns true if the mouse button is currently down.
function mouse.isDown()
  return mouse._mouseDownX ~= nil
end


-- Returns true if the user seems to be dragging the mouse.
function mouse.isBeingDragged()
  return mouse.dragDistance() > 2
end


-- Returns the horizontal amount the mouse has moved since the start of a drag
function mouse.horizontalDragDistance()
  if mouse.isDown() then
    return mouse._mouseLastX - mouse._mouseDownX
  end
end


-- Returns the vertical amount the mouse has moved since the start of a drag
function mouse.verticalDragDistance()
  if mouse.isDown() then
    return mouse._mouseLastY - mouse._mouseDownY
  end
end


-- Returns the total current distance the mouse has travelled since the start 
-- of a drag.
function mouse.dragDistance()
  if mouse.isDown() then
    local dx, dy = mouse.getMouseDownPosition()
    local cx, cy = mouse.getMousePosition()
    dx = math.abs(dx - cx)
    dy = math.abs(dy - cy)
    return math.sqrt((dx * dx) + (dy * dy)) 
  end
  return 0
end


-- Returns the x and y locations of the mouse when the user clicked a mouse
-- button inside the display panel area.
function mouse.getMouseDownPosition()
  return mouse._mouseDownX, mouse._mouseDownY
end


-- Returns the last known position of the mouse over the display panel.
function mouse.getMousePosition()
  return mouse._mouseLastX, mouse._mouseLastY
end


-- ===========================================================================
-- Events

-- Sets a handler that will be called when the user presses a mouse button 
-- over the display panel.
function mouse.setMouseDownHandler(handlerFunc)
  local p = getDisplayPanel()
  p:setOnMouseDown("_mouse_mouseDown")
  p:setOnMouseUp("_mouse_mouseUp")
  p:setOnMouseMove("_mouse_mouseMove")
  mouse._mouseDownHandler = handlerFunc
end


-- Returns a previously set handler function
function mouse.getMouseDownHandler()
  return mouse._mouseDownHandler
end


-- Sets a handler that will be called when the user releases a mouse button 
-- over the display panel.
function mouse.setMouseUpHandler(handlerFunc)
  local p = getDisplayPanel()
  p:setOnMouseDown("_mouse_mouseDown")
  p:setOnMouseUp("_mouse_mouseUp")
  p:setOnMouseMove("_mouse_mouseMove")  
  mouse._mouseUpHandler = handlerFunc
end


-- Returns a previously set handler function
function mouse.getMouseUpHandler()
  return mouse._mouseUpHandler
end


-- Sets a handler that will be called when the mouse is moved inside the
-- display panel.
function mouse.setMouseMoveHandler(handlerFunc)
  local p = getDisplayPanel()
  p:setOnMouseDown("_mouse_mouseDown")
  p:setOnMouseUp("_mouse_mouseUp")
  p:setOnMouseMove("_mouse_mouseMove")
  mouse._mouseMoveHandler = handlerFunc
end


-- Returns a previously set handler function
function mouse.getMouseMoveHandler()
  return mouse._mouseMoveHandler
end


-- Sets a handler that will be called when the user drags the mouse inside the
-- display panel.
function mouse.setMouseDragHandler(handlerFunc)
  local p = getDisplayPanel()
  p:setOnMouseDown("_mouse_mouseDown")
  p:setOnMouseUp("_mouse_mouseUp")
  p:setOnMouseMove("_mouse_mouseMove")  
  mouse._mouseDragHandler = handlerFunc
end


-- Returns a previously set handler function
function mouse.getMouseDragHandler()
  return mouse._mouseDragHandler
end


-- ===========================================================================
-- Private functions

function _mouse_mouseDown(p, x, y, b, m)
  mouse._setMouseDownPosition(x, y)
  if type(mouse._mouseDownHandler) == "function" then
    mouse._mouseDownHandler(p, x, y, b, m)
  end  
end


function _mouse_mouseUp(p, x, y)
  mouse._clearMouseDownPosition()
  if type(mouse._mouseUpHandler) == "function" then
    mouse._mouseUpHandler(p, x, y)
  end  
end


function _mouse_mouseMove(p, x, y)
  mouse._setMousePosition(x, y)
  if type(mouse._mouseMoveHandler) == "function" then
    mouse._mouseMoveHandler(p, x, y)
  end  

  if mouse.isBeingDragged() then
    if type(mouse._mouseDragHandler) == "function" then
      mouse._mouseDragHandler(p, x, y)
    end  
  end
end


-- ===========================================================================

function mouse._setMouseDownPosition(x, y)
  mouse._mouseDownX = x
  mouse._mouseDownY = y
  mouse._setMousePosition(x, y)
end


function mouse._clearMouseDownPosition()
  mouse._mouseDownX = nil
  mouse._mouseDownY = nil
end


function mouse._setMousePosition(x, y)
  mouse._mouseLastX = x
  mouse._mouseLastY = y
end

