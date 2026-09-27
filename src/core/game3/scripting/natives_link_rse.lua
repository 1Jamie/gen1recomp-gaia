local Link = require("src.core.game3.link.init")
local Union = require("src.core.game3.link.union_room")
local LinkBattle = require("src.core.game3.link.battle")
local LinkTrade = require("src.core.game3.link.trade")
local RecordMix = require("src.core.game3.link.record_mix")
local Family = require("src.core.game3.link.family")

local NativesLinkRse = {}

NativesLinkRse.Link = Link
NativesLinkRse.Union = Union
NativesLinkRse.RecordMix = RecordMix

local function varResult(ctx)
  return require("src.core.game3.scripting.flags").getVar(nil, ctx, Link.VAR_RESULT)
end

NativesLinkRse.BY_NAME = {
  -- pokeemerald/src/field_control_avatar.c:995
  SetCableClubWarp = function(ctx)
    Link.setCableClubWarp(ctx)
    return false
  end,
  -- pokeemerald/src/field_screen_effect.c:601
  DoCableClubWarp = function(ctx, adapters)
    return Link.doCableClubWarp(ctx, adapters)
  end,
  -- pokeemerald/src/field_screen_effect.c:641
  ReturnFromLinkRoom = function(ctx, adapters)
    Link.returnFromLinkRoom(ctx, adapters)
    return false
  end,
  -- pokeemerald/src/cable_club.c:1023
  CleanupLinkRoomState = function(ctx, adapters)
    Link.cleanupLinkRoomState(ctx, adapters)
    return false
  end,
  -- pokeemerald/src/cable_club.c:1036
  ExitLinkRoom = function(ctx, adapters)
    Link.exitLinkRoom(ctx, adapters)
    return false
  end,
  -- pokeemerald/src/cable_club.c:571
  TryBattleLinkup = function(ctx, adapters)
    return LinkBattle.tryBattleLinkup(ctx, adapters)
  end,
  -- pokeemerald/src/cable_club.c:610
  TryTradeLinkup = function(ctx, adapters)
    return LinkTrade.tryTradeLinkup(ctx, adapters)
  end,
  -- pokeemerald/src/cable_club.c:617
  TryRecordMixLinkup = function(ctx, adapters)
    return LinkBattle.tryRecordMixLinkup(ctx, adapters)
  end,
  -- pokeemerald/src/cable_club.c:625
  ValidateMixingGameLanguage = function(ctx)
    RecordMix.validateMixingGameLanguage(ctx, varResult(ctx))
    return false
  end,
  -- pokeemerald/src/record_mixing.c:166
  RecordMixingPlayerSpotTriggered = function(ctx, adapters)
    return RecordMix.playerSpotTriggered(ctx, adapters)
  end,
  -- pokeemerald/src/cable_club.c:1180
  ColosseumPlayerSpotTriggered = function(ctx, adapters)
    return LinkBattle.enterColosseumPlayerSpot(ctx, adapters)
  end,
  -- pokeemerald/src/cable_club.c:1160
  PlayerEnteredTradeSeat = function(ctx, adapters)
    return LinkTrade.enterTradeSeat(ctx, adapters)
  end,
  -- pokeemerald/src/script_pokemon_util.c:99
  HasEnoughMonsForDoubleBattle = function(ctx)
    return LinkBattle.hasEnoughMonsForDoubleBattle(ctx)
  end,
  -- pokeemerald/src/link.c:400
  CloseLink = function()
    Link.closeLink("close_link")
    return false
  end,
  -- pokeemerald/src/load_save.c:208
  LoadPlayerBag = function()
    Link.loadPlayerBag()
    return false
  end,
  -- pokeemerald/src/link.c:237
  IsWirelessAdapterConnected = function(ctx, adapters)
    return Link.isWirelessAdapterConnected(ctx, adapters)
  end,
  -- pokeemerald/src/union_room.c:375
  TryBecomeLinkLeader = function(ctx, adapters)
    return Union.tryBecomeLinkLeader(ctx, adapters)
  end,
  -- pokeemerald/src/union_room.c:970
  TryJoinLinkGroup = function(ctx, adapters)
    return Union.tryJoinLinkGroup(ctx, adapters)
  end,
  -- pokeemerald/src/union_room.c:2421
  RunUnionRoom = function(ctx, adapters)
    Union.run(ctx, adapters)
    return false, 0
  end,
  -- pokeemerald/src/wireless_communication_status_screen.c:193
  ShowWirelessCommunicationScreen = function(ctx, adapters)
    return Link.showWirelessCommunicationScreen(ctx, adapters)
  end,
  -- pokeemerald/src/union_room.c:3294
  InitUnionRoom = function(ctx)
    Union.init(ctx)
    return false, 0
  end,
  -- pokeemerald/src/union_room.c:3379
  BufferUnionRoomPlayerName = function(ctx, adapters)
    return Union.bufferPlayerName(ctx, adapters)
  end,
  -- pokeemerald/src/union_room.c:4344
  Script_ResetUnionRoomTrade = function()
    Union.resetTrade()
    return false, 0
  end,
  -- pokeemerald/src/cable_club.c:1196
  Script_ShowLinkTrainerCard = function(ctx, adapters)
    return Link.showLinkTrainerCard(ctx, adapters)
  end,
  -- pokeemerald/src/event_object_lock.c:119
  Script_FacePlayer = function(ctx, adapters)
    if adapters and adapters.facePlayer then
      local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
      if okF then adapters.facePlayer(Flags.getVar(nil, ctx, Family.var(nil, "VAR_FACING"))) end
    end
    return false
  end,
  -- pokeemerald/src/event_object_lock.c:124
  Script_ClearHeldMovement = function()
    return false
  end,
  -- pokeemerald/src/mystery_gift.c:156
  ValidateSavedWonderCard = function()
    local sess = Link.session()
    if require("src.core.game3.rse.init").call("eventIslands", "pendingGift", nil, nil, sess) ~= nil then
      return false, 1
    end
    return false, require("src.core.game3.mystery_gift").validateSavedCard(sess) and 1 or 0
  end,
}

-- pokeemerald/include/constants/script_menu.h:92
NativesLinkRse.MULTI_LINK_LEADER = 81

local okM, Multi = pcall(require, "src.core.game3.scripting.multichoice")
if okM and type(Multi) == "table" then
  Multi.OVERRIDES = Multi.OVERRIDES or {}
  local prev = Multi.OVERRIDES[NativesLinkRse.MULTI_LINK_LEADER]
  Multi.OVERRIDES[NativesLinkRse.MULTI_LINK_LEADER] = function(ctx, row, done)
    if Family.of() ~= "rse" then
      if type(prev) == "function" then return prev(ctx, row, done) end
      return false
    end
    return Union.directModes(ctx, row, done)
  end
end

return NativesLinkRse
