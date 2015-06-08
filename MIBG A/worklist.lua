-- ===========================================================================
-- A library that provides a simple worklist
--
-- Developed by Adam Starkey, Roger Engelmann, and Ling Teng.
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
  
  dofile(path_to_worklist_lib)
  worklist.initialize("d://worklist", "stb")
  
]]-- 


worklist = {}

-- 'casePath' is the path that contains the image files and completed projects 
-- 'studyId' a string that will be used to name and identify projects for the
-- study, I.E 'sta', or 'stb' for stages 'a' and 'b'.
function worklist.initialize(casePath, studyId)
  if mibg == nil then
    error("Missing MIBG library")
  end
  
  worklist._casePath = casePath
  worklist._studyId = studyId
  
  -- create UI
  worklist._panel = panel.new()
  worklist._panel:setBackground(0xFFA0A0A0)  
  local lv = listview.new("list")  
  lv:setOnSelectionsChanged("_worklist_listSelectionsChanged")
  worklist._panel:addChild(lv)
  local b = button.new("Mark case complete")
  b:setName("complete")
  b:setOnClicked("_worklist_completeClicked")
  worklist._panel:addChild(b)  
  worklist.update()
end


function worklist.selectcase(casename)
     local lv = worklist._panel:getChild("list")
     local caselist =lv:getItems()
        local index =0
     for i,v in ipairs(caselist) do
             if v==casename then
           index =i
        end
     end
      lv:selectIndexes({index})
     _worklist_listSelectionsChanged(lv)

end
-- Updates the case list.  Typically you wont need to call this function, as
-- this library will keep an eye on things for you.
function worklist.update()
  if mibg == nil then
    error("Missing MIBG library")
  end
  
  local ok, msg = pcall(worklist._updateListView)
  if not ok then
    mibg.logError(msg)
  end  
end


-- Adds the worklist component to the specified parent component.
function worklist.addToComponent (parent)
  if worklist._panel:parent() ~= nil then
    worklist._panel:parent():removeChild(worklist._panel)
  end
  parent:addChild(worklist._panel)
end


-- Sets the bounds for the worklist with respect to its parent.
function worklist.setBounds (l, t, w, h)
  worklist._panel:setBounds(l, t, w, h)
  worklist._resized()
end


-- Sets an event handler that will be called when the user opens a case from
-- the worklist.
function worklist.setCaseOpenedHandler(handlerFunc)
  worklist._caseOpenedHandler = handlerFunc
end


-- ===========================================================================
-- Private functions

function _worklist_listSelectionsChanged(lv)
  local lv = worklist._panel:getChild("list")
  local indexes = lv:getSelectedIndexes()
  if #indexes == 1 then
    local items = lv:getItems()
    
    -- Save exisiting project if we have one
    if getProjectFileName() ~= '' then
      saveProject()
    end
  
    -- load existing project, or create a new one if no project exists
    local caseFile = file.new(worklist._casePath):child(items[indexes[1]])
    if caseFile:withExtension(worklist._studyId .. "_complete"):exists() then
      openProjectAs(caseFile:withExtension(worklist._studyId .. "_complete"))
    elseif caseFile:withExtension(worklist._studyId):exists() then
      openProjectAs(caseFile:withExtension(worklist._studyId))
    else
      newProject()
      setPrimaryQueue({caseFile:withExtension("dcm"):fullPathName()})
      saveProjectAs(caseFile:withExtension(worklist._studyId))
    end
    
    -- Give main application a chance to do extra work
    local ok, msg = pcall(worklist._caseOpenedHandler)  
    if not ok then
      mibg.logError(msg)
    end
  end
end
  

function _worklist_completeClicked(b)
  if getProjectFileName() ~= '' then
    local f = file.new(getProjectFileName())
    saveProjectAs(f:withExtension(worklist._studyId .. "_complete"))
    worklist._updateListView() 
  end
end


function worklist._resized ()
  local p = worklist._panel
  local w = p:width();
  local h = p:height();
  local lv = p:getChild("list")
  lv:setBounds(1, 1, w - 2, h - 36)
  local b = p:getChild("complete")
  b:setBounds(6, h - 30, w - 12, 24)  
end


function worklist._updateListView()
  local d = file.new(worklist._casePath)
  local items = {}
  local cases = d:getDirectoryList("*.dcm", false)
  for i, case in ipairs(cases) do
    local item = case:withExtension(""):fileName()
    if file.new(case:withExtension(worklist._studyId .. '_complete')):exists() then
      item = {item, colour.new(0xFF808080)}
    end
    items[i] = item
  end
  table.sort(items, function(a, b)
                      if type(a) == "string" then
                        if type(b) == "string" then
                          return a < b
                        end
                        return true
                      elseif type(b) == "string" then
                        return false
                      end
                      return (#a < #b) or (a[1] < b[1])
                    end)
  local lv = worklist._panel:getChild("list")
  lv:setItems(items)
  _worklist_listSelectionsChanged(lv)
end



