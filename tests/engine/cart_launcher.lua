-- Custom carts in the launcher.
--   luajit tests/engine/cart_launcher.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end
love.graphics.polygon = love.graphics.polygon or function() end

local Kit = require("src.ui.kit.Kit")
local SaveData = require("src.core.SaveData")
local CartManifest = require("src.carts.CartManifest")
local CartStore = require("src.carts.CartStore")
local RomImporter = require("src.import.RomImporter")
local LauncherView = require("src.import.LauncherView")

local SHA = ("a1b2c3d4"):rep(8)

local function window(w, h)
  love.graphics.getDimensions = function() return w, h end
  love.graphics.getPixelDimensions = function() return w, h end
end

local function freshLauncher(onComplete)
  return RomImporter.new(onComplete or function() end, { launcher = true })
end

local realPrint = love.graphics.print
local function drawAndCapture(imp)
  local seen = {}
  love.graphics.print = function(str, ...)
    seen[#seen + 1] = tostring(str)
    return realPrint(str, ...)
  end
  local ok, err = pcall(LauncherView.draw, imp)
  love.graphics.print = realPrint
  check(ok, "the frame draws: " .. tostring(err))
  return table.concat(seen, "\n")
end

local realSetColor = love.graphics.setColor
local function drawColors(imp)
  local seen = {}
  love.graphics.setColor = function(r, g, b, a)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
      seen[("%d,%d,%d"):format(math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))] = true
    end
    return realSetColor(r, g, b, a)
  end
  local ok, err = pcall(LauncherView.draw, imp)
  love.graphics.setColor = realSetColor
  check(ok, "the frame draws: " .. tostring(err))
  return seen
end

local function cartTable(over)
  local tbl = {
    id = "kanto_plus", title = "Kanto Plus", version = "1.2.0",
    author = "Ren", shell = "#3fa9f5", base = "red", seal = "sealed",
    mods = { { id = "rare_soda", source = "github", repo = "ren/rare-soda",
               version = "0.4.1", sha256 = SHA } },
  }
  for key, value in pairs(over or {}) do tbl[key] = value end
  return tbl
end

local function install(over)
  over = over or {}
  local cart, parseErr = CartManifest.parse(cartTable(over))
  check(cart ~= nil, "fixture parses: " .. tostring(parseErr))
  cart.labelArt = over.labelArt
  local ok, err = CartStore.install(CartManifest.encode(cart))
  check(ok ~= nil, "fixture installs: " .. tostring(err))
  return cart
end

install()
install({ id = "zeta_open", title = "Zeta Open", version = "0.9.0",
          seal = "open", shell = "#112233" })
install({ id = "johto_lite", title = "Johto Lite", base = "blue",
          shell = "#7a5c2e" })

window(1280, 720)

local imp = freshLauncher()
local red = imp:_ensureCarts("red")
eq(#red, 2, "red lists exactly the carts based on red")
eq(red[1].id, "kanto_plus", "the list is sorted by title")
eq(red[2].id, "zeta_open", "the list is sorted by title")
eq(#imp:_ensureCarts("blue"), 1, "blue lists only its own cart")
eq(imp:_ensureCarts("blue")[1].id, "johto_lite", "and that one is Johto Lite")
eq(#imp:_ensureCarts("yellow"), 0, "a game with no carts lists none")

imp.tab = "red"
imp.ready.red = true
imp._cartPopup = "red"
local picker = drawAndCapture(imp)
check(picker:find("Pokemon Red", 1, true) ~= nil,
  "the picker offers the base game as the first row")
check(picker:find("Kanto Plus", 1, true) ~= nil, "the picker lists Kanto Plus")
check(picker:find("Zeta Open", 1, true) ~= nil, "the picker lists Zeta Open")
check(picker:find("Johto Lite", 1, true) == nil,
  "the picker does NOT list a cart based on another game")
check(picker:find("v1.2.0", 1, true) ~= nil, "a cart row carries its version")
check(picker:find("sealed", 1, true) ~= nil, "a cart row carries its seal state")
check(picker:find("open", 1, true) ~= nil, "including an open one")
check(picker:find("Get more carts", 1, true) ~= nil,
  "the last row is the browse placeholder")

imp._cartPopup = nil
local vanillaColors = drawColors(imp)
check(vanillaColors["63,169,245"] == nil,
  "a vanilla page never paints the cart's shell colour")

imp:_selectCart("red", "kanto_plus")
eq(imp.activeCart.red, "kanto_plus", "the pick lands on activeCart")
eq(imp._cartPopup, nil, "picking closes the picker")

local titled = drawAndCapture(imp)
check(titled:find("Kanto Plus", 1, true) ~= nil,
  "the panel title becomes the cart's title")

local cartColors = drawColors(imp)
eq(cartColors["63,169,245"], true,
  "the cartridge takes the cart's shell colour")

eq(imp.tab, "red", "a cart id never reaches imp.tab")
eq(imp.panelVersion, "red", "a cart id never reaches imp.panelVersion")

check(imp._cartridge["cart:kanto_plus"] ~= nil,
  "the cart spins on its own cartridge state")
check(imp._cartridge["cart:kanto_plus"] ~= imp._cartridge.red,
  "which is not the base game's")
eq(imp._cartridgeLabels["cart:kanto_plus"], false,
  "a cart carrying no label art falls through to bare plastic")

local scope = imp:slotScope("red")
eq(scope, "cart_kanto_plus", "an active cart scopes the panel's save slots")
imp:_newSlot(scope)
imp:_newSlot(scope)
eq(#SaveData.listCartSlots("kanto_plus"), 2, "both slots land in the cart")
eq(#SaveData.listSlots("red"), 0, "and none of them in the base game")
imp:_ensureSlots(scope)
eq(#imp.slots[scope], 2, "the panel reads the cart's slots back")

imp:_beginRename(scope, "slot1")
imp._rename.text = "Nuzlocke"
imp:_commitRename()
eq(SaveData.listCartSlots("kanto_plus")[1].label, "Nuzlocke",
  "a rename writes into the cart's registry")

imp:_selectSlot(scope, "slot2")
eq(SaveData.activeCartSlot("kanto_plus"), "slot2",
  "selecting a row moves the cart's active slot")
imp:_deleteSlot(scope, "slot2")
eq(#SaveData.listCartSlots("kanto_plus"), 1, "a delete removes the cart's slot")

local withCart = drawAndCapture(imp)
check(withCart:find("Nuzlocke", 1, true) ~= nil,
  "the slot card shows the cart's slots while the cart is active")

imp:_selectCart("red", nil)
eq(imp.activeCart.red, nil, "choosing the base game clears the active cart")
eq(imp:slotScope("red"), "red", "and the slots go back to the version's own")
imp:_newSlot("red")
eq(#SaveData.listSlots("red"), 1, "a vanilla slot lands in the version")
eq(#SaveData.listCartSlots("kanto_plus"), 1, "and not in the cart")

local backHome = drawAndCapture(imp)
check(backHome:find("Nuzlocke", 1, true) == nil,
  "the slot card no longer shows the cart's slots")
check(backHome:find("Kanto Plus", 1, true) == nil,
  "and the panel title is the base game's again")
local homeColors = drawColors(imp)
check(homeColors["63,169,245"] == nil,
  "the cartridge is back to the base game's shell")

local handed = {}
local player = freshLauncher(function(version, cartId)
  handed.version, handed.cart = version, cartId
end)
player.ready.red = true
player:_selectCart("red", "kanto_plus")
player:play("red")
eq(handed.version, "red", "Play still boots the base game")
eq(handed.cart, "kanto_plus", "and names the cart it is running")

local opts = SaveData.loadOptions()
eq(opts.lastVersion, "red", "play still remembers the version")
eq(type(opts.activeCart) == "table" and opts.activeCart.red or nil, "kanto_plus",
  "play persists the active cart beside it")

local restored = freshLauncher()
eq(restored.activeCart.red, "kanto_plus",
  "a fresh launcher restores the cart its page was on")
eq(restored.tab, "red", "and a cart id still never reaches the tab")

local uninstalled = freshLauncher()
uninstalled.activeCart.red = nil
uninstalled:_restoreActiveCarts({ activeCart = { red = "gone_forever" } })
eq(uninstalled.activeCart.red, nil,
  "a remembered cart that is no longer installed is dropped")

local Base64 = require("src.core.Base64")
local PNG = CartManifest.PNG_SIGNATURE .. ("labelart"):rep(4)
local function artOf()
  return { encoding = "base64", bytes = #PNG, data = Base64.encode(PNG) }
end

install({ id = "art_cart", title = "Art Cart", base = "yellow",
          shell = "#204060", labelArt = artOf() })
install({ id = "bare_cart", title = "Bare Cart", base = "yellow",
          shell = "#405060" })
install({ id = "bad_cart", title = "Bad Cart", base = "yellow",
          shell = "#605040", labelArt = artOf() })

check(CartStore.labelArt("art_cart") == PNG,
  "the store hands back the cart's own PNG bytes")
check(CartStore.labelArt("bare_cart") == nil,
  "and nothing for a cart that carries none")

window(1280, 720)
local realNewImage = love.graphics.newImage
local madeImages = 0
love.graphics.newImage = function(...)
  madeImages = madeImages + 1
  return realNewImage(...)
end

local art = freshLauncher()
art.tab = "yellow"
art.ready.yellow = true
art:_selectCart("yellow", "art_cart")
drawAndCapture(art)
local artLabel = art._cartridgeLabels["cart:art_cart"]
check(type(artLabel) == "table" and artLabel.image ~= nil,
  "a cart's own label art becomes a cached cartridge image")
local afterFirst = madeImages
drawAndCapture(art)
eq(madeImages, afterFirst, "the decode happens once, not every frame")

art:_selectCart("yellow", "bare_cart")
drawAndCapture(art)
eq(art._cartridgeLabels["cart:bare_cart"], false,
  "a cart with no art renders as bare plastic")
check(art._cartridgeLabels["cart:art_cart"] ~= art._cartridgeLabels["cart:bare_cart"],
  "and the two carts never share one label cache entry")

love.graphics.newImage = function(a, ...)
  if type(a) == "table" and a._fileData then error("not a PNG this engine reads") end
  return realNewImage(a, ...)
end
local bad = freshLauncher()
bad.tab = "yellow"
bad.ready.yellow = true
bad:_selectCart("yellow", "bad_cart")
drawAndCapture(bad)
love.graphics.newImage = realNewImage
eq(bad._cartridgeLabels["cart:bad_cart"], false,
  "art that will not decode leaves the cart bare instead of throwing")
drawAndCapture(bad)
eq(bad._cartridgeLabels["cart:bad_cart"], false,
  "and it is not retried on the next frame")

local LauncherMods = require("src.mods.LauncherMods")
local realModList = LauncherMods.list

local function fakeRow(over)
  local row = { id = "x", name = "X", version = "1.0.0", badge = "MOD",
                description = "", enabled = true, status = "ok",
                statusDetail = "", experimental = false, targetsHere = true,
                targets = nil, safeMode = false, requiredImports = {},
                imports = {}, missingRequiredImports = 0,
                missingOptionalImports = 0,
                enabledByVersion = { red = true, blue = true, yellow = true,
                                     gold = true, silver = true } }
  for key, value in pairs(over) do row[key] = value end
  row.manifest = row.manifest or { id = row.id, name = row.name,
                                   version = row.version }
  return row
end

local FAKE_MODS = {
  fakeRow({ id = "rare_soda", name = "Rare Soda", version = "0.4.1",
            github = "ren/rare-soda", sha256 = SHA }),
  fakeRow({ id = "wide_gym", name = "Wide Gym", version = "dev" }),
  fakeRow({ id = "off_mod", name = "Off Mod", enabled = false,
            enabledByVersion = { red = false } }),
}

local modsView = freshLauncher()
modsView.tab = "mods"
local modsText = drawAndCapture(modsView)
check(modsText:find("Save as cart", 1, true) ~= nil,
  "the mods tab carries the Save as cart control")

LauncherMods.list = function() return FAKE_MODS end

local maker = freshLauncher()
maker.tab = "red"
maker.ready.red = true
maker:_setModScope("red")
eq(maker:_cartCaptureCount("red"), 2,
  "the control counts only the mods enabled for this game")

maker:_beginCartSave("red")
check(maker._cartSave ~= nil, "Save as cart opens a form")
eq(maker._cartSave.count, 2, "the form reports the captured mod count")
eq(maker._cartSave.version, "red", "scoped to the game the panel is showing")
eq(#maker._cartSave.unresolved, 1, "capture reports one pin it could not resolve")
eq(maker._cartSave.unresolved[1].id, "wide_gym", "naming the mod it belongs to")
check(tostring(maker._cartSave.unresolved[1].reason):find("semantic", 1, true) ~= nil,
  "and why it could only be pinned locally")
eq(maker._cartSave.publishable, false, "a local pin makes the cart unpublishable")

local form = drawAndCapture(maker)
check(form:find("Save as cart", 1, true) ~= nil, "the form is titled")
check(form:find("Wide Gym", 1, true) ~= nil,
  "the unresolved pin is named BEFORE the player confirms")
check(form:find("could only be pinned to this install", 1, true) ~= nil,
  "under a heading that says what a local pin means")
check(form:find("cannot be shared", 1, true) ~= nil,
  "and the form says plainly that the result cannot be shared")

maker._cartSave.text = "Kanto Plus"
maker:_commitCartSave()
check(maker._cartSave ~= nil, "a title that collides with an installed cart refuses")
check(tostring(maker._cartSave.error):find("kanto_plus", 1, true) ~= nil,
  "and names the id that is already taken")
eq(CartStore.get("kanto_plus").title, "Kanto Plus",
  "the installed cart is untouched")

maker._cartSave.text = "Soda Run"
maker:_commitCartSave()
eq(maker._cartSave, nil, "a free title saves the cart and closes the form")
eq(maker._cartPopup, "red", "and drops the player straight into the picker")
local made = CartStore.get("soda_run")
check(made ~= nil, "the cart is installed under the id derived from the title")
eq(made.base, "red", "based on the game the panel was showing")
eq(made.version, "1.0.0", "at the default cart version")
eq(made.seal, "sealed", "sealed by default")
eq(made.shell, "#ff3c48", "wearing the base game's rail colour")
eq(#made.mods, 2, "pinning exactly the enabled mods")

local listedNow = false
for _, row in ipairs(maker:_ensureCarts("red")) do
  if row.id == "soda_run" then listedNow = true end
end
check(listedNow, "and the picker lists it immediately")
local picked = drawAndCapture(maker)
check(picked:find("Soda Run", 1, true) ~= nil, "including on screen")

LauncherMods.list = function() return { FAKE_MODS[1] } end
local pure = freshLauncher()
pure.tab = "red"
pure.ready.red = true
pure:_beginCartSave("red")
eq(#pure._cartSave.unresolved, 0, "a fully pinned capture has no local pins")
eq(pure._cartSave.publishable, true, "and it is publishable")
local pureForm = drawAndCapture(pure)
check(pureForm:find("can be shared", 1, true) ~= nil,
  "which the form says before the player confirms")
check(pureForm:find("cannot be shared", 1, true) == nil,
  "instead of the local-pin warning")
pure._cartSave.text = "Pure Soda"
pure:_commitCartSave()
eq(pure._cartSave, nil, "a fully pinned capture saves too")
local pureOk, pureWhy = CartManifest.publishable(CartStore.get("pure_soda"))
eq(pureOk, true, "and the saved cart really is publishable")
eq(pureWhy, nil, "with nothing holding it back")
LauncherMods.list = function() return FAKE_MODS end

local blank = freshLauncher()
blank:_beginCartSave("red")
blank:_commitCartSave()
check(blank._cartSave ~= nil, "an empty title does not save")
check(tostring(blank._cartSave.error):find("title", 1, true) ~= nil,
  "and asks for one")
blank:_cancelCartSave()
eq(blank._cartSave, nil, "Cancel closes the form")

LauncherMods.list = realModList

local exporter = freshLauncher()
exporter:exportCart("kanto_plus")
check(tostring(exporter._cartNotice):find("Exported", 1, true) ~= nil,
  "Export reports where the cart file went: " .. tostring(exporter._cartNotice))
local wroteBytes = love.filesystem.read("exports/carts/kanto_plus" .. CartStore.EXT)
check(type(wroteBytes) == "string" and wroteBytes ~= "",
  "and the bytes land in the same exports tree a save export uses")
eq(wroteBytes, (CartStore.export("kanto_plus")),
  "byte for byte what CartStore.export returned")
local roundTrip = CartManifest.decode(wroteBytes)
check(roundTrip ~= nil and roundTrip.id == "kanto_plus",
  "and the file decodes back into the cart")

exporter:exportCart("no_such_cart")
check(tostring(exporter._cartNotice):find("not installed", 1, true) ~= nil,
  "exporting a cart that is not installed says so")

window(1920, 1080)

local FULL_MODS = { fakeRow({ id = "rare_soda", name = "Rare Soda",
                              version = "0.4.1", github = "ren/rare-soda",
                              sha256 = SHA }) }

LauncherMods.list = function() return FULL_MODS end
local okCart = freshLauncher()
okCart.tab = "red"
okCart.ready.red = true
okCart:_selectCart("red", "kanto_plus")
local okPlan = okCart:cartPlan("red")
eq(okPlan.refused, false, "a cart whose pin is installed is playable")
eq(okPlan.sealed, true, "and is still sealed")
local okText = drawAndCapture(okCart)
check(okText:find("Sealed", 1, true) ~= nil,
  "the verdict is on the page before the player commits")
check(okText:find("Break the seal", 1, true) ~= nil,
  "and a sealed cart's page offers the escape hatch")

LauncherMods.list = function() return {} end
local gapCart = freshLauncher()
gapCart.tab = "red"
gapCart.ready.red = true
gapCart:_selectCart("red", "kanto_plus")
local gapPlan = gapCart:cartPlan("red")
eq(gapPlan.refused, true, "a cart with an uninstalled pin refuses")
eq(gapPlan.missing[1].id, "rare_soda", "naming the pin it cannot find")
local gapText = drawAndCapture(gapCart)
check(gapText:find("will not start", 1, true) ~= nil,
  "which the page says without the player booting into an error")
check(gapText:find("rare_soda", 1, true) ~= nil, "and names the pin")
check(gapText:find("Break the seal", 1, true) ~= nil,
  "with the escape hatch beside the refusal")

local sealScope = gapCart:slotScope("red")
gapCart:_ensureSlots(sealScope)
local sealSlot = gapCart.activeSlot[sealScope]
check(type(sealSlot) == "string", "the cart page has a loaded save slot")
eq(gapCart:pressBreakSeal("red"), false, "the first press only arms the confirm")
eq(SaveData.slotSealBroken("kanto_plus", sealSlot), false,
  "so one press breaks nothing")
local armedText = drawAndCapture(gapCart)
check(armedText:find("Kanto Plus", 1, true) ~= nil,
  "the armed confirm names the cart")
check(armedText:find("save slot", 1, true) ~= nil, "and the save slot")
check(armedText:find("cannot be undone", 1, true) ~= nil,
  "says it is permanent")
check(armedText:find("marked modified", 1, true) ~= nil,
  "says the file is marked modified from then on")
check(armedText:find("pinned mods first", 1, true) ~= nil,
  "and that the cart's own list still loads first")
eq(gapCart:pressBreakSeal("red"), true, "a second press breaks the seal")
eq(SaveData.slotSealBroken("kanto_plus", sealSlot), true,
  "which lands on that slot, durably")
eq(gapCart:cartPlan("red").refused, false, "and the cart is no longer refused")
local brokenText = drawAndCapture(gapCart)
check(brokenText:find("Seal broken", 1, true) ~= nil,
  "the cart page shows the broken state afterwards")
check(brokenText:find("seal broken", 1, true) ~= nil,
  "and so does the cart's slot row")

gapCart:_newSlot(sealScope)
local freshSlot = gapCart.activeSlot[sealScope]
check(freshSlot ~= sealSlot, "a new save slot under the same cart")
eq(SaveData.slotSealBroken("kanto_plus", freshSlot), false,
  "starts sealed again")
eq(gapCart:cartPlan("red").refused, true, "so the cart refuses that one")

LauncherMods.list = realModList
window(1280, 720)

local function clipped(r)
  local x1, y1, x2, y2 = r.x, r.y, r.x + r.w, r.y + r.h
  if r.clip then
    x1 = math.max(x1, r.clip.x); y1 = math.max(y1, r.clip.y)
    x2 = math.min(x2, r.clip.x + r.clip.w); y2 = math.min(y2, r.clip.y + r.clip.h)
  end
  if x2 - x1 <= 1 or y2 - y1 <= 1 then return nil end
  return x1, y1, x2, y2
end

local function overlap(a, b)
  local ax1, ay1, ax2, ay2 = clipped(a)
  if not ax1 then return false end
  local bx1, by1, bx2, by2 = clipped(b)
  if not bx1 then return false end
  return math.min(ax2, bx2) - math.max(ax1, bx1) > 1
     and math.min(ay2, by2) - math.max(ay1, by1) > 1
end

local function auditFrame(label, want)
  local controls, found = {}, false
  for _, r in ipairs(Kit.audit or {}) do
    if r.class == "control" then
      controls[#controls + 1] = r
      if want and tostring(r.label):find(want, 1, true) then found = true end
    end
  end
  check(#controls > 0, label .. ": the frame dispatched controls at all")
  local collisions = 0
  for i = 1, #controls do
    for j = i + 1, #controls do
      if overlap(controls[i], controls[j]) then
        collisions = collisions + 1
        print(("  overlap: '%s' vs '%s' at (%.0f,%.0f) / (%.0f,%.0f)")
          :format(tostring(controls[i].label), tostring(controls[j].label),
            controls[i].x, controls[i].y, controls[j].x, controls[j].y))
      end
    end
  end
  check(collisions == 0, label .. ": no two controls overlap")
  if want then check(found, label .. ": drew " .. want) end
end

local SIZES = {
  { 360, 780 }, { 412, 915 }, { 480, 900 }, { 720, 1280 },
  { 1280, 720 }, { 1024, 768 }, { 900, 700 }, { 1920, 1080 },
}

for _, size in ipairs(SIZES) do
  local W, H = size[1], size[2]
  window(W, H)
  for _, cart in ipairs({ false, true }) do
    local page = freshLauncher()
    page.tab = "red"
    page.ready.red = true
    page:_selectCart("red", cart and "kanto_plus" or nil)
    LauncherView.draw(page)
    Kit.audit = {}
    local ok, err = pcall(LauncherView.draw, page)
    Kit.audit = ok and Kit.audit or nil
    check(ok, ("%dx%d %s draws: %s")
      :format(W, H, cart and "cart" or "vanilla", tostring(err)))
    if ok then
      auditFrame(("%dx%d %s"):format(W, H, cart and "cart" or "vanilla"),
        "Custom Carts")
    end
    Kit.audit = nil

    page._cartPopup = "red"
    if cart then
      page._cartNotice = "Browsing for carts arrives in a later update."
    end
    LauncherView.draw(page)
    Kit.audit = {}
    ok, err = pcall(LauncherView.draw, page)
    Kit.audit = ok and Kit.audit or nil
    check(ok, ("%dx%d picker draws: %s"):format(W, H, tostring(err)))
    if ok then
      auditFrame(("%dx%d picker"):format(W, H), "Kanto Plus")
      for _, r in ipairs(Kit.audit or {}) do
        local label = tostring(r.label)
        if label == "Get more carts" or label == "Close" then
          check(r.y >= -0.5 and r.y + r.h <= H + 0.5,
            ("%dx%d picker: %q stays inside the window"):format(W, H, label))
        end
      end
    end
    Kit.audit = nil
  end
end

LauncherMods.list = function() return FAKE_MODS end
for _, size in ipairs(SIZES) do
  local W, H = size[1], size[2]
  window(W, H)
  local form = freshLauncher()
  form.tab = "mods"
  form.ready.red = true
  form:_setModScope("red")
  form:_beginCartSave("red")
  form._cartSave.text = "Soda Run"
  form:_commitCartSave()
  check(form._cartSave ~= nil,
    ("%dx%d save form stays open on a colliding title"):format(W, H))
  LauncherView.draw(form)
  Kit.audit = {}
  local ok, err = pcall(LauncherView.draw, form)
  Kit.audit = ok and Kit.audit or nil
  check(ok, ("%dx%d save form draws: %s"):format(W, H, tostring(err)))
  if ok then
    auditFrame(("%dx%d save form"):format(W, H), "Save as cart")
    for _, r in ipairs(Kit.audit or {}) do
      if tostring(r.label) == "Cancel" then
        check(r.y >= -0.5 and r.y + r.h <= H + 0.5,
          ("%dx%d save form: Cancel stays inside the window"):format(W, H))
      end
    end
  end
  Kit.audit = nil
end
LauncherMods.list = realModList

T.finish("cart launcher")
