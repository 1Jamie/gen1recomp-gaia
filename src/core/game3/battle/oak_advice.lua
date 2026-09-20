-- pokefirered/src/battle_controller_oak_old_man.c:626

local Oak = {}

-- pokefirered/include/battle_controllers.h:287
Oak.FLAG_INFLICT_DMG = 1
Oak.FLAG_STAT_CHG = 2
Oak.FLAG_HP_RESTORE = 4

-- pokefirered/src/battle_message.c:507
Oak.TEXT = {
  forPetesSake = {
    "OAK: Oh, for Pete's sake…\nSo pushy, as always.\f{PLAYER}.\fYou've never had a POKéMON battle\nbefore, have you?"
      .. "\fA POKéMON battle is when TRAINERS\npit their POKéMON against each\nother.",
    "The TRAINER that makes the other\nTRAINER's POKéMON faint by lowering\ntheir HP to “0,” wins.",
    "But rather than talking about it,\nyou'll learn more from experience.\fTry battling and see for yourself.",
  },
  inflictingDamage = "OAK: Inflicting damage on the foe\nis the key to any battle.",
  loweringStats = "OAK: Lowering the foe's stats\nwill put you at an advantage.",
  keepAnEyeOnHp = "OAK: Keep your eyes on your\nPOKéMON's HP.\fIt will faint if the HP drops to\n“0.”",
  noRunning = "OAK: No! There's no running away\nfrom a TRAINER POKéMON battle!",
  winEarnsPrize = "OAK: Hm! Excellent!\fIf you win, you earn prize money,\nand your POKéMON will grow!"
    .. "\fBattle other TRAINERS and make\nyour POKéMON strong!",
  howDisappointing = "OAK: Hm…\nHow disappointing…\fIf you win, you earn prize money,\nand your POKéMON grow."
    .. "\fBut if you lose, {PLAYER}, you end\nup paying prize money…"
    .. "\fHowever, since you had no warning\nthis time, I'll pay for you."
    .. "\fBut things won't be this way once\nyou step outside these doors."
    .. "\fThat's why you must strengthen your\nPOKéMON by battling wild POKéMON.",
}

-- pokefirered/src/battle_setup.c:899
function Oak.active(st)
  return (st and st.firstBattle) and true or false
end

-- pokefirered/src/battle_controller_oak_old_man.c:2228
function Oak.testFlag(st, mask)
  if not st or not mask or mask <= 0 then return false end
  return math.floor((tonumber(st.oakMsgFlags) or 0) / mask) % 2 == 1
end

function Oak.setFlag(st, mask)
  if not st or not mask or mask <= 0 then return end
  if Oak.testFlag(st, mask) then return end
  st.oakMsgFlags = (tonumber(st.oakMsgFlags) or 0) + mask
end

function Oak.pending(st, mask)
  return Oak.active(st) and not Oak.testFlag(st, mask)
end

function Oak.expand(st, s)
  local name = (st and st.playerName) or "PLAYER"
  s = tostring(s or ""):gsub("{B_PLAYER_NAME}", name)
  return (s:gsub("{PLAYER}", name))
end

function Oak.pages(st, key)
  local raw = Oak.TEXT[key]
  if raw == nil then return nil end
  if type(raw) == "string" then raw = { raw } end
  local out = {}
  for i = 1, #raw do out[i] = Oak.expand(st, raw[i]) end
  return out
end

function Oak.say(st, key, sayFn)
  if not Oak.active(st) then return false end
  local pages = Oak.pages(st, key)
  if not pages or #pages == 0 then return false end
  if not sayFn then
    local Ui = require("src.core.game3.battle.ui")
    sayFn = function(t) Ui.push(t) end
  end
  for _, p in ipairs(pages) do sayFn(p) end
  return true
end

function Oak.sayOnce(st, mask, key, sayFn)
  if not Oak.pending(st, mask) then return false end
  Oak.setFlag(st, mask)
  return Oak.say(st, key, sayFn)
end

return Oak
