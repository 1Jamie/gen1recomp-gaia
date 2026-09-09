-- Build in-memory battle party from opaque session party + move_overlay.
-- Preserves Gen3 move ids (no host downgrade). Tracks overlay slots for PP writeback.

local PartyView = {}

local function shallow(mon)
  local copy = {}
  for k, v in pairs(mon) do
    if type(v) == "table" then
      local inner = {}
      for ik, iv in pairs(v) do inner[ik] = iv end
      copy[k] = inner
    else
      copy[k] = v
    end
  end
  return copy
end

--- Returns battleParty, remap[{partySlot,moveSlot,frlgMoveId}]
function PartyView.fromSession(sessionParty, moveOverlay)
  local battleParty = {}
  local remap = {}
  if type(sessionParty) ~= "table" then return battleParty, remap end
  for pi, mon in ipairs(sessionParty) do
    local copy = shallow(mon)
    copy.moves = {}
    copy.pp = {}
    local overlaySlot = moveOverlay and moveOverlay[pi]
    for mi = 1, 4 do
      local ov = overlaySlot and overlaySlot[mi]
      if ov and ov.frlgMoveId then
        copy.moves[mi] = ov.frlgMoveId
        copy.pp[mi] = ov.pp or (mon.pp and mon.pp[mi]) or 5
        remap[#remap + 1] = {
          partySlot = pi,
          moveSlot = mi,
          frlgMoveId = ov.frlgMoveId,
          hostFallbackId = ov.frlgMoveId, -- identity; writeback keeps Gen3 id
        }
      else
        copy.moves[mi] = mon.moves and mon.moves[mi]
        copy.pp[mi] = mon.pp and mon.pp[mi]
      end
    end
    battleParty[pi] = copy
  end
  return battleParty, remap
end

function PartyView.firstAliveIndex(party)
  if type(party) ~= "table" then return nil end
  for i, mon in ipairs(party) do
    if mon and (tonumber(mon.hp) or 0) > 0 then return i end
  end
  return nil
end

return PartyView
