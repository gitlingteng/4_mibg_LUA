-- ===========================================================================
-- MIBG Interface for stage A
--
-- Developed by Ling Teng, Adam Starkey, and Roger Engelmann.
-- 
-- Copyright (c) The University of Chicago - 2012 - 2013
-- All rights reserved.
-- ===========================================================================

-- ===========================================================================
-- Appplication logic

function disableTools()
  mibg.getToolPanel():setEnabled(false)
end


function enableTools()
  mibg.getToolPanel():setEnabled(true)
end

function lesionPlaced(lesionIndex)
  local r = getRegion(lesionIndex)
  local lesionId = lesion.getIdForLesion(r)
  if type(r) == "lineregion" then
    local options = lesion.showLesionStyleDialog(lesionId)
    if options == nil then                -- cancelled so delete lesion
      lesion.deleteLesionWithId(lesionId)
    else
      lesion.setLesionIsScore3Type(lesionId, options.score3Type)
      lesion.setStyle(lesionId, options.style)
    end
  end
 -- updateLesionZones()
end


function lesionChanged(lesionIndex)
 -- updateLesionZones()
end

function updateLesionZones()
  local visited = {}
  local zones = schematic.getSchematicZones()
  for zoneId, poly in pairs(zones) do
    -- Be careful here.  A point that lies on the edge of a zone will reside 
    -- in more than one zone, which can create recursive nastiness.
    local lesionIndexes = lesion.getIndexesOfLesionsInsidePolygon(poly)
    lesionIndexes = mibg.filter(lesionIndexes, function(v) 
                                                 return not visited[v] 
                                               end)
    lesion.assignZoneToLesions(zoneId, lesionIndexes)
    for _, v in ipairs(lesionIndexes) do 
      visited[v] = true
    end
  end  
end



function worklistCaseOpened()
  enableTools()
  lesion.caseChanged()
   resetZoom()

  mibg.setToolMode("windowing")  
end




-- ===========================================================================
-- UI
function leftPanelResized(p)
  local w = p:width()
  local h = p:height()
  worklist.setBounds(0, 0, w, h * 0.7)
  mibg.getToolPanel():setBounds(0, h * 0.85, w, h * 0.15) 
end


function rightPanelResized(p)
  local w = p:width()
  local h = p:height()
  
  -- relocate schematic
  local aspect = 220 / 350
  local scw = w
  local sch = math.min(w / aspect, h * 0.55)
  scw = math.min(scw, sch * aspect)
  sch = math.min(sch, scw / aspect)
  --schematic.setBounds(0, 0, scw, sch)
  
  -- relocate summary
 -- summary.setBounds(0, sch + 6, scw, h - (sch + 6))
end


function isEclipse(index)
   local r=getRegion(index)
   if type(r) == "freehand" or type(r) == "multipoint" then
      return(true)
   else
      return(false)
   end
end 



-- ===========================================================================
-- Start up code

--assetsDir = file.getScriptDataDirectory()
showMessage(file.getScriptDataDirectory():fullPathName())
assetsDir = file.new(file.getScriptDataDirectory():fullPathName())

maximizeImage(true)
switchToImageTab()
switchToScriptPanel()
newProject()


casePath = assetsDir:fullPathName()
--showMessage(casePath)
dofile(assetsDir:child("mibg.lua"):fullPathName())
mibg.initialize()

dofile(assetsDir:child("mouse.lua"):fullPathName())
mouse.initialize()

--dofile(assetsDir:child("mibgwindowing.lua"):fullPathName())
--mibgwindowing.initialize()

dofile(assetsDir:child("zoom.lua"):fullPathName())
zoom.initialize()

dofile(assetsDir:child("lesion.lua"):fullPathName())
lesion.initialize(true)


dofile(assetsDir:child("worklist.lua"):fullPathName())
worklist.initialize(casePath, "sta")
--worklist.selectcase(patientList[patientIndex])
worklistCaseOpened()
-- Add UI components
mibg.getLeftPanel():addChild(mibg.getToolPanel())
worklist.addToComponent(mibg.getLeftPanel())
--schematic.addToComponent(mibg.getRightPanel())
--summary.addToComponent(mibg.getRightPanel())

mibg.getLeftPanel():setOnResized("leftPanelResized")
mibg.getRightPanel():setOnResized("rightPanelResized")
leftPanelResized(mibg.getLeftPanel())
rightPanelResized(mibg.getRightPanel())



-- Lesion events
--lesion.addPlacedListener(lesionPlaced)
lesion.addChangedListener(lesionChanged)
-- Schematics events
--schematic.setOnZoneClicked(schematicZoneClicked)

-- Worklist events
worklist.setCaseOpenedHandler(worklistCaseOpened)

-- Summary events
--summary.setOnRowSelectedListener(summaryRowSelected)

--disableTools()

wantEvents(true)
