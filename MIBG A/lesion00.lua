-- ===========================================================================
-- A library that provides lesion support for the various MIBG interfaces.
--
-- Developed by Ling Teng, Adam Starkey, and Roger Engelmann.
-- 
-- Copyright (c) The University of Chicago - 2012 - 2013
-- All rights reserved.
--
-- ---------------------------------------------------------------------------
--
-- Version 1.8
-- 
--    * Fixed _removeZoneFromLesion() which was not clearing both zone 
--      attributes.
--
-- Version 1.4
--
--    * Added a few helper functions, mostly to allow for location of lesions 
--      by zone.
--
-- Version 1.3
--
--   * Added an API for finding lesions that lie inside an arbitrary polygon.
--
-- Version 1.2
--
--   * Added a score 3 dialog that also supports styles
--   * Added support for lesion styles (I.E. ellipses).
--   * Added new lesion placed event
--   * Exposed score3 state to public API
--   * Fixed context menu support
--   * Fixed score counting logic.  
--
-- ===========================================================================

-- To use, call:

--[[

  dofile(path_to_lesion_lib)
  mibg.initialize()
  
]]--

 
lesion = {}

lesion.zones = {'1', '2', '3L', '3R', '4', '5L', '5R', '6L', '6R', '7L', '7R', '8L', '8R', '9L', '9R', '10'}


-- Call this function to initialize the MIBG library. 

function lesion.initialize(createToolButtons, lesionReadFilespecObj, inMIBGBModified)
  if mibg == nil then
    error("Missing MIBG library")
  end

  if mouse == nil then
    error("Missing mouse library")
  end
  
  lesion._zoneScores = nil
  lesion._listChangedListeners = {}
  lesion._changedListeners = {}
  lesion._placedListeners = {}
  lesion._selectionChangedListeners = {}
  lesion._extantLesionIds = {}
  lesion._selectedIds = {}
  lesion._lesionReadFilespecObj = lesionReadFilespecObj
  lesion._inMIBGBModified = inMIBGBModified
    
  setRegionAutoRepeatEnabled(false)
  mibg.addRegionListChangedListener(lesion._regionListChanged)
  mibg.addRegionSelectionsChangedListener(lesion._regionSelectionsChanged)
  mibg.addRegionChangedListener(lesion._regionChanged)
  mibg.addToolModeChangedListener(lesion._toolModeChanged)
  
  if  createToolButtons == true then 
    mibg.addToolMode('draw', "Identify Lesion", 3)
    mibg.addToolMode('edit', "Edit Lesion", 3)
--  else
--    if createToolButtons == false then
--      mibg.addToolMode('import', "Import Lesion", 2)
--    end
  end

  lesion.caseChanged()
end


-- Call this function to notify the lesion library that the case has changed!
function lesion.caseChanged()
  -- Creating project attributes lets us use Abras's region hide/show 
  -- functionality rather than filtering regions manually.
  local attribs = {generalzone = {}, fakezone = {}}
  for i = 1, 10 do
    attribs.generalzone[i] = tostring(i)
  end
  attribs.generalzone[11] = "unassigned"
  
  attribs.zone = {}
  for i, v in ipairs(lesion.zones) do
    attribs.zone[i] = v
  end
  setAttributes(attribs)  

  -- Reset lesion caches, and send change messages.
  lesion._clearZoneScores()
  lesion._regionListChanged()
  lesion._regionSelectionsChanged()  
end


-- Call this function to display a window through which the user can specify
-- whether a lesion is score 3 type, and the geometry to use when displaying 
-- the lesion.
-- You should not call this function for point mark lesions!
-- The return value is nil if the user clicked cancel, or a table with the 
-- following keys:
--   'score3Type' - true if the lesion is a score 3, or false otherwise
--   'style'      - A string matching the inputs for lesion.setStyle()
function lesion.showLesionStyleDialog(lesionId)
  return lesion._showLesionStyleDialog(lesionId)
end


-- Call this function to get a lookup table of zone scores.
-- The scores are returned as a keyed table of the form t['1'], t['4R'] etc.
-- The lookup table presents scores both for grouped zones and individual, 
-- I.E. the key '5' will contain the combined score for '5L' and '5R'.
function lesion.getZoneScores()
  if lesion._zoneScores == nil then
    lesion._updateZoneScores()
  end
  return lesion._zoneScores
end


-- Returns the indexes of the region(s) corresponding to the given lesion Id.
function lesion.getLesionIndexes(lesionId)
  return getIndexesOfRegionsWithAttribute("id", tostring(lesionId))
end


-- Returns the indexes of all lesion regions.
function lesion.getIndexesOfAllLesions()
  return getIndexesOfRegionsWithAttribute("id")  
end


-- Returns a list of all lesion Ids.
function lesion.getAllLesionIds()
  local indexes = lesion.getIndexesOfAllLesions()

  local t = {}
  for _, v in ipairs(indexes) do
    t[v] = true  
  end
  
  local ids = {}
  local i = 1
  for k in pairs(t) do
    ids[i] = k 
  end
  
  return ids  
end


-- Returns the indexes of all lesion regions with the specified zone.
function lesion.getIndexesOfLesionsInZone(zoneName)
  local indexes
  if tostring(tonumber(zoneName)) == tostring(zoneName) then
    indexes = getIndexesOfRegionsWithAttribute("generalzone", zoneName)
  else
    indexes = getIndexesOfRegionsWithAttribute("zone", zoneName)  
  end
  return indexes
end


-- Returns true if the selected region set contains only lesions, or false if 
-- either regions other than lesions are selected, or no regions are selected.
function lesion.areOnlyLesionsSelected()
  local indexes = getIndexesOfSelectedRegions()
  local result = #indexes > 0
  for _, v in ipairs(indexes) do
    local r = getRegion(v)
    if r ~= nil then
      if not lesion.isRegionALesion(r) then
        result = false
        break
      end
    end    
  end
  return result
end


-- Returns true if any of the selected region set are lesions, or false if 
-- no lesions are selected.
function lesion.areAnyLesionsSelected()
  local result = false
  local indexes = getIndexesOfSelectedRegions()
  for _, v in ipairs(indexes) do
    local r = getRegion(v)
    if r ~= nil then
      if lesion.isRegionALesion(r) then
        result = true
        break
      end
    end
  end  
  return result
end


-- Returns the IDs of any selected lesions.
function lesion.getIdsOfSelectedLesions()
  local t = {}
  local indexes = getIndexesOfSelectedRegions()
  for _, v in ipairs(indexes) do
    local r = getRegion(v)
    if r ~= nil then
      if lesion.isRegionALesion(r) then
        local id = lesion.getIdForLesion(r)
        t[id] = true
      end
    end
  end
  
  local result = {}
  for k, _ in pairs(t) do
    table.insert(result, k)
  end
  return result
end


-- Returns true if the given Abras region represents a lesion
function lesion.isRegionALesion(r)
  return lesion.getIdForLesion(r) ~= nil
end


-- Returns the id of the given lesion
function lesion.getIdForLesion(r)
 return r:getValueForAttribute("id")
end


-- Returns true if the given lesion was the original of a lesion pair
function lesion.isLesionOriginalMark(r)
  return r:hasAttribute("original")
end


-- Specifies whether the given lesion is a score 3 lesion
function lesion.setLesionIsScore3Type(lesionId, isScore3Type)
  lesion._setLesionScore3Type(lesionId, isScore3Type)
end


-- Returns true if given lesion is a score 3 lesion
function lesion.isLesionAScore3Type(r)
  return r:hasAttribute("score3")
end


-- Sets the style of the lesion, which can be one of: 'line', 'thin-ellipse', 
-- 'thick-ellipse', or 'circle'
-- Do not attempt to set the style of a point lesion, only line lesions 
-- support having their style specified!
function lesion.setStyle(lesionId, style)
  if style == "line" or style == "thin-ellipse" or 
     style == "thick-ellipse" or style == "circle" then
    local indexes = lesion.getLesionIndexes(lesionId)
    if #indexes > 0 then
      local r
      for _, v in ipairs(indexes) do
        r = getRegion(v)
        if type(r) == "lineregion" then
          if style == "line" then
            r:removeAttribute("shortaxis")
          elseif style == "thin-ellipse" then
            r:addAttribute("shortaxis", "short")
          elseif style == "thick-ellipse" then
            r:addAttribute("shortaxis", "medium")
          elseif style == "circle" then
            r:addAttribute("shortaxis", "long")
          end
          lesion._updateAppearance(r)
          setRegion(r, v)
        else
          error("Attempt to set style of lesion that is not a line region")
        end
      end
      if r ~= nil then
        lesion._removeEllipses(r)
        if type(r) == "lineregion" and r:hasAttribute("shortaxis") then
          lesion._createEllipses(r)
        end
      end      
    else
      error("Unknown lesion Id provided")    
    end
  else
    error("Unknown style specified")
  end
end


-- Returns the style of the lesion, which can be one of:
-- 'point', 'line', 'thin-ellipse', 'thick-ellipse', 'circle', or if the  
-- lesion Id is invalid, nil. 
function lesion.getStyle(lesionId)
  local indexes = lesion.getLesionIndexes(lesionId)
  if #indexes > 0 then
    local r = getRegion(indexes[1])
    local rtype = type(r)
    if rtype == "pointmark" then
      return "point"
    elseif rtype == "lineregion" or rtype == "freehand" then
      local shortAxis = r:getValueForAttribute("shortaxis")
      if shortAxis == "short" then
        return "thin-ellipse"
      elseif shortAxis == "medium" then
        return "thick-ellipse"
      elseif shortAxis == "long" then
        return "circle"
      else
        return "line"
      end
    end 
  else
    error("Unknown lesion Id provided")    
  end
end


-- Returns true if the lesion has been assigned to an anatomic zone
function lesion.lesionHasAssignedZone(r)
  return r:hasAttribute("zone")
end


-- Returns the general zone for the lesion, if one has been set.  The general
-- zone is the zone without a laterality specifier, I.E. '5', rather than '5R'
function lesion.getGeneralZoneForLesion(r)
  return r:getValueForAttribute("generalzone")
end


-- Returns the zone for the lesion, if one has been set.
function lesion.getZoneForLesion(r)
  return r:getValueForAttribute("zone")
end


-- Returns true if the lesion is a soft tissue type.
function lesion.isLesionSoftTissue(r)
  return lesion.getZoneForLesion(r) == "10"
end


-- Assigns a zone to the lesion with the given Id
function lesion.assignZoneToLesion(zoneId, lesionId)
  local indexes = lesion.getLesionIndexes(lesionId)
  if #indexes > 0 then
    lesion._assignZoneToLesion(zoneId, indexes[1])
  end
end


-- Assigns the given zone Id to the specified lesions and their peers.  It is
-- not necessary to list peers when calling the function.
-- The zone Id should be the full form where applicable, I.E. '4R', not just 
-- '4'.
function lesion.assignZoneToLesions(zoneId, lesionIndexes)
  for _, v in ipairs(lesionIndexes) do
    lesion._assignZoneToLesion(zoneId, v)
  end
end


-- Removes the zone assignment (if any) from the specified lesions and their 
-- peers.  It is not necessary to list peers when calling the function.
function lesion.removeZoneFromLesions(lesionIndexes)
  for _, v in ipairs(lesionIndexes) do
    lesion._removeZoneFromLesion(v)
  end   
end


-- Removes lesions with Ids listed in table 't'.
function lesion.deleteLesionWithIdsIn(t)
  for _, lesionId in ipairs(t) do
    lesion.deleteLesionWithId(lesionId)
  end
end


-- Removes the lesion with the given lesion Id.
function lesion.deleteLesionWithId(lesionId)
  lesion._extantLesionIds[lesionId] = nil
  local indexes = lesion.getLesionIndexes(lesionId)
  if #indexes > 0 then
    removeRegions(indexes)
    lesion._regionListChanged()
  end
end


-- Select all lesions for zone.  
function lesion.selectAllLesionsInZone(zoneName) 
  local indexes = lesion.getIndexesOfLesionsInZone(zoneName)
  selectRegions(indexes)
  lesion._regionSelectionsChanged()
end


-- Hides all lesions that are not located in the specified zone.
function lesion.showOnlyLesionsInZone(zoneName)
  if zoneName == "unassigned" or tostring(tonumber(zoneName)) == tostring(zoneName) then
    selectAttributes({{"generalzone", zoneName}})
  else
    selectAttributes({{"zone", zoneName}})
  end
end


-- Hides all lesions for all zones.  Calling this clears any current filtering
-- previously set by a call to lesion.showOnlyLesionsInZone()
function lesion.hideAllLesions()
  selectAttributes({'fakezone'})
end


-- Shows all lesions for all zones.  Call this function to clear any filtering
-- previously set by a call to lesion.showOnlyLesionsInZone()
function lesion.showAllLesions()
  selectAttributes()    
end


-- Returns the centroid of the lesion.
function lesion.getLesionCentroid(r)
  local pos
  if type(r) == "pointmark" then
    pos = r:position()
  elseif type(r) == "lineregion" then
    pos = lesion._getLineMidPoint(r:lineSegment())
  elseif type(r) == "freehand" then
    local poly = r:getPolygon()
    pos = poly:centerOfMass()
  end
  return pos
end


-- Returns the lesion indexes of all lesions that lie inside the given polygon.
-- The polygon should be in described in normal region space.
function lesion.getIndexesOfLesionsInsidePolygon(p)
  return lesion._getIndexesOfLesionsInsidePolygon(p)
end


function lesion.readInLesionFromFile() 
  local map = lesion._readInLesionFromFile() 
  return map
end


-- Is this supposed to be public or private?  It needs documenting if public!
function lesion.createLesionsFromfile(map)
  -- map is a keyed table in which the keyname is the zone, and the value is 
  -- a table suitable for passing directly to a polygon.
  -- mesh._coords = map
  --  local map2=lesion._parsemap(map)
  -- local  isSoftTissue=false
    
  for zone, coordTable in pairs(map) do
    if (not lesion._inMIBGBModified) then
      local p=point.new(coordTable)
      lesion.createPointLesionAuto(p)
    else
      if lesion._mysplit(zone, ":")[2]=="S" then
        isSoftTissue=true
      else
        isSoftTissue=false
      end
    
      if lesion._mysplit(zone, ":")[3]=="3" then
       isScore3=true
      else
       isScore3=false
      end
    
      if #coordTable==1 then  -- point
        local p=point.new(coordTable[1])        
        lesion.createPointLesionAuto(p,isSoftTissue)
      else  --#coordTable>=2   --line or multipoint		
        lesion.createLineorPoly(coordTable,isSoftTissue,isScore3)	
      end
    end
  end
 
  -- lesion._updateZoneScores()
  -- lazy hack to invert Roger's coords into Abras cartesian coords.
  --mesh._copyMeshCoordsFromRegions()     
end


-- Is this supposed to be public or private?  It needs documenting if public!
function lesion.createLineorPoly(coordTable, isSoftTissue, isScore3)
  local lineseg
  local r
  local p
  local pnta
  local pntb
  
  if #coordTable ==2 then
    pnta = point.new(coordTable[1])
    pntb = point.new(coordTable[2])
    r =lineregion.new(pnta,pntb)
  else
    p = polygon.new(coordTable)
    -- r = multipoint.new(p)
    r = freehand.new(p)
  end

  r:setAssociations({getCurrentPrimaryFileName()})

  if isSoftTissue then
    r:addAttribute("zone", "10")
    r:addAttribute("generalzone", "10")
  else
    r:addAttribute("zone", "unassigned")
    r:addAttribute("generalzone", "unassigned")
  end

  if isScore3 then
    r:addAttribute("score3")
  end

  r:setThickness(1.0)
  local lesionId = lesion._getNextFreeLesionId()
  lesion._setLesionId(r, lesionId)
  lesion._setLesionOriginal(r)
  lesion._updateAppearance(r)
  setRegion(r)
  lesion._createMirrorLesion(r)
  lesion._regionListChanged()
end


-- ===========================================================================
-- Events

-- Sets a handler function for lesion context menu.  The handler will be 
-- called when the user right clicks on a lesion.
function lesion.setContextMenuHandler(handlerFunc)
  lesion._contextMenuHandler = handlerFunc
end


-- Adds a listener function that will be called when the list of lesions 
-- changes.  
function lesion.addListChangedListener(listenerFunc)
  mibg.addToListIfNotPresent(lesion._listChangedListeners, listenerFunc)    
end


-- Removes a previously registered listener.
function lesion.removeListChangedListener(listenerFunc)
  mibg.removeFromList(lesion._listChangedListeners, listenerFunc)    
end


-- Adds a listener function that will be called when a lesion changes.  
function lesion.addChangedListener(listenerFunc)
  mibg.addToListIfNotPresent(lesion._changedListeners, listenerFunc)    
end


-- Removes a previously registered listener.
function lesion.removeChangedListener(listenerFunc)
  mibg.removeFromList(lesion._changedListeners, listenerFunc)    
end


-- Adds a listener function that will be called when the user has finished 
-- placing a lesion.  This is a special case of list changed in that it only
-- does not fire for programmitically created lesions, and only fires when the 
-- user has finished placing the lesion.
function lesion.addPlacedListener(listenerFunc)
  mibg.addToListIfNotPresent(lesion._placedListeners, listenerFunc)    
end


-- Removes a previously registered listener.
function lesion.removePlacedListener(listenerFunc)
  mibg.removeFromList(lesion._placedListeners, listenerFunc)    
end
 

-- Adds a listener function that will be called when the list of lesion 
-- selections changes.  If any regions are selected that are not lesions, the 
-- selection will be considered as having no lesion selections. 
function lesion.addSelectionChangedListener(listenerFunc)
  mibg.addToListIfNotPresent(lesion._selectionChangedListeners, listenerFunc)    
end


-- Removes a previously registered listener.
function lesion.removeSelectionChangedListener(listenerFunc)
  mibg.removeFromList(lesion._selectionChangedListeners, listenerFunc)    
end


-- ===========================================================================
-- Private event handlers.

function lesion._toolModeChanged(mode)
  function writelesionassign(sublesionpath)
    local f = io.open(sublesionpath, "w+")
    local indtbl = lesion.getIndexesOfAllLesions()
    f:write("Lesion Index".."\t".."Zonename".."\n")
    for i, v in ipairs(indtbl) do
      if math.mod(i,2)==1  then
        local r = getRegion(v)
        zonename =r:getValueForAttribute("generalzone")
        f:write(v.."\t"..zonename.."\n")
      end
    end
    f:close() 
  end
  
  -- called when the user changes the tool mode (mibg library)
  if mode == "edit" then
    -- in 'edit' mode standard Abras controls are used
    mouse.clear()
  elseif mode == 'draw' then
    -- in 'draw' mode we capture mouse to provide customs drawing.  Lesion 
    -- placement is thus handled hee rather than by letting Abras do its thing  
    mouse.clear()
    mouse.setMouseDownHandler(lesion._mouseDown)
    mouse.setMouseUpHandler(lesion._mouseUp)
    mouse.setMouseDragHandler(lesion._mouseDrag)
  elseif mode=="import" then             --import lesion
    local map =lesion.readInLesionFromFile()
	  lesion.createLesionsFromfile(map)
	  updateLesionZones()
	  if (lesion._inMIBGBModified) then
      --local sublesion = subdir:child("lesionassignfirst.txt")
      -- local sublesionpath =sublesion:fullPathName() 
	    local sublesionpath = outParticipantDataRoot .. "lesionassignfirst.txt";
      writelesionassign(sublesionpath)
	    --leftPanelResized(mibg.getLeftPanel())
      rightPanelResized(mibg.getRightPanel())
    end
	  mouse.clear()
  end
end


function lesion._regionListChanged()
  -- Called when the user changes the list of regions in some way (see mibg 
  -- library).
  -- If changes impact lesions, generate a corresponding lesion list changed 
  -- event.
  local numRegions = getNumberOfRegions()
  lesion._removeLesionPeerIfNeeded()  
  if numRegions ~= getNumberOfRegions() or lesion._updateExtantLesionIds() then
    -- User deleted one region, and peer was cleaned up, or user deleted both
    -- peers.
    lesion._clearZoneScores()
    mibg.callListeners(lesion._listChangedListeners)
  end
end


function lesion._regionSelectionsChanged()
  -- Called when the user selects or deselects regions (see mibg library).
  -- If lesion selection states change, generate a corresponding lesion 
  -- selection changed event.
  lesion._updateEllipseHandlesShown()
  if lesion._updateSelectedLesionIds() then
    mibg.callListeners(lesion._selectionChangedListeners)
  end
end


function lesion._regionChanged(index)
  -- Called when the user changes a region in some way (see mibg library).
  -- If change impacts a lesion, generate a corresponding lesion changed 
  -- event.
  local r = getRegion(index)
  if r ~= nil then
    if lesion.isRegionALesion(r) then
      lesion._clearZoneScores()
      lesion._updateLesionPeer(r)
      if type(r) == "lineregion" then
        local lesionId = lesion.getIdForLesion(r)
        lesion._updateEllipses(lesionId)  
      end 

      if (not lesion._inMIBGBModified) then
        mibg.callListeners(lesion._changedListeners, index)
      end 
    end
  end
end


--[[function lesion._mouseDown(p, x, y, b, m)
  -- (See mouse library) Only fires during initial placement of lesion
  -- Creates a new pointmark lesion at the mouse down co-ords.
  lesion._newLesionId = nil
  if (b ~= PopupButton) then
    lesion._createNewLesionAt(p, x, y, m)
  end
end
]]
function lesion._mouseDown(p, x, y, b, m)
  -- (See mouse library) Only fires during initial placement of lesion
  -- Creates a new pointmark lesion at the mouse down co-ords.
  lesion._newLesionId = nil
  if (b ~= PopupButton) then
    local lesionId = lesion._createNewLesionAt(p, x, y, m)

    if lesionId then
      -- Assign selected attribute to new lesion
      local attribs = getSelectedAttributes()
      if #attribs == 1 and attribs[1][1] == "zone" then
        local indexes = lesion.getLesionIndexes(lesionId)
        lesion.assignZoneToLesions(attribs[1][2], indexes)
      end
    end
  end
end


function lesion._mouseUp(p, x, y,b,m)
  -- (See mouse library) Only fires during initial placement of lesion
  -- Generates a lesion placed event.
  if lesion._newLesionId ~= nil then
    local index = lesion._getOriginalLesionIndex(lesion._newLesionId)
    lesion._newLesionId = nil
    local r=getRegion(index)
    if r:type() =="Line"  then
    seg=r:lineSegment()
    linelength =seg:length() 
     if linelength <0.015 then
        pt =seg:a()
        removeRegion(index)
        lesion._newLesionId = lesion._createNewLesion(pt, (m == AltModifier))
        local lesionId =lesion._newLesionId
        if lesionId then
          -- Assign selected attribute to new lesion
          local attribs = getSelectedAttributes()
          if #attribs == 1 and attribs[1][1] == "zone" then
            local indexes = lesion.getLesionIndexes(lesionId)
            lesion.assignZoneToLesions(attribs[1][2], indexes)
         end
       end
       index =lesion._getOriginalLesionIndex(lesionId)
     end
    
   end
 
    -- TODO: need to switch selected region here
    mibg.callListeners(lesion._placedListeners, index)
  end
end


function lesion._mouseDrag(p, x, y,m)
  -- (See mouse library) Only fires during initial placement of lesion
  -- If necessary, converts a point lesion to a line.  Updates coords. 
  if lesion._newLesionId ~= nil then
    local index = lesion._getOriginalLesionIndex(lesion._newLesionId)
    if index then
      local r = getRegion(index)
      if type(r) == 'pointmark' then
        lesion._convertLesionToLine(lesion._newLesionId)
        selectRegions({index})
      else
        lesion._updateLineEndpoint(index, x, y)
      end
    end
  end
end




function lesion.createPointLesionAuto(p,isSoftTissue)

--function lesion.createPointLesionAuto(p)
    lesion._createNewLesion(p, isSoftTissue)
end


-- ===========================================================================
-- Private functions

--[[function lesion._createNewLesionAt(p, x, y, m)
  -- Verifies the the creation co-ordinates are valid, if so creates a point 
  -- lesion
  local pos = point.new(x, y)
  pos = p:convertDisplayPixelToRegionCoordinate(pos)
  if pos:x() >= 0 and pos:x() <= 1.0 and pos:y() >= 0 and pos:y() <= 1.0 then
    lesion._newLesionId = lesion._createNewLesion(pos, (m == AltModifier))
  end
end
]]


function lesion._createNewLesionAt(p, x, y, m)
  -- Verifies the the creation co-ordinates are valid, if so creates a point
  -- lesion
  local pos = point.new(x, y)
  pos = p:convertDisplayPixelToRegionCoordinate(pos)
  if pos:x() >= 0 and pos:x() <= 1.0 and pos:y() >= 0 and pos:y() <= 1.0 then
    lesion._newLesionId = lesion._createNewLesion(pos, (m == AltModifier))
    return lesion._newLesionId
  end
end



function lesion._createNewLesion(pos, isSoftTissue)
  -- Creates a new pointmark and its peer at the given x/y and peer x/y  
  local r = lesion._createOriginalLesion(pos, isSoftTissue)
  lesion._createMirrorLesion(r)
  local lesionId = lesion.getIdForLesion(r)
  lesion._extantLesionIds[lesionId] = true
  lesion._clearZoneScores()
  selectRegions({getNumberOfRegions() - 1})
  lesion._updateSelectedLesionIds()
  mibg.callListeners(lesion._listChangedListeners, nil)  
  mibg.callListeners(lesion._selectionChangedListeners, nil)  
  return lesionId
end


function lesion._createOriginalLesion(pos, isSoftTissue)
  local r = pointmark.new(pos)
  r:setCrosshairType(pointmark.crosshair)
  r:setCrosshairSize(10)
  r:associateWith(getCurrentPrimaryFileName())
  if isSoftTissue then
    r:addAttribute("zone", "10")
    r:addAttribute("generalzone", "10")
  else
    r:addAttribute("zone", "unassigned")
    r:addAttribute("generalzone", "unassigned")
  end
  
  local lesionId = lesion._getNextFreeLesionId()
  lesion._setLesionId(r, lesionId)
  lesion._setLesionOriginal(r)
  lesion._updateAppearance(r)
  lesion._clearZoneScores()  
  setRegion(r)
  return r
end


function lesion._getNextFreeLesionId()
  -- Brute force search for the highest current lesion Id + 1
  local id = 0
  local indexes = getIndexesOfRegionsWithAttribute("id")
  for _, index in ipairs(indexes) do
    local r = getRegion(index)
    local lesionId = lesion.getIdForLesion(r)
    lesionId = tonumber(lesionId)
    if lesionId > id then
      id = lesionId
    end
  end
  return id + 1
end


function lesion._createMirrorLesion(r)
  -- Create a lesion that is the mirrored peer of the passed one.
  lesion._unsetLesionOriginal(r)
  lesion._updateAppearance(r)
  lesion._copyAndMirrorCoordinates(r, r)
  setRegion(r)
end


function lesion._copyAndMirrorCoordinates(r1, r2)
  if type(r1) == "pointmark" then
    local p = r1:position()
    r2:setPosition(1 - p:x(), p:y())
  elseif type(r1) == "lineregion" then
    local l = r1:lineSegment()
    l:setA(point.new(1 - l:a():x(), l:a():y()))
    l:setB(point.new(1 - l:b():x(), l:b():y()))
    r2:setLineSegment(l)
  elseif (lesion._inMIBGBModified) then         --multiline
     local p =r1:getPolygon()
 --[[    local ptable = p:getAsTable()
     local ptablecopy={}
     for i,v in pairs(ptable) do
     	ptablecopy[i] ={1- v[1],v[2]}
     end
     ]]--
     p:displaceBy(-1, 0)
     p:scaleBy(-1, 1)
     r2:setPolygon(p)
  end  
end


function lesion._removeLesionPeerIfNeeded()
  -- Any lesions with missing peers will be removed.  Return true if deletions
  -- were needed.
  local result = false
  local lesionIds = {}
  local numRegions = getNumberOfRegions()
  for i = 1, numRegions do
    local r = getRegion(i)
    if not r:hasAttribute("ellipseid") then
      local lesionId = lesion.getIdForLesion(r)
      if lesionId ~= nil then
        if lesionIds[lesionId] == nil then
          lesionIds[lesionId] = true
        else
          lesionIds[lesionId] = nil
        end
      end
    end
  end
  
  for lesionId, _ in pairs(lesionIds) do
    lesion.deleteLesionWithId(lesionId)
    result = true
  end
  return result  
end 


function lesion._updateEllipseHandlesShown()
  -- If an ellipse is selected, we show it's peer line.  We do this simply
  -- by selecting the line for the selected ellipses.
  local indexes = getIndexesOfSelectedRegions()
  for i, index in ipairs(indexes) do
    local r = getRegion(index)
    if r:hasAttribute("ellipseid") then
      table.insert(indexes, lesion._getEllipsePeerLineIndex(r))
    end
  end  
  selectRegions(indexes)
end


function lesion._getEllipsePeerLineIndex(r)
  local lesionId = lesion.getIdForLesion(r)
  local indexes = lesion.getLesionIndexes(lesionId)
  local p = r:getPolygon()
  local isLeft = p:vertex(1):x() < 0.5
  for _, v in ipairs(indexes) do 
    local r2 = getRegion(v)
    if type(r2) == "lineregion" then
      if isLeft == (r2:a():x() < 0.5) then
        return v
      end
    end
  end  
end


function lesion._removeEllipses(r)
  -- Remove any existing ellipse regions, and create new ones if needed.
  local lesionId = lesion.getIdForLesion(r)
  if lesionId ~= nil then
    local indexes = getIndexesOfRegionsWithAttribute("ellipseid", lesionId)
    removeRegions(indexes)
  end
end


function lesion._getRatioForEllipse(style)
  if style == "thin-ellipse" then
    return 8
  elseif style == "thick-ellipse" then
    return 4
  end
  return 1  
end


function lesion._createEllipses(r)
  -- creates ellipse peers corresponding to the long axis line segment for 
  -- lesion r.
  local lesionId = lesion.getIdForLesion(r)
  local indexes = lesion.getLesionIndexes(lesionId)
  if #indexes > 0 then
    r = getRegion(indexes[1])
    local l = r:lineSegment()
    local style = lesion.getStyle(lesionId)
    local ratio = lesion._getRatioForEllipse(style)
    local poly = lesion._getEllipsePolygonForLine(l, ratio)
    local ellipse = freehand.new(poly)
    ellipse:addAttribute("id", lesionId)
    ellipse:addAttribute("ellipseid", lesionId)
    ellipse:setAssociations(r:getAssociations())
    ellipse:setThickness(1.0)
    lesion._updateAppearance(ellipse)
    setRegion(ellipse)
    
    if #indexes > 1 then
      r = getRegion(indexes[2])
      l = r:lineSegment()
      poly = lesion._getEllipsePolygonForLine(l, ratio)
      ellipse:setPolygon(poly)
      lesion._updateAppearance(ellipse)
      setRegion(ellipse)
    end
  end
end


function lesion._updateEllipses(lesionId)
  local indexes = lesion.getLesionIndexes(lesionId)
  for _, index in ipairs(indexes) do
    local r = getRegion(index)
    if type(r) == "freehand" then
      local lineIndex = lesion._getEllipsePeerLineIndex(r)
      local l = getRegion(lineIndex)
      l = l:lineSegment()
      local style = lesion.getStyle(lesionId)
      local ratio = lesion._getRatioForEllipse(style)      
      local p = lesion._getEllipsePolygonForLine(l, ratio)
      r:setPolygon(p)
      setRegion(r, index)
    end 
  end
end


function lesion._getLineMidPoint(l)
  local a = l:a()
  local b = l:b()
  return point.new(a:x() + ((b:x() - a:x()) / 2), a:y() + ((b:y() - a:y()) / 2))
end


function lesion._getEllipsePolygonForLine(l, ratio)
  -- We need to do this operation in pixel space as image wont be square
  local mi = getImage(getCurrentPrimaryFileName())
  
  if mi ~= nil then
    l = linesegment.new(l)
    l:scaleBy(mi:width(), mi:height())
  end
  
  local p = polygon.new()
  local a  = l:length() / 2
  local b = a / ratio
  local theta = linesegment.new(l:ax(), l:ay(), l:bx(), l:ay()):angleBetweenVectors(l)
  local center = lesion._getLineMidPoint(l)
  for t = 0, 2 * math.pi, 0.1 do
    local x = center:x() + (a * math.cos(t) * math.cos(theta)) - (b * math.sin(t) * math.sin(theta))
    local y = center:y() + (a * math.cos(t) * math.sin(theta)) - (b * math.sin(t) * math.cos(theta))
    p:addVertex(x, y)
  end
  
  if mi ~= nil then
    p:scaleBy(1 / mi:width(), 1 / mi:height())
  end
  
  return p
end


function lesion._updateLesionPeer(r)  
  local isOriginal = lesion.isLesionOriginalMark(r)
  local lesionId = lesion.getIdForLesion(r)
  if lesionId ~= nil then
    local indexes = lesion.getLesionIndexes(lesionId)
    local regions = {}
    for _, index in ipairs(indexes) do
      local r1 = getRegion(index)
      if not r1:hasAttribute("ellipseid") then
        if lesion.isLesionOriginalMark(r1) == isOriginal then
          regions[1] = {index, r1}
        else
          regions[2] = {index, r1}
        end
      end
    end
    
    if #regions == 2 then
      lesion._copyAndMirrorCoordinates(regions[1][2], regions[2][2])
      setRegion(regions[2][2], regions[2][1])
    end
  end
end



function lesion._convertLesionToLine(lesionId)
  local indexes = lesion.getLesionIndexes(lesionId)
  if #indexes > 0 then
    local r = getRegion(indexes[1])
    if lesion.isRegionALesion(r) and type(r) == 'pointmark' then
      removeRegions(indexes)

      -- Create original
      local softTissueType = lesion.isLesionSoftTissue(r)
      local attribs = r:getAttributes()
      local pos = r:position()
      r = lineregion.new(pos, pos)
      r:associateWith(getCurrentPrimaryFileName())
      r:setAttributes(attribs)
      r:setThickness(1.0)
      lesion._setLesionOriginal(r)
      lesion._updateAppearance(r)
      setRegion(r)
      lesion._createMirrorLesion(r)
      lesion._regionListChanged()
    end
  end
end


function lesion._updateLineEndpoint(lesionIndex, x, y)
  local r = getRegion(lesionIndex)
  if type(r) == "lineregion" then
    local pos = point.new(x, y)
    local p = getDisplayPanel()
    pos = p:convertDisplayPixelToRegionCoordinate(pos)
    r:setB(pos)
    setRegion(r, lesionIndex)
    lesion._updateLesionPeer(r)
  end
end


function lesion._getOriginalLesionIndex(lesionId)
  local indexes = lesion.getLesionIndexes(lesionId)
  for _, v in ipairs(indexes) do
    local r = getRegion(v)
    if lesion.isLesionOriginalMark(r) then
      return v
    end
  end
end


function lesion._setLesionScore3Type(lesionId, isScore3)
  local orig
  local indexes = lesion.getLesionIndexes(lesionId)
  for _, v in ipairs(indexes) do
    local r = getRegion(v)
    if isScore3 then
      r:addAttribute("score3")
    else
      r:removeAttribute("score3")
    end
    setRegion(r, v)
    if lesion.isLesionOriginalMark(r) then
      orig = v  
    end  
  end
  lesion._clearZoneScores()      

  if orig ~= nil then
    lesion._regionChanged(orig)
  end    
end


function lesion._assignZoneToLesion(zoneId, lesionIndex)
  local orig
  local r = getRegion(lesionIndex)
  if r ~= nil then
    local lesionId = lesion.getIdForLesion(r)
    if lesionId ~= nil then
      local indexes = lesion.getLesionIndexes(lesionId)
      for _, v in ipairs(indexes) do
        r = getRegion(v)
        if not lesion.isLesionSoftTissue(r) then
          if lesion.getZoneForLesion(r) ~= zoneId then
            r:addAttribute("zone", zoneId)
            r:addAttribute("generalzone", zoneId:match("^%d+"))
            setRegion(r, v)
            if lesion.isLesionOriginalMark(r) then
              orig = v
            end
          end
        else
          mibg.logError("Attempt to overrwrite zone for soft tissue lesion.")
        end
      end
      lesion._clearZoneScores()      
    end
  end  
  
  if orig ~= nil then
    lesion._regionChanged(orig)
  end      
end


function lesion._removeZoneFromLesion(lesionIndex)
  local orig
  local r = getRegion(lesionIndex)
  if r ~= nil then
    local lesionId = lesion.getIdForLesion(r)
    if lesionId ~= nil then
      local indexes = lesion.getLesionIndexes(lesionId)
      for _, v in ipairs(indexes) do
        r = getRegion(v)
        if not lesion.isLesionSoftTissue(r) then
          if lesion.lesionHasAssignedZone(r) then
            r:removeAttribute("generalzone")
            r:removeAttribute("zone")
            setRegion(r, v)
            if lesion.isLesionOriginalMark(r) then
              orig = v
            end
          end
        else
          mibg.logError("Attempt to overrwrite zone for soft tissue lesion.")
        end
      end
      lesion._clearZoneScores()      
    end
  end  
  
  if orig ~= nil then
    lesion._regionChanged(orig)
  end        
end


function lesion._setLesionId(r, lesionId)
  r:addAttribute("id", lesionId)
end


function lesion._setLesionOriginal(r)
  r:addAttribute("original")
end


function lesion._unsetLesionOriginal(r)
  r:removeAttribute("original")
end


function lesion._clearZoneScores()
  lesion._zoneScores = nil
end


function lesion._updateAppearance(r)
  -- Originals are yellow, peers are blue.
  local normal
  if lesion.isLesionOriginalMark(r) then
    normal = 0x00FFFF00
 else
    normal = 0x000000FF
  end
  
  -- All regions are red when selected except ellipses
  local selected
  if r:hasAttribute("ellipseid") then
    selected = 0x800000FF
  else
    selected = 0xFFFF0000  
  end
  
  -- All regions have a near full alpha except unselected ellipse long axis
  local alpha = 0xFF000000
  if type(r) == "lineregion" then
    if r:hasAttribute("shortaxis") then
      r:setEndTypes(lineregion.none, lineregion.none)
      alpha = 0
    else
      r:setEndTypes(lineregion.tbar, lineregion.tbar)
    end
  end
  
  r:setOutlineColours(alpha + normal, selected)
end


function lesion._updateZoneScores()
  local lookup = {}
    
  -- local function performs score calculation
  function updateScore(zoneName, isScore3)
    if zoneName == nil then
      lookup['unassigned'] = lookup['unassigned'] + 1
    elseif isScore3 then 
      lookup[zoneName] = 3
    else
      if lookup[zoneName] == 0 then
        lookup[zoneName] = 1
      elseif lookup[zoneName] == 1 then 
        lookup[zoneName] = 2
      end
    end
  end
  
  -- clear scores
  for _, v in ipairs(lesion.zones) do
    lookup[v] = 0
    if tonumber(v) == nil then
      lookup[v:sub(1, 1)] = 0
    end
  end
  lookup['unassigned'] = 0

  -- We're just grabbing everything here from the region list
  local numRegions = getNumberOfRegions()
  for i = 1, numRegions do
    local r = getRegion(i)
    if lesion.isLesionOriginalMark(r) then
      local generalZone = lesion.getGeneralZoneForLesion(r)
      local zone = lesion.getZoneForLesion(r)
      updateScore(generalZone, lesion.isLesionAScore3Type(r))
      if zone ~= generalZone then
        updateScore(zone, lesion.isLesionAScore3Type(r))
      end
    end
  end
    
  lesion._zoneScores = lookup
end


function lesion._updateExtantLesionIds()
  local result = false
  local t = {}
    
  local indexes = getIndexesOfRegionsWithAttribute("id")
  for _, index in ipairs(indexes) do
    local r = getRegion(index)
    if lesion.isRegionALesion(r) then
      local lesionId = lesion.getIdForLesion(r)
      t[lesionId] = true
      if lesion._extantLesionIds[lesionId] == nil then
        result = true
      else
        lesion._extantLesionIds[lesionId] = nil
      end
    end
  end

  -- t contains current lesions, and _extantLesionIds contains deleted lesions 
  result = result or (next(lesion._extantLesionIds) ~= nil) 
  
  lesion._extantLesionIds = t
  return result
end


function lesion._updateSelectedLesionIds()
  local result = false
  local t = {}

  local indexes = getIndexesOfSelectedRegions()
  for _, index in ipairs(indexes) do
    local r = getRegion(index)
    if lesion.isRegionALesion(r) then
      local lesionId = lesion.getIdForLesion(r)
      t[lesionId] = true
      if lesion._selectedIds[lesionId] == nil then
        result = true
      else
        lesion._selectedIds[lesionId] = nil
      end
    else 
      t = {}
      result = false
      break
    end
  end

  -- t contains current selections, and _selectedIds contains deselecteds 
  result = result or (next(lesion._selectedIds) ~= nil) 
  
  lesion._selectedIds = t
  return result
end


-- ===========================================================================
-- Style dialog and menu

function lesion._showLesionStyleDialog(lesionId)
  local w = window.new()
  w:setTitle("Lesion type")
  w:setInnerWidth(430)
  w:setInnerHeight(300)
  
  local l = label.new("You can specify a style for the lesion from the following geometries.\n\nNote that you can always change this value later.")
  l:setBounds(6, 6, 418, 96)
  w:addChild(l)
  
  local b = button.new('line')
  b:setRadioId(1)
  b:setBounds(6, 102, 100, 24) 
  b:setBackgroundColour(SAFE_BUTTON)
  b:setDown(true)
  w:addChild(b)
  
  b = button.new('thin ellipse')
  b:setRadioId(1)
  b:setBounds(112, 102, 100, 24) 
  b:setBackgroundColour(SAFE_BUTTON)
  w:addChild(b)
  
  b = button.new('thick ellipse')
  b:setRadioId(1)
  b:setBounds(218, 102, 100, 24) 
  b:setBackgroundColour(SAFE_BUTTON)
  w:addChild(b)
  
  b = button.new('circle')
  b:setRadioId(1)
  b:setBounds(324, 102, 100, 24) 
  b:setBackgroundColour(SAFE_BUTTON)
  w:addChild(b)
  
  local p = panel.new()
  p:setBackground(0xFF808080)
  p:setBounds(0, 132, 430, 133)
  
  l = label.new("Please specify whether this lesion has more than 50% involvement.")
  l:setBounds(6, 139, 418, 23)
  w:addChild(l)

  b = button.new("normal lesion")
  b:setBounds(112, 168, 100, 24)
  b:setBackgroundColour(WARNING_BUTTON)
  b:setOnClicked("_lesion_normalClicked")
  w:addChild(b)
  
  b = button.new("50% involvement")
  b:setBounds(218, 168, 100, 24)
  b:setBackgroundColour(WARNING_BUTTON)
  b:setOnClicked("_lesion_score3Clicked")
  w:addChild(b)
  
  b = button.new("cancel")
  b:setBounds(324, 168, 100, 24)
  b:setBackgroundColour(DANGER_BUTTON)
  b:setOnClicked("_lesion_cancelClicked")
  w:addChild(b)
  
  local result
  local option = w:showModal()
  if option ~= 0 then
    result = {}
    result.score3Type = (option == 2)
    result.style = "line"
    if w:getChild("thin ellipse"):isDown() then
      result.style = "thin-ellipse"
    elseif w:getChild("thick ellipse"):isDown() then
      result.style = "thick-ellipse"
    elseif w:getChild("circle"):isDown() then
      result.style = "circle"
    end
  end
  return result  
end


function _lesion_normalClicked(b)
  b:parent():hideModal(1)
end


function _lesion_score3Clicked(b)
  b:parent():hideModal(2)
end


function _lesion_cancelClicked(b)
  b:parent():hideModal(0)
end

function lesion.getIndexesOfLesionsInsideSpecialPolygon(p)
  local result = {}
  local lesionIndexes = getIndexesOfRegionsWithAttribute("id")
--  mibg.logError("lesion with id:  "..#lesionIndexes)
  for _, index in ipairs(lesionIndexes) do
    local r = getRegion(index)
    
    if not lesion.isLesionSoftTissue(r) then
      local pos = nil
      if type(r) == "pointmark" then
        pos = r:position()
      elseif type(r) == "lineregion" then
        pos = lesion._getLineMidPoint(r:lineSegment())
      elseif (lesion._inMIBGBModified) then
        local poly= r:getPolygon()
        pos = poly:centerOfMass()
      end
      
      if pos ~= nil then
        if p:contains(pos) then
             	table.insert(result, index)
         end
      end          
    end    
  end
 -- mibg.logError("lesion with id2:  "..#result)
  return result
end


function lesion._readInLesionFromFile() 
  local dofile = dofile
  local lesionFile = lesion._lesionReadFilespecObj
  
  if lesionFile:exists() then
    local path = lesionFile:fullPathName()
    --    showMessage(path)
    -- Run the result file as raw Lua.
    lesionreg = dofile(path)
  else
    lesionreg = {error = "Result file not generated"}
  end
  return lesionreg
end


function lesion._mysplit(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  t={}
  i=1
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    t[i] = str
    i = i + 1
  end
  return t
end


function lesion._parsemap(lesmap)
  local deltbl = {}
  local changetbl= {}
  for i,v in pairs(lesmap) do
    if #v>2 then
      table.insert(deltbl,i)
      --find corresponding line
      lastline= lesion._mysplit(i,":")[1]-1
      -- print(lastline)
      for j,v in pairs(lesionreg) do
        if lesion._mysplit(j,":")[1]-0==lastline then
          table.insert(changetbl,j)
          --    print(j)
        end
      end
    end
  end

  for i,v in pairs(deltbl) do    
    --   lesmap[changetbl[i]] =lesmap[v]
    lesmap[v] =nil
  end 
  return(lesmap)
end


-- ===========================================================================
-- Lesion in poly tests

function lesion._getIndexesOfLesionsInsidePolygon(p)
  local result = {}
  local lesionIndexes = getIndexesOfRegionsWithAttribute("id")
--  mibg.logError("lesion with id:  "..#lesionIndexes)
  for _, index in ipairs(lesionIndexes) do
    local r = getRegion(index)
    
    if not lesion.isLesionSoftTissue(r) then
      local pos = lesion.getLesionCentroid(r)
      
      if pos ~= nil then
        if p:contains(pos) then
          local idvalue =r:getValueForAttribute("id")
          local coidindexes =getIndexesOfRegionsWithAttribute("id", idvalue)
          --if the lesion in poly is original , add the lesion index, Otherwise, add peer index
          if r:hasAttribute("original") then         
          	table.insert(result, index)
          else
            if index == coidindexes[1] then
            	table.insert(result, coidindexes[2])
            else
              table.insert(result, coidindexes[1]) 
            end
          end
        end
      end          
    end    
  end
  --mibg.logError("lesion with id2:  "..#result)
  return result
end


