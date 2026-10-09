-- 6.12, the cosmetics (Config.Cosmetics, shared/Style.luau, shared/StyleLooks.luau) in the standalone Luau CLI: the
-- catalogue (ids unique, every item in a slot, a real colour, a look that builds, prices sensible against the game's
-- earnings and shops, the rewards flagged and never sold), the rules the server decides with (a saved wardrobe
-- cleaned, buy / wear / unwear, which vehicles a slot fits), the hats and jackets drawn on the classic R15 body (a
-- crown over the head, the jacket's shell under the Courier Vest), and the decals laid on a van's panels round its
-- lamps and labels. The fit on real bodies and on the real fleet: tools/character-art/style-check.luau and
-- tools/vehicle-preview/decal-check.luau. Run with tests/run_tests.py.
-- The clerks (the owner: "things are bought only from the NPCs in the shops, for the vibe"): every slot is sold at
-- shops that exist (Dot's gear stall, Gus's Wrench Garage, Kip's BIKES counter at Dead End Motors), where you stand decides a purchase
-- (Style.shopAt / Style.canBuyAt: server/StyleWear.luau's "buy" and the app's BUY), and the toasts say who sells it.
local Config = require("./Config")
local Map = require("./Map")
local Style = require("./Style")
local StyleLooks = require("./StyleLooks")
local CharacterGeometry = require("./CharacterGeometry")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local Fit = Config.Cosmetics.Fit
local items = Config.Cosmetics.Items
local MATERIALS = { Fabric = true, SmoothPlastic = true, Plastic = true, Metal = true, Foil = true, Leather = true, Neon = true }
local REWARDS = { tasks = true, event = true, pass = true }
local PAINTS = { main = true, trim = true, shade = true, dark = true, metal = true, white = true }

-- The catalogue ----------------------------------------------------------------------------------------------------
local seen: { [string]: boolean } = {}
local perSlot: { [string]: { buyable: number, rewards: number, cheapest: number, dearest: number } } = {}
for _, slot in Config.Cosmetics.Slots do
	check(`slot {slot.id}: a tab, a name and a note`, (slot.tab == "courier" or slot.tab == "vehicle") and slot.name ~= "" and #slot.note > 10)
	perSlot[slot.id] = { buyable = 0, rewards = 0, cheapest = math.huge, dearest = 0 }
end
local function colour(c: { number }?): boolean
	return type(c) == "table" and #c == 3 and c[1] >= 0 and c[1] <= 255 and c[2] >= 0 and c[2] <= 255 and c[3] >= 0 and c[3] <= 255
end
for _, def in items do
	check(`{def.id}: a unique id`, not seen[def.id])
	seen[def.id] = true
	local slot = perSlot[def.slot]
	check(`{def.id}: in a known slot`, slot ~= nil, def.slot)
	check(`{def.id}: a name and an English line`, #def.name > 2 and #def.description > 10 and not string.find(def.description, "[ěščřžýáíéůúňťď]"))
	check(`{def.id}: a real colour`, colour(def.color) and (def.trim == nil or colour(def.trim)))
	check(`{def.id}: a known material`, def.material == nil or MATERIALS[def.material] == true, def.material)
	check(`{def.id}: Style.find finds it`, Style.find(def.id) == def)
	if def.reward then
		check(`{def.id}: a reward is never sold (price 0, what gives it)`, def.price == 0 and REWARDS[def.reward] == true and not Style.buyable(def))
		check(`{def.id}: a reward says so`, string.find(def.description, "Not for sale", 1, true) ~= nil)
		if slot then
			slot.rewards += 1
		end
	else
		check(`{def.id}: sold for a price`, def.price > 0 and Style.buyable(def), def.price)
		check(`{def.id}: a level the career reaches`, def.level == nil or (def.level >= 1 and def.level <= Config.Levels.MaxLevel))
		if slot then
			slot.buyable += 1
			slot.cheapest = math.min(slot.cheapest, def.price)
			slot.dearest = math.max(slot.dearest, def.price)
		end
	end
	-- every item has a look that builds
	if def.slot == "hat" then
		check(`{def.id}: a hat look`, table.find(StyleLooks.Hats, def.look) ~= nil and #StyleLooks.hat(def.look) > 0, def.look)
	elseif def.slot == "jacket" then
		check(`{def.id}: a jacket look`, table.find(StyleLooks.Jackets, def.look) ~= nil and #StyleLooks.jacket(def.look) > 0, def.look)
	elseif def.slot == "vest" or def.slot == "bag" then
		check(`{def.id}: a colour (dye)`, def.look == "dye")
	elseif def.slot == "wrap" or def.slot == "bikepaint" then
		check(`{def.id}: a {def.slot} look`, def.look == def.slot)
	elseif def.slot == "decal" then
		check(`{def.id}: a decal look`, table.find(StyleLooks.Decals, def.look) ~= nil, def.look)
	end
end
check("about fifty items", #items >= 40 and #items <= 70, #items)

-- Prices against the economy: a walk pays up to Foot.PayMax (×PayTop), a level's reward from $500, the kit up to
-- $1,500, Wrench Garage's paints $300 – $3,000.
local walk = Config.Jobs.Foot.PayMax * Config.Jobs.Foot.PayTop
local paintLow, paintHigh = math.huge, 0
for _, paint in Config.Paints do
	if paint.price > 0 then
		paintLow, paintHigh = math.min(paintLow, paint.price), math.max(paintHigh, paint.price)
	end
end
local kitHigh = 0
for _, kit in Config.Kit do
	kitHigh = math.max(kitHigh, kit.price)
end
for id, slot in perSlot do
	local courier = (Style.slot(id) :: any).tab == "courier"
	check(`{id}: three or more for sale and a reward for later`, slot.buyable >= 3 and slot.rewards >= 1, `{slot.buyable} / {slot.rewards}`)
	if courier then
		check(`{id}: the cheapest within four walks`, slot.cheapest <= walk * 4, slot.cheapest)
		check(`{id}: none dearer than the dearest kit`, slot.dearest <= kitHigh, slot.dearest)
	else
		check(`{id}: priced with the garage's paints`, slot.cheapest >= 100 and slot.dearest <= paintHigh, `{slot.cheapest} – {slot.dearest}`)
	end
end
check("a wrap costs at least the cheapest paint job", perSlot.wrap.cheapest >= paintLow)
check("the courier's first look within one walk or two", math.min(perSlot.hat.cheapest, perSlot.vest.cheapest, perSlot.bag.cheapest) <= walk * 2)

-- The rules --------------------------------------------------------------------------------------------------------
local cap, beanie, wrap, decal, reward = Style.find("cap_red") :: any, Style.find("beanie_grey") :: any, Style.find("wrap_teal") :: any, Style.find("logo") :: any, Style.find("cap_gold") :: any
local clean = Style.sanitize({ owned = { cap_red = true, nonsense = true, wrap_teal = "yes" }, worn = { hat = "cap_red", jacket = "cap_red", wrap = "wrap_teal", decal = "nope" } })
check("sanitize: known owned items only", clean.owned.cap_red == true and clean.owned.nonsense == nil and clean.owned.wrap_teal == nil)
check("sanitize: a worn item owned and in its own slot", clean.worn.hat == "cap_red" and clean.worn.jacket == nil and clean.worn.wrap == nil and clean.worn.decal == nil)
check("sanitize: anything else is the empty wardrobe", next(Style.sanitize(nil).owned) == nil and next(Style.sanitize("x").worn) == nil)
local style = Style.empty()
check("buy: enough money and level", (Style.canBuy(style, cap, 120, 1)))
check("buy: not enough money", select(2, Style.canBuy(style, cap, 119, 1)) == "money")
local cowboy = Style.find("cowboy") :: any
check("buy: under its level", select(2, Style.canBuy(style, cowboy, 99999, cowboy.level - 1)) == "level")
check("buy: a reward never", select(2, Style.canBuy(style, reward, 99999, 15)) == "reward")
style.owned.cap_red = true
check("buy: never twice", select(2, Style.canBuy(style, cap, 99999, 15)) == "owned")
check("wear: only what you own", (Style.canWear(style, cap)) and select(2, Style.canWear(style, beanie)) == "owned")
check("state: sale, owned, wearing, reward", Style.state(style, beanie) == "sale" and Style.state(style, cap) == "owned" and Style.state(style, reward) == "reward")
style.worn.hat = "cap_red"
check("state: wearing; worn finds it", Style.state(style, cap) == "wearing" and Style.worn(style, "hat") == cap and Style.worn(style, "jacket") == nil)
check("key: the worn items of slots", Style.key(style, { "hat", "jacket" }) == "hat=cap_red;jacket=")
local van, bike, scooter, company
for _, car in Config.Cars do
	if car.id == "van" then van = car end
	if car.id == "citybike" then bike = car end
	if car.id == "escooter" then scooter = car end
	if car.company and not company then company = car end
end
check("a wrap and a decal fit a car, not a bike", Style.forVehicle("wrap", van) and Style.forVehicle("decal", van) and not Style.forVehicle("wrap", bike) and not Style.forVehicle("decal", scooter))
check("bike paint fits the bikes and the E-Scooter, not a car", Style.forVehicle("bikepaint", bike) and Style.forVehicle("bikepaint", scooter) and not Style.forVehicle("bikepaint", van))
check("never on a company vehicle", company ~= nil and not Style.forVehicle("wrap", company) and not Style.forVehicle("decal", company))
check("the toasts", Style.say("bought", cap) == "Backwards Cap · ZDC Red is yours. You're wearing it." and Style.say("money", wrap) == "Not enough money: Satin Teal costs $900."
	and Style.say("level", cowboy) == `Cowboy Hat unlocks at level {cowboy.level}.` and string.find(Style.say("off", nil, "hat"), "Hats off", 1, true) ~= nil
	and Style.say("off", cap, "hat") == "Backwards Cap · ZDC Red is off.")
check("money with thousands", Style.money(1200) == "$1,200" and Style.money(80) == "$80" and Style.money(15000) == "$15,000")
check("Style.slots: four for the courier, three for the vehicles", #Style.slots("courier") == 4 and #Style.slots("vehicle") == 3)

-- Where the looks are sold (the clerks) ----------------------------------------------------------------------------
local function same(list: { string }, want: { string }): boolean
	return table.concat(list, ",") == table.concat(want, ",")
end
local SOLD: { [string]: { string } } = {
	hat = { "supplies", "bags" }, jacket = { "supplies", "bags" }, vest = { "supplies", "bags" }, bag = { "supplies", "bags" },
	wrap = { "mechanic" }, decal = { "mechanic" }, bikepaint = { "bikes", "mechanic" },
}
for _, slot in Config.Cosmetics.Slots do
	local shops = Style.shopsFor(slot.id)
	check(`{slot.id}: sold where the owner said`, SOLD[slot.id] ~= nil and same(shops, SOLD[slot.id]), table.concat(shops, ","))
	local real = #shops > 0
	for _, id in shops do
		real = real and Map.Shops[id] ~= nil and Map.shopRadius(id) > 0
	end
	check(`{slot.id}: every shop of it is in Map.Shops`, real)
	local counter, at = Style.counterFor(slot.id)
	check(`{slot.id}: a clerk sells it, on its tab`, counter ~= nil and at == shops[1] and counter.tab == slot.tab and #counter.clerk > 1 and #counter.place > 3)
	for _, def in Style.items(slot.id) do
		if not same(Style.shopsFor(def), shops) then
			check(`{def.id}: sold where its slot is`, false)
		end
	end
end
for id, counter in Config.Cosmetics.Counters do
	check(`counter {id}: a shop of the map that sells looks of its tab`, Map.Shops[id] ~= nil and (counter.tab == "courier" or counter.tab == "vehicle") and #counter.pitch > 3)
	local sells = false
	for _, slot in Style.slots(counter.tab) do
		sells = sells or Style.sells(id, slot.id)
	end
	check(`counter {id}: sells something of its tab`, sells)
end
check("three clerks: Dot, Gus, Kip", Config.Cosmetics.Counters.supplies.clerk == "Dot" and Config.Cosmetics.Counters.mechanic.clerk == "Gus"
	and Config.Cosmetics.Counters.bikes.clerk == "Kip" and Config.Cosmetics.Counters.bags == nil)
check("sells: a shop of the slot, nothing else", Style.sells("mechanic", wrap) and Style.sells("bags", cap) and not Style.sells("supplies", wrap)
	and not Style.sells("guns", cap) and not Style.sells(nil, cap) and #Style.shopsFor("nonsense") == 0)
-- where you stand (server/Shops.luau's nearShop: the horizontal distance under Map.shopRadius)
local function at(id: string, dx: number?): (number, number)
	local shop = Map.Shops[id]
	return shop.x + (dx or 0), shop.z
end
local bikePaint = Style.find("bike_mint") :: any
local mx, mz = at("mechanic")
check("at Wrench Garage: wraps, decals, bike paint; no hats", Style.shopAt(wrap, mx, mz) == "mechanic" and Style.shopAt(decal, mx, mz) == "mechanic"
	and Style.shopAt(bikePaint, mx, mz) == "mechanic" and Style.shopAt(cap, mx, mz) == nil)
local bx, bz = at("bikes")
check("at the BIKES counter (6.12.7: Dead End Motors'): bike paint only", Style.shopAt(bikePaint, bx, bz) == "bikes" and Style.shopAt(wrap, bx, bz) == nil and Style.shopAt("hat", bx, bz) == nil)
local gx, gz = at("supplies")
local nx, nz = at("bags")
check("at the gear stall (Dot's GEAR or Nell's BAGS): the courier's looks, no wraps", Style.shopAt(cap, gx, gz) == "supplies" and Style.shopAt("vest", nx, nz) ~= nil
	and Style.sells(Style.shopAt("bag", nx, nz), "bag") and Style.shopAt(wrap, gx, gz) == nil)
local r = Map.shopRadius("mechanic")
local inX = at("mechanic", r - 0.5)
local outX = at("mechanic", r + 0.5)
check("the shop's radius is the edge", Style.shopAt(wrap, inX, mz) == "mechanic" and Style.shopAt(wrap, outX, mz) == nil)
check("far from every shop: none", Style.shopAt(cap, 1e5, 1e5) == nil and Style.shopAt(bikePaint, -1e5, 1e5) == nil)
-- the purchase as server/StyleWear.luau decides it (a wardrobe, money, a level, where the character stands)
local function buy(def: any, money: number, level: number, x: number, z: number): (boolean, string?)
	return Style.canBuyAt(Style.empty(), def, money, level, Style.shopAt(def, x, z))
end
check("buy at its shop", (buy(wrap, 99999, 15, mx, mz)) and (buy(cap, 120, 1, gx, gz)) and (buy(cap, 120, 1, nx, nz)) and (buy(bikePaint, 150, 1, bx, bz)) and (buy(bikePaint, 150, 1, mx, mz)))
check("buy away from its shops: \"shop\"", select(2, buy(wrap, 99999, 15, gx, gz)) == "shop" and select(2, buy(cap, 99999, 15, mx, mz)) == "shop"
	and select(2, buy(wrap, 99999, 15, 1e5, 1e5)) == "shop" and select(2, buy(bikePaint, 99999, 15, gx, gz)) == "shop")
check("too poor: \"money\" at the shop, \"shop\" away from it", select(2, buy(wrap, 10, 15, mx, mz)) == "money" and select(2, buy(wrap, 10, 15, gx, gz)) == "shop")
check("a reward or a level says so anywhere", select(2, buy(reward, 99999, 15, gx, gz)) == "reward" and select(2, buy(reward, 99999, 15, 1e5, 1e5)) == "reward"
	and select(2, buy(cowboy, 99999, cowboy.level - 1, gx, gz)) == "level" and select(2, buy(cowboy, 99999, cowboy.level - 1, mx, mz)) == "level")
local mine = Style.empty()
mine.owned.cap_red = true
check("owned stays owned (no second purchase) anywhere", select(2, Style.canBuyAt(mine, cap, 99999, 15, "supplies")) == "owned" and select(2, Style.canBuyAt(mine, cap, 99999, 15, nil)) == "owned")
check("the toasts name the clerk and the shop", Style.say("shop", wrap) == "Buy it from Gus at Wrench Garage." and Style.say("shop", cap) == "Buy it from Dot at the gear stall."
	and Style.say("shop", bikePaint) == "Buy it from Kip at Dead End Motors or Gus at Wrench Garage."
	and Style.say("where", wrap) == "Gus sells it at Wrench Garage. It's on your GPS." and Style.say("where", bikePaint) == "Kip sells it at Dead End Motors. It's on your GPS."
	and Style.say("sold", cap) == "Dot sells it at the gear stall." and Style.say("notOwned", decal) == "Buy ZDC Logo first, from Gus at Wrench Garage.")
check("the app's button away from the shop", Style.atLabel(wrap) == "AT WRENCH GARAGE" and Style.atLabel(cap) == "AT THE GEAR STALL" and Style.atLabel(bikePaint) == "AT DEAD END MOTORS")
check("who sells a tab's looks", Style.soldBy("courier") == "Dot at the gear stall" and Style.soldBy("vehicle") == "Gus at Wrench Garage and Kip at Dead End Motors")
check("no toast says the phone sells", not string.find(string.lower(Style.say("shop", wrap) .. Style.say("where", cap) .. Style.say("notOwned", cap)), "phone", 1, true))

-- The hats and jackets on the classic R15 body ---------------------------------------------------------------------
local half = Fit.Head / 2
for _, look in StyleLooks.Hats do
	local pieces = StyleLooks.hat(look)
	local crown, low, high = 0, math.huge, -math.huge
	local known = true
	for _, p in pieces do
		known = known and p.attach == "Head" and PAINTS[p.paint] == true and p.size[1] > 0 and p.size[2] > 0 and p.size[3] > 0
		if p.shape == "Cylinder" and p.turn and p.turn[3] == 90 then
			-- an upright crown: its diameter across, its height up
			if p.size[1] >= 0.3 then
				crown = math.max(crown, math.min(p.size[2], p.size[3]))
				low = math.min(low, p.at[2] - p.size[1] / 2)
			end
			high = math.max(high, p.at[2] + p.size[1] / 2)
		end
	end
	check(`{look}: pieces on the head, known paints`, known and #pieces <= 12, #pieces)
	check(`{look}: a crown wider than the head (it sits on it)`, crown > Fit.Head, crown)
	check(`{look}: over the head's top, its rim above the eyes`, high > half and low > 0.12 and low < half - 0.1, `{low} … {high}`)
end
local T = Fit.Shell
local vestOuter = 0
for _, p in CharacterGeometry.hivis() do
	if string.match(p.name, "^Vest") then
		vestOuter = math.max(vestOuter, math.abs(p.at[3]) + p.size[3] / 2)
	end
end
for _, look in StyleLooks.Jackets do
	local pieces = StyleLooks.jacket(look)
	local torso: any = nil
	local bones: { [string]: boolean } = {}
	local known = true
	for _, p in pieces do
		known = known and StyleLooks.Nominal[p.attach] ~= nil and PAINTS[p.paint] == true
		bones[p.attach] = true
		if p.name == "JacketTorso" then
			torso = p
		end
	end
	check(`{look}: pieces on the torso and the arms, known paints`, known and #pieces <= 24, #pieces)
	check(`{look}: the shell covers the torso, both arms, the waist`, bones.UpperTorso and bones.LowerTorso and bones.LeftUpperArm and bones.RightLowerArm)
	local n = StyleLooks.Nominal.UpperTorso
	check(`{look}: the torso's shell thin round the torso`, torso ~= nil and torso.size[1] >= n[1] and torso.size[3] >= n[3] and torso.size[1] - n[1] <= 0.1 and torso.size[3] - n[3] <= 0.1)
	check(`{look}: under the Courier Vest's cloth`, torso ~= nil and torso.size[3] / 2 < vestOuter, `{torso and torso.size[3] / 2} < {vestOuter}`)
end
check("the shell is thin", T > 0 and T <= 0.03)
local f = StyleLooks.factors("Head", { 1.6, 1.35, 1.4 })
check("a head's factors: one across and deep", math.abs(f[1] - f[3]) < 1e-9 and math.abs(f[1] - 1.5 / Fit.Head) < 1e-9 and math.abs(f[2] - 1.35 / Fit.Head) < 1e-9)
local odd = StyleLooks.factors("Head", { 9, 0.1, 9 })
check("an odd head: clamped", odd[1] == Fit.HeadMax and odd[2] == Fit.HeadMin)
check("an unknown part: 1", StyleLooks.factors("Tail", { 3, 3, 3 })[1] == 1)

-- The decals on a van's panels (the chassis' space: the front at -Z) ------------------------------------------------
local function boxAt(c: { number }, s: { number }): any
	return { min = { c[1] - s[1] / 2, c[2] - s[2] / 2, c[3] - s[3] / 2 }, max = { c[1] + s[1] / 2, c[2] + s[2] / 2, c[3] + s[3] / 2 } }
end
local function panel(name: string, c: { number }, s: { number }): any
	local b = boxAt(c, s)
	b.name = name
	return b
end
local panels = {
	panel("Hood", { 0, 2.47, -5.25 }, { 6.3, 0.26, 2.5 }),
	panel("CabRoof", { 0, 5.42, -2 }, { 6.3, 0.35, 4 }),
	panel("CargoRoof", { 0, 5.49, 3.2 }, { 6.35, 0.22, 6.4 }),
	panel("CargoSide", { -3.3, 3.4, 3.2 }, { 0.14, 4.4, 6.4 }),
	panel("CargoSide", { 3.3, 3.4, 3.2 }, { 0.14, 4.4, 6.4 }),
	panel("FrontFender", { -3.3, 1.9, -5.25 }, { 0.13, 1.4, 2.5 }),
	panel("FrontFender", { 3.3, 1.9, -5.25 }, { 0.13, 1.4, 2.5 }),
}
local blocks = {
	boxAt({ 0, 5.73, -3.55 }, { 3.5, 0.18, 0.45 }), -- a roof lamp pod over the cab
	boxAt({ 3.395, 3.9, 3.33 }, { 0.025, 0.65, 3.5 }), -- the right side's ZDC label
	boxAt({ -3.395, 3.9, 3.33 }, { 0.025, 0.65, 3.5 }), -- the left side's
	boxAt({ 3.41, 3.41, 3.2 }, { 0.045, 0.1, 5.9 }), -- the right side's red stripe
	boxAt({ -3.41, 3.41, 3.2 }, { 0.045, 0.1, 5.9 }), -- the left side's
}
local function hits(piece: any, list: { any }): boolean
	local e = StyleLooks.extents(piece.size, piece.turn)
	for _, b in list do
		local inX = piece.at[1] + e[1] > b.min[1] and piece.at[1] - e[1] < b.max[1]
		local inY = piece.at[2] + e[2] > b.min[2] and piece.at[2] - e[2] < b.max[2]
		local inZ = piece.at[3] + e[3] > b.min[3] and piece.at[3] - e[3] < b.max[3]
		if inX and inY and inZ then
			return true
		end
	end
	return false
end
for _, look in StyleLooks.Decals do
	local pieces = StyleLooks.decals(look, panels, blocks)
	local clear, flat = true, true
	for _, p in pieces do
		clear = clear and not hits(p, blocks) and not hits(p, panels)
		flat = flat and p.attach == "Chassis" and math.min(p.size[1], p.size[2], p.size[3]) <= Fit.Thick + 1e-9
	end
	check(`{look}: laid on the van ({#pieces} parts, within the budget)`, #pieces > 0 and #pieces <= Fit.Budget, #pieces)
	check(`{look}: clear of the lamps, the labels, the stripes and the panels themselves`, clear)
	check(`{look}: thin`, flat)
end
local stripes = StyleLooks.decals("stripes", panels, blocks)
local onHood, cut = 0, false
for _, p in stripes do
	if p.at[3] < -4 then
		onHood += 1
	end
	if p.at[3] > -3.55 and p.at[3] < 0 and p.at[2] > 5.5 then
		cut = true -- the cab roof's stripes behind the lamp pod
	end
end
check("stripes: two on the hood, cut round the lamp pod", onHood == 2 and cut)
local sides = { [-1] = 0, [1] = 0 }
for _, p in StyleLooks.decals("logo", panels, blocks) do
	if p.name == "LogoFace" then
		sides[if p.at[1] < 0 then -1 else 1] += 1
		check("the logo's face reads outward", p.text == "ZDC" and p.face == (if p.at[1] < 0 then "Left" else "Right"))
	end
end
check("logo: one on each side", sides[-1] == 1 and sides[1] == 1)
local checks = 0
for _, p in StyleLooks.decals("checker", panels, blocks) do
	if p.checker then
		checks += 1
	end
end
check("checker: a band down both sides", checks >= 2)
check("no room, no decal", #StyleLooks.decals("flames", {}, {}) == 0 and #StyleLooks.decals("nonsense", panels, blocks) == 0)
check("bike paint: the frame's tubes and the scooter's deck", table.find(StyleLooks.BikeFrame, "DownTube") ~= nil and table.find(StyleLooks.BikeFrame, "Deck") ~= nil)
check("the vest's cloth and the five bags' bodies", StyleLooks.Vest.VestL == 1 and StyleLooks.Bags.bag and StyleLooks.Bags.tote and StyleLooks.Bags.thermal and StyleLooks.Bags.padded and StyleLooks.Bags.duffel)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
