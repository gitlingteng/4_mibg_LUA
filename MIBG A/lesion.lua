-- ===========================================================================
-- A library that provides lesion support for the various MIBG interfaces.
--
-- Developed by Adam Starkey, Ling Teng, and Roger Engelmann.
-- 
-- Copyright (c) The University of Chicago - 2012 - 2013
-- All rights reserved.
--
-- ---------------------------------------------------------------------------
--
-- 12/05/2013 - Cleaned up color code such that colors are defined as named 
--              values, rather than local hardcoded values.  Added function
--              to dim/undim lesions.
--              
-- 12/05/2013 - Fixed misnamed function.
--
-- 12/05/2013 - Added region styling tweaks.  Fixed misnamed function.
-- 
-- 12/03/2013 - Added a clearAll() helper function.
--
-- 11/25/2013 - Total rework of the API.  All public functions now use lesion 
--              IDs exclusively.  Region indexes, and indeed, the regions 
--              themselves are not exposed.
--              User interaction logic has been spun off in an effort to 
--              finally transition to something more akin to an MVC pattern. 
--              It is now up to your application 'controller' code to handle
--              mouse interactions.
--
-- 11/19/2013 - Fixed bug where assigned count was being improperly treated as
--              scorable zone.
--
-- 11/19/2013 - Fixed cache invalidation bug that caused multiple lesion 
--              deletion to not send an event for the last lesion.
--              Further optimized to allow multiple deletions to coalesce 
--              events down into a single post group deletion event.
--
-- 11/18/2013 - Added a couple of helper functions to aid obtaining the lesion
--              pair regions.
--
-- 11/15/2013 - Added back support for soft-lesions having different color to
--              normals.
--
-- 11/14/2013 - Removed direct tool button interaction from library.
--              Updated mouse behaviour to match modified mouse library.
--              Fixed lesion._mouseUp() bugs.
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
function lesion.initialize()
  if mibg == nil then
    error("Missing MIBG library")
  end

  if mouse == nil then
    error("Missing mouse library")
  end
  
  lesion._selectedColor = 0xFFFF0000              -- Red
  lesion._unassigned = 0xFF0000FF                 -- Blue
  lesion._lesionColor = 0xFFFF00FF                -- Magenta
  lesion._score3LesionColor = 0xFF0080FF          -- Turquoise
  lesion._peerColor = 0xFF00FF00                  -- Green
  lesion._softTissueColor = 0xFFFFFF00            -- Yellow
  lesion._score3SoftTissueColor = 0xFFFFA000      -- Orange
  
  lesion._showDimmed = false
  
  lesion._lesionIdRegionIndexes = nil
  lesion._selectedIds = nil
  lesion._blockEvents = false

  lesion._listChangedListeners = {}
  lesion._changedListeners = {}
  lesion._selectionChangedListeners = {}

  mibg.addRegionListChangedListener(lesion._regionListChanged)
  mibg.addRegionSelectionsChangedListener(lesion._regionSelectionsChanged)
  mibg.addRegionChangedListener(lesion._regionChanged)

  lesion.caseChanged()
end


-- Call this function to release any handlers set by this library.
function lesion.clearAll()  
  mibg.removeRegionListChangedListener(lesion._regionListChanged)
  mibg.removeRegionSelectionsChangedListener(lesion._regionSelectionsChanged)
  mibg.removeRegionChangedListener(lesion._regionChanged)
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
  lesion._lesionIdRegionIndexes = nil
  lesion._selectedIds = nil
  lesion._blockEvents = false
  
  selectRegions()  
  
   mibg.callListeners(lesion._listChangedListeners)
   mibg.callListeners(lesion._selectionChangedListeners)
end


-- Returns a list of all current lesion Ids.
function lesion.getAllLesionIds()
  return lesion._getAllLesionIds()
end


-- Returns the IDs of any selected lesions.  (Note that if any non-lesion
-- regions are selected, this function will return an empty set.
function lesion.getSelectedLesionIds()
  return lesion._getSelectedLesionIds()
end


-- Returns true if any lesions are currently selected.
function lesion.areAnyLesionsSelected()
  local ids = lesion.getSelectedLesionIds()
  return #ids > 0  
end


-- Returns the IDs of all lesions that are assigned to the given zone.
--
-- zoneId               - The id of the zone.  This can be the general or full
--                        form.
function lesion.getIdsOfLesionsWithZone(zoneId)
  return lesion._getIdsOfLesionsWithZone(zoneId)
end


-- Retunrs the Ids of all lesions that aren't currently assigned to any zones.
function lesion.getIdsOfUnassignedLesions()
  return lesion._getIdsOfUnassignedLesions()
end
  

-- Specifies whether the given lesion is a score 3 lesion
--
-- lesionId             - The id of the lesion.
-- shouldBeScore3Type   - A boolean flag that defines whether this lesion 
--                      - is a score 3 (> 50% involvement) type or not.
-- sendMessage          - If true, this function will generate a lesion 
--                      - change event.
function lesion.setLesionScore3Type(lesionId, shouldBeScore3Type, sendMessage)
  if lesion._isLesionAScore3Type(lesionId) ~= shouldBeScore3Type then
    lesion._setLesionScore3Type(lesionId, shouldBeScore3Type)

    if sendMessage then
      lesion._callEvent(lesion._changedListeners, lesionId)
    end
  end
end


-- Returns true if given lesion is a score 3 (> 50% involvement) lesion
--
-- lesionId             - The id of the lesion.
function lesion.isLesionAScore3Type(lesionId)
  return lesion._isLesionAScore3Type(lesionId)
end


-- Returns true if the lesion has been assigned to an anatomic zone
--
-- lesionId             - The id of the lesion.
function lesion.lesionHasAssignedZone(lesionId)
  return lesion._lesionHasAssignedZone(lesionId)
end


-- Returns the general zone for the lesion, if one has been set.  The general
-- zone is the zone without a laterality specifier, I.E. '5', rather than '5R'
--
-- lesionId             - The id of the lesion.
function lesion.getGeneralZoneForLesion(lesionId)
  return lesion._getGeneralZoneForLesion(lesionId)
end


-- Returns the zone for the lesion, if one has been set.
--
-- lesionId             - The id of the lesion.
function lesion.getZoneForLesion(lesionId)
  return lesion._getZoneForLesion(lesionId)
end


-- Returns true if the lesion is a soft tissue type.
--
-- lesionId             - The id of the lesion.
function lesion.isLesionSoftTissue(lesionId)
  return lesion._isLesionSoftTissue(lesionId)
end


-- Assigns a zone to the lesion with the given Id
--
-- zoneId               - The id of the zone (in full form where applicable, 
--                        I.E. '4R', not just '4').
-- lesionId             - The id of the lesion.
-- sendMessage          - If true, this function will generate a lesion 
--                      - change event.
function lesion.assignZoneToLesion(zoneId, lesionId, sendMessage)
  if lesion.getZoneForLesion(lesionId) ~= zoneId then
    lesion._assignZoneToLesion(zoneId, lesionId)

    if sendMessage then
      lesion._callEvent(lesion._changedListeners, lesionId)
    end
  end
end


-- Assigns a zone to the specified lesions.
--
-- zoneId               - The id of the zone (in full form where applicable, 
--                        I.E. '4R', not just '4').
-- lesionIds            - An array of lesion ids.
-- sendMessage          - If true, this function will generate a lesion 
--                      - change event.
function lesion.assignZoneToLesionsIn(zoneId, lesionIds, sendMessage)
  local changed = {}
  for _, lesionId in ipairs(lesionIds) do
    if lesion._getZoneForLesion(lesionId) ~= zoneId then
      lesion._setZoneForLesion(zoneId, lesionId)
      if sendMessage then
        table.insert(changed, lesionId)
      end
    end
  end
  
  -- If we send all change messages late, this reduces the risk of unnecessary
  -- cache rebuilds.
  for _, lesionId in ipairs(changed) do
    lesion._callEvent(lesion._changedListeners, lesionId)   
  end
end


-- Removes the zone assignment (if any) from the specified lesions.
-- 
-- lesionIds            - An array of lesion ids.
-- sendMessage          - If true, this function will generate a lesion 
--                      - change event.
function lesion.removeZoneFromLesionsIn(lesionIds, sendMessage)
  for _, lesionId in ipairs(lesionIds) do
    lesion._removeZoneFromLesion(lesionId)
  end   

  -- If we send all change messages late, this reduces the risk of unnecessary
  -- cache rebuilds.
  if sendMessage then
    for _, lesionId in ipairs(lesionIds) do
      lesion._callEvent(lesion._changedListeners, lesionId)
    end 
  end
end


-- Removes specified lesions.
--
-- lesionIds            - An array of lesion ids.
-- sendMessage          - If true, this function will generate a list 
--                      - change event.
function lesion.deleteLesionsIn(lesionIds, sendMessage)
  for _, lesionId in ipairs(lesionIds) do
    lesion._deleteLesion(lesionId)
  end
  
  if sendMessage then
    lesion._callEvent(lesion._listChangedListeners)
  end
end


-- Removes the specified lesion
--
-- lesionIds            - The id of the lesion to delete
-- sendMessage          - If true, this function will generate a list 
--                      - change event.
function lesion.deleteLesion(lesionId, sendMessage)
  lesion._deleteLesion(lesionId)

  if sendMessage then
    lesion._callEvent(lesion._listChangedListeners)
  end
end


-- Create a new lesion from the specified geometry.
--
-- geometry         - A point, line, or polygon describing the location of the
--                  - lesion in pixel space. 
-- isSoftTissue     - If this value is true, the lesion will be considered to 
--                    be a soft tissue area lesion.
-- isScore3         - Set this to true if this lesion has greater than 50% 
--                  - involvement.
-- sendMessage      - If true, this function will generate a list 
--                  - change event.
function lesion.addNewLesion(geometry, isSoftTissue, isScore3, sendMessage)
  lesion._createNewLesion(geometry, isSoftTissue, isScore3)

  if sendMessage then
    lesion._callEvent(lesion._listChangedListeners)
  end
end


-- Specfies whether lesions should be shown with reduced opacity or not.
-- This may be useful to allow readers to make marks in areas of anatomy that
-- contain multiple lesions.
--
-- shouldBeDimmed   - Set this to true to dim lesions, or false to show them
--                    with normal opacity.  
function lesion.setLesionsDimmed(shouldBeDimmed)
  if lesion._showDimmed ~= shouldBeDimmed then
    lesion._showDimmed = shouldBeDimmed

    local lesionIds = lesion._getAllLesionIds()
    for _, lesionId in ipairs(lesionIds) do
      local zoneId = lesion._getZoneForLesion(lesionId)  
      local isScore3 = lesion._isLesionAScore3Type(lesionId)
      lesion._updateColorForLesion(lesionId, zoneId, isScore3, shouldBeDimmed)
    end
  end
end


-- ===========================================================================
-- Events

--  a listener function that will be called when the list of lesions 
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
-- Private functions

function lesion._getAllLesionIds()
  local regionIndexes = lesion._getLesionIdRegionIndexes()
  return table.getKeys(regionIndexes)
end


function lesion._getSelectedLesionIds()
  if lesion._selectedIds == nil then
    local t = {}
    local indexes = getIndexesOfSelectedRegions()
    for _, v in ipairs(indexes) do
      local r = getRegion(v)
      local lesionId = lesion._getLesionIdForRegion(r) 
      if lesionId ~= nil then
        t[lesionId] = true
      else
        t = {}
        break
      end
    end
  
    local result = {}
    for k in pairs(t) do
      table.insert(result, k)
    end
    
    lesion._selectedIds = result
  end
  
  return lesion._selectedIds
end


function lesion._getIdsOfLesionsWithZone(zoneId)
  local t = {}

  local ids = lesion._getAllLesionIds()
  for _, id in ipairs(ids) do
    if zoneId == lesion._getGeneralZoneForLesion(id) or
       zoneId == lesion._getZoneForLesion(id) then
      table.insert(t, id)
    end
  end

  return t
end


function lesion._getIdsOfUnassignedLesions()
  local t = {}

  local ids = lesion._getAllLesionIds()
  for _, id in ipairs(ids) do
    if not lesion._lesionHasAssignedZone(id) then
      table.insert(t, id)
    end
  end

  return t
end


function lesion._getZoneForLesion(lesionId)
  return lesion._getNamedZoneForLesion(lesionId, "zone")
end


function lesion._lesionHasAssignedZone(lesionId)
  local zone = lesion.getZoneForLesion(lesionId)
  return zone ~= nil and zone ~= "unassigned" 
end


function lesion._getGeneralZoneForLesion(lesionId)
  return lesion._getNamedZoneForLesion(lesionId, "generalzone")
end


function lesion._getNamedZoneForLesion(lesionId, zoneClass)
  local r = lesion._getOriginalLesion(lesionId)
  if r ~= nil then
    local zone = r:getValueForAttribute(zoneClass)
    if zone == nil then
      return "unassigned" 
    else
      return zone
    end
  end 
end


function lesion._setZoneForLesion(zone, lesionId)
  if not lesion._isLesionSoftTissue(lesionId) then
    lesion._setAttributeForLesionRegions(lesionId, "zone", zone)
    lesion._setAttributeForLesionRegions(lesionId, "generalzone", zone:match("^%d+"))

    -- Update the color for the original region
    local isScore3 = lesion._isLesionAScore3Type(lesionId)
    lesion._updateColorForLesion(lesionId, zone, isScore3)
  else
    mibg.logError("Attempt to overrwrite zone for soft tissue lesion " .. lesionId)
  end
end


function lesion._removeZoneFromLesion(lesionId)
  if not lesion._isLesionSoftTissue(lesionId) then
    lesion._setAttributeForLesionRegions(lesionId, "zone", "unassigned")
    lesion._setAttributeForLesionRegions(lesionId, "generalzone", "unassigned")
    
    -- Update the color for the original region
    local isScore3 = lesion._isLesionAScore3Type(lesionId)
    lesion._updateColorForLesion(lesionId, nil, isScore3, lesion._showDimmed)    
  else
    mibg.logError("Attempt to remove zone for soft tissue lesion " .. lesionId)
  end  
end

    
function lesion._isLesionSoftTissue(lesionId)
  return lesion._getZoneForLesion(lesionId, 'zone') == '10'
end


function lesion._isLesionAScore3Type(lesionId)
  local r = lesion._getOriginalLesion(lesionId)
  return r ~= nil and r:hasAttribute("score3")  
end


function lesion._setLesionScore3Type(lesionId, isScore3)
  if isScore3 then
    lesion._setAttributeForLesionRegions(lesionId, "score3")
  else
    lesion._removeAttributeForLesionRegions(lesionId, "score3")
  end

  -- Update the color for the original region
  local zoneId = lesion._getGeneralZoneForLesion(lesionId)
  lesion._updateColorForLesion(lesionId, zoneId, isScore3, lesion._showDimmed)
end


function lesion._getLesionType(lesionId)
  local r = lesion._getOriginalLesion(lesionId)
  local rtype = type(r)
  if rtype == "pointmark" then
    return "point"
  elseif rtype == "lineregion" then
    return "line"
  elseif rtype == "freehand" then
    return "ellipse"    
  end
end


function lesion._deleteLesion(lesionId)
  local regionIndexes = lesion._getRegionIndexesForLesion(lesionId)
  if regionIndexes ~= nil then
    removeRegions(regionIndexes)
  end    
end


function lesion._createNewLesion(geometry, isSoftTissue, isScore3)
  local geometry = lesion._getScaledGeometry(geometry)
  local orig = lesion._createLesionRegion(geometry, false)
  local peer = lesion._createLesionRegion(geometry, true)
  local zone

  orig:addAttribute("original")

  if isSoftTissue then
    lesion._updateColorForRegion(orig, "10", isScore3, lesion._showDimmed)
    zone = "10"
  else    
    zone = "unassigned"
    lesion._updateColorForRegion(orig, nil, isScore3, lesion._showDimmed)
  end
  lesion._updateColorForPeerRegion(peer, lesion._showDimmed)
  
  orig:addAttribute("zone", zone)
  peer:addAttribute("zone", zone)
  orig:addAttribute("generalzone", zone)
  peer:addAttribute("generalzone", zone)
  
  if isScore3 then
    orig:addAttribute("score3")
    peer:addAttribute("score3")
  end
    
  lesion._addRegionPairToProject(orig, peer)
end


function lesion._getScaledGeometry(geometry)
  local dp = getDisplayPanel()
  local geometryType = type(geometry)

  if geometryType == "point" then
    return dp:convertDisplayPixelToRegionCoordinate(geometry)
  elseif geometryType == "linesegment" then
    local a = dp:convertDisplayPixelToRegionCoordinate(geometry:a())
    local b = dp:convertDisplayPixelToRegionCoordinate(geometry:b())
    return linesegment.new(a, b)
  elseif geometryType == "polygon" then
    local scaled = polygon.new()
    for i = 1, geometry:numberOfFaces() do
      local p = geometry:vertex(i)
      scaled:addVertex(dp:convertDisplayPixelToRegionCoordinate(p))
    end
    return scaled
  end
end


function lesion._updateColorForLesion(lesionId, zoneId, isScore3, showDimmed)
  local regionIndexes = lesion._getRegionIndexesForLesion(lesionId)
  if regionIndexes ~= nil then
    -- Original
    local r = getRegion(regionIndexes[1])
    lesion._updateColorForRegion(r, zoneId, isScore3, showDimmed)
    setRegion(r, regionIndexes[1])
    
    -- Peer
    local r = getRegion(regionIndexes[2])
    lesion._updateColorForPeerRegion(r, showDimmed)
    setRegion(r, regionIndexes[2])
  end 
end


-- ===========================================================================
-- Low level private functions.  Do not call directly from public functions!

function lesion._updateColorForRegion(r, zoneId, isScore3, showDimmed)
  local c
  if zoneId == nil or zoneId == "unassigned" then
    c = colour.new(lesion._unassigned)
  elseif zoneId == "10" then
    if isScore3 then
      c = colour.new(lesion._score3SoftTissueColor)     
    else
      c = colour.new(lesion._softTissueColor)     
    end
  else
    if isScore3 then
      c = colour.new(lesion._score3LesionColor)     
    else
      c = colour.new(lesion._lesionColor)     
    end    
  end

  if showDimmed then
    c:setAlpha(c:alpha() * 0.5)
  end
  
  r:setOutlineColours(c, lesion._selectedColor)    
end
    

function lesion._updateColorForPeerRegion(r, showDimmed)
  local c = colour.new(lesion._peerColor)
  if showDimmed then
    c:setAlpha(c:alpha() * 0.5)
  end
  
  r:setOutlineColours(c, lesion._selectedColor)      
end


function lesion._getLesionIdRegionIndexes()
  -- If needed, create a new region index lookup
  if lesion._lesionIdRegionIndexes == nil then
    lesion._lesionIdRegionIndexes = lesion._createRegionIndexLookup()
  end
  
  return lesion._lesionIdRegionIndexes
end


function lesion._getLesionIdForRegion(r) 
  if r ~= nil then
    return r:getValueForAttribute("id")
  end  
end


function lesion._getRegionIndexesForLesion(lesionId)
  local regionIndexes = lesion._getLesionIdRegionIndexes()
  return regionIndexes[lesionId]
end


function lesion._getOriginalLesion(lesionId)
  local regionIndexes = lesion._getRegionIndexesForLesion(lesionId)
  if regionIndexes ~= nil then
    return getRegion(regionIndexes[1])
  end
end


function lesion._isRegionTheOriginal(r)
  return r:hasAttribute("original")
end
  

function lesion._isRegionThePeer(r)
  return not lesion._isRegionOriginal(r)
end


function lesion._setAttributeForLesionRegions(lesionId, attribute, value)
  local regionIndexes = lesion._getRegionIndexesForLesion(lesionId)
  if regionIndexes ~= nil then
    for _, index in ipairs(regionIndexes) do
      local r = getRegion(index)
      r:addAttribute(attribute, value)
      setRegion(r, index)
    end
  else
    mibg.logError("Attempt to set attribute " .. attribute .. " to "  .. value .. " for unknown lesion " .. lesionId)
  end 
end


function lesion._removeAttributeForLesionRegions(lesionId, attribute)
  local regionIndexes = lesion._getRegionIndexesForLesion(lesionId)
  if regionIndexes ~= nil then
    for _, index in ipairs(regionIndexes) do
      local r = getRegion(index)
      r:removeAttribute(attribute)
      setRegion(r, index)
    end
  else
    mibg.logError("Attempt to remove attribute " .. attribute .. " from unknown lesion " .. lesionId)
  end   
end


function lesion._createRegionIndexLookup()
  -- Build t[lesionId] = {regionIndex1, regionIndex2, ...}
  local t = {}
  for i = 1, getNumberOfRegions() do
    local r = getRegion(i)
    local lesionId = lesion._getLesionIdForRegion(r) 
    if lesionId ~= nil then
      local indexes = t[lesionId]
      
      if indexes == nil then
        indexes = {}
        t[lesionId] = indexes
      end
      
      table.insert(indexes, i)
    end      
  end
  
  -- sort table 't' such that region indexes are in order: original, peer, ..
  for _, indexes in pairs(t) do
    table.sort(indexes, function(rindex1, rindex2)
            local r1 = getRegion(rindex1)
            local r2 = getRegion(rindex2)
            if lesion._isRegionTheOriginal(r1) then
              return true
            elseif lesion._isRegionTheOriginal(r2) then
              return false
            elseif lesion._isRegionThePeer(r1) then
              return true
            elseif lesion._isRegionThePeer(r2) then
              return false
            else
              return false
            end
          end)
  end
  
  return t
end


function lesion._createLesionRegion(geometry, mirrorX)
  local r
  local geometryType = type(geometry)
  if geometryType == "point" then
    if mirrorX then
      r = pointmark.new(1 - geometry:x(), geometry:y())
    else
      r = pointmark.new(geometry)
    end
    r:setCrosshairSize(9)
  elseif geometryType == "linesegment" then
    if mirrorX then
      local l = linesegment.new(geometry)
      l:displaceBy(-1, 0)
      l:scaleBy(-1, 1)
      r = lineregion.new(l)
    else
      r = lineregion.new(geometry)
    end
    r:setThickness(1)
  elseif geometryType == "polygon" then
    if mirrorX then
      local p = polygon.new(geometry)
      p:displaceBy(-1, 0)
      p:scaleBy(-1, 1)
      r = freehand.new(p)
    else
      r = freehand.new(geometry)
    end
    r:setThickness(1)    
  end
  
  if r ~= nil then
    r:associateWith(getCurrentPrimaryFileName())  
  end
  
  return r      
end


function lesion._addRegionPairToProject(orig, peer)
  local lesionId = lesion._getNextFreeLesionId()
  orig:addAttribute("id", lesionId)
  peer:addAttribute("id", lesionId)
  
  local regionIndex = getNumberOfRegions() + 1
  setRegion(orig)
  setRegion(peer)

  -- add to cache
  local lesionIds = lesion._getLesionIdRegionIndexes()
  lesionIds[lesionId] = {regionIndex, regionIndex + 1}  
  
  -- Need to call this manually as Abras wrongly selects the new region, but
  -- doesn't send a selection change message.
  lesion._regionSelectionsChanged()
end


function lesion._getNextFreeLesionId()
  local nextLesionId = 1
  local lesionIds = lesion._getLesionIdRegionIndexes()
  for lesionId in pairs(lesionIds) do
    if nextLesionId <= tonumber(lesionId) then
      nextLesionId = lesionId + 1
    end
  end 
  return tostring(nextLesionId)
end


function lesion._updateLesionPeerLocation(r)
  function copyAndMirrorLocation(r1, r2)
    local rtype = type(r1)
    if rtype == "pointmark" then
      local p = r1:position()
      r2:setPosition(1 - p:x(), p:y()) 
    elseif rtype == "lineregion" then
      local l = r1:lineSegment()
      l:displaceBy(-1, 0)
      l:scaleBy(-1, 1)
      r2:setLineSegment(l)
    elseif rtype == "freehand" then
      local p = r1:getPolygon()
      p:displaceBy(-1, 0)
      p:scaleBy(-1, 1)
      r2:setPolygon(p)
    end
  end
  
  local lesionId = lesion._getLesionIdForRegion(r) 
  local indexes = lesion._getRegionIndexesForLesion(lesionId)
  local peerIndex
  
  if lesion._isRegionTheOriginal(r) then
    peerIndex = indexes[2] 
  else
    peerIndex = indexes[1]
  end  
  
  local peer = getRegion(peerIndex)
  copyAndMirrorLocation(r, peer)
  setRegion(peer, peerIndex)       
end


function lesion._callEvent(listeners, ...)
  lesion._blockEvents = true
  pcall(mibg.callListeners, listeners, ...)
  lesion._blockEvents = false
end


-- ===========================================================================
-- Private event handlers.
--
-- These are not compliant with a strict MVC pattern, but since our model is
-- abstracting an Abras construct, we deal with these here so that the effects
-- are invisible to the outside world.

function lesion._regionSelectionsChanged()
  -- Called when the user selects or deselects regions (see mibg library).
  -- If lesion selection states change, generate a corresponding lesion 
  -- selection changed event.
  local t = lesion._selectedIds
  lesion._selectedIds = nil

  if not lesion._blockEvents then
    local selectedIds = lesion._getSelectedLesionIds()
    if #selectedIds ~= #t then
      mibg.callListeners(lesion._selectionChangedListeners)
    else
      local intersect = mibg.intersect(t, selectedIds)
      if #intersect ~= t then
        mibg.callListeners(lesion._selectionChangedListeners)
      end
    end
  end
end


function lesion._regionChanged(index)
  -- Called when the user changes a region in some way (see mibg library).
  -- If change impacts a lesion, generate a corresponding lesion changed 
  -- event.
  local r = getRegion(index)
  local lesionId = lesion._getLesionIdForRegion(r) 
  if lesionId ~= nil and lesionId ~= "" then
    lesion._updateLesionPeerLocation(r)
    
    if not lesion._blockEvents then
      mibg.callListeners(lesion._changedListeners, index)
    end
  end
end


function lesion._regionListChanged()
  -- Called when the user changes the list of regions in some way (see mibg 
  -- library).  
  -- If changes impact lesions, generate a corresponding lesion list changed 
  -- event.  The only event of interest to use that should arrive here is the
  -- deletion of a single region by theuser.  We need to find and delete the 
  -- other peer.

  local deletionCandidates = {}
  
  -- Rebuild the index table
  lesion._lesionIdRegionIndexes = nil
  local lookup = lesion._getLesionIdRegionIndexes()
  
  -- hunt for half pairs.
  for lesionId, indexes in pairs(lookup) do
    if #indexes == 1 then
      table.insert(deletionCandidates,  indexes[1])  
    end  
  end
  
  -- The deletion list needs to be reverse sorted.
  table.sort(deletionCandidates, function(v1, v2) return V2 < v1; end)
  
  -- Delete the regions
  for _, index in ipairs(deletionCandidates) do
    removeRegion(index)
  end

  -- TODO: This doesn't catch the, admittedly, odd case where both original 
  -- and peer lesions are selected when delete is pressed.  We need to also 
  -- compare before and after lesion Ids.  This is probably a better approach 
  -- anyway.

  if #deletionCandidates > 0 then
    -- Wipe the cache again.
    lesion._lesionIdRegionIndexes = nil

     mibg.callListeners(lesion._listChangedListeners)
  end
end

