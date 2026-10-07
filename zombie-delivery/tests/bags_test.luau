-- 6.4, five bags (Config.Kit pieces with `extra`; shared/Transport.luau activeBag / bagRoom …): the shop's list, the
-- bag in your hand is ONE bag (the choice, else the best owned: the most room, a tie the later one), its room is never
-- the sum of the bags you own, the perks' numbers (the thermal bag's warm, the padded messenger, the duffel's breath),
-- the fragile knocks on foot (JobRules.footKnock / knockLoss), the sprint (pieces in the bag are never in your hands:
-- Holding.place; the duffel's breath cost: client/Stamina.luau), each bag's swing (BagSwing.tuning) and its art
-- (server/KitArt/Geometry.luau, copied as KitGeometry). 6.6: one carrying item (no backpacks), the bags sold at ZDC
-- Bags (Map.Shops.bags), the retired backpacks' refund (Transport.packRefund). Run with tests/run_tests.py.
local Config = require("./Config")
local Transport = require("./Transport")
local JobRules = require("./JobRules")
local Holding = require("./Holding")
local KitFit = require("./KitFit")
local BagSwing = require("./BagSwing")
local Stamina = require("./Stamina")
local KitArt = require("./KitGeometry")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) < (eps or 1e-6)
end
local function kit(id: string): Config.KitDef
	return Transport.findKit(id) :: Config.KitDef
end

-- The shop's list ----------------------------------------------------------------------------------------------------

local bags: { string } = {}
for _, def in Config.Kit do
	if Transport.isBag(def) then
		table.insert(bags, def.id)
	end
end
check("five bags in the shop, in this order", table.concat(bags, ",") == "bag,tote,thermal,padded,duffel", table.concat(bags, ","))
local want = {
	bag = { 0, 1, 2 }, -- 6.7: the starter bag, never sold
	tote = { 120, 2, 3 },
	thermal = { 300, 3, 4 },
	padded = { 650, 4, 4 },
	duffel = { 1200, 6, 6 },
}
for id, n in want do
	local def = kit(id)
	check(`{def.name}: \${n[1]}, level {n[2]}, +{n[3]}`, def.price == n[1] and def.level == n[2] and def.extra == n[3], `{def.price} {def.level} {def.extra}`)
	check(`{def.name}: the sprint first in its words`, string.find(def.description, "Sprint with your deliveries", 1, true) ~= nil, def.description)
	check(`{def.name}: no room on the back, no walk speed`, (def :: any).room == nil and def.speed == nil and (def :: any).warm == nil)
end
check("the shoes are no bag", not Transport.isBag(kit("shoes")) and not Transport.isBag(nil))
check("6.7: the plastic bag is the starter (not sold), the other bags are", kit("bag").starter == true and kit("tote").starter == nil and kit("duffel").starter == nil)
check("6.7: every bag at ZDC Bags", Transport.kitShop(kit("bag")) == "bags" and Transport.kitShop(kit("duffel")) == "bags")

-- 6.6, one carrying item: the backpacks are gone, their owners paid back ------------------------------------------

check("6.6: no backpack in the kit any more", Transport.findKit("backpack") == nil and Transport.findKit("bigpack") == nil)
local anyRoom = false
for _, def in Config.Kit do
	anyRoom = anyRoom or (def :: any).room ~= nil
end
check("6.6: no kit piece adds room on the back", not anyRoom)
check("6.6: the retired backpacks keep their prices for the refund", Config.RetiredKit[1].id == "backpack" and Config.RetiredKit[1].price == 150
	and Config.RetiredKit[2].id == "bigpack" and Config.RetiredKit[2].price == 400 and Config.RetiredKit[1].flag == "noPacks" and Config.RetiredKit[2].flag == "noPacks")
check("6.7: … and the Thermal Jacket after them, its own flag", #Config.RetiredKit == 3 and Config.RetiredKit[3].id == "jacket" and Config.RetiredKit[3].price == 300
	and Config.RetiredKit[3].flag == "noJacket")
local money, names = Transport.packRefund({ backpack = true, bigpack = true, bag = true, shoes = true })
check("6.6: both backpacks: $550 back", money == 550 and #names == 2 and names[1] == "Courier Backpack" and names[2] == "Big Backpack", money)
check("6.6: the Courier Backpack alone: $150", (Transport.packRefund({ backpack = true })) == 150)
check("6.6: the Big Backpack alone: $400", (Transport.packRefund({ bigpack = true, tote = true })) == 400)
check("6.6: no backpack: nothing", (Transport.packRefund({ bag = true, duffel = true })) == 0 and (Transport.packRefund({})) == 0)
check("6.7: the backpacks' refund leaves the jacket alone", (Transport.packRefund({ jacket = true })) == 0 and (Transport.packRefund({ jacket = true, backpack = true })) == 150)
check("6.6: a false entry or a broken save: nothing", (Transport.packRefund({ backpack = false })) == 0 and (Transport.packRefund(nil)) == 0 and (Transport.packRefund("backpack")) == 0)
local words = string.gsub(Config.Courier.PackRefund, "{money}", "$550")
check("6.6: Marge's words", words == "Backpacks are gone: bags do it all now. You got $550 back.", words)

-- 6.6, ZDC Bags: the bag kiosk in the depot's safe yard, by the spawn --------------------------------------------------

local Map = require("./Map")
local shop = Map.Shops.bags
check("6.6: ZDC Bags is a shop", shop ~= nil and shop.name == "ZDC Bags" and shop.x == Config.BagShop.X and shop.z == Config.BagShop.Z)
check("6.6: a kiosk's own radius, the big shops' as before", Map.shopRadius("bags") == Config.BagShop.Radius and Map.shopRadius("supplies") == Map.ShopRadius and Map.shopRadius("moon") == Map.ShopRadius)
local function away(x: number, z: number): number
	return math.sqrt((Config.BagShop.X - x) ^ 2 + (Config.BagShop.Z - z) ^ 2)
end
local rack = Config.Rental.SpawnRack
local marge = Config.Tutorial.NpcSpot
check("6.6: inside the depot's block, in the safe zone", math.abs(Config.BagShop.X) < Config.City.BlockSize / 2 - 8 and math.abs(Config.BagShop.Z) < Config.City.BlockSize / 2 - 8 and Map.isSafe(Config.BagShop.X, Config.BagShop.Z))
check("6.6: clear of the spawn pad (0, 26), its radius not over it", away(0, 26) - 5 > Config.BagShop.Radius - 2, away(0, 26))
check("6.6: clear of the scooter rack", away(rack.x + rack.slots * rack.pitch / 2, rack.z) > 12 and away(rack.x - rack.slots * rack.pitch / 2, rack.z) > 12)
check("6.6: clear of the job board, the garage terminal and Marge", away(-18, -25) > 40 and away(18, -25) > 40 and away(marge[1], marge[2]) > 40)
local soldHere = 0
for _, def in Config.Kit do
	if Transport.isBag(def) then
		soldHere += 1
	end
end
check("6.6: it sells the five bags", soldHere == 5)

-- The bag in your hand -------------------------------------------------------------------------------------------------

local hands = Config.Cargo.HandsMax
check("no bag: none active, no room", Transport.activeBag({}, nil) == nil and Transport.bagRoom({}, nil) == 0 and Transport.bagRoom({ shoes = true }, "duffel") == 0)
check("the plastic bag alone: 2", Transport.bagRoom({ bag = true }, nil) == 2 and (Transport.activeBag({ bag = true }, nil) :: any).id == "bag")
local all = { bag = true, tote = true, thermal = true, padded = true, duffel = true }
check("every bag owned: the duffel's 6, never the sum (21)", Transport.bagRoom(all, nil) == 6 and Transport.handsRoom(all, nil) == hands + 6, Transport.handsRoom(all, nil))
check("the default is the best: the most room", (Transport.bestBag({ bag = true, tote = true }) :: any).id == "tote")
check("a tie goes to the later (pricier) one: the padded over the thermal", (Transport.bestBag({ thermal = true, padded = true }) :: any).id == "padded")
check("your choice wins when you own it", (Transport.activeBag(all, "thermal") :: any).id == "thermal" and Transport.bagRoom(all, "bag") == 2)
check("a choice you don't own: the best", (Transport.activeBag({ bag = true, tote = true }, "duffel") :: any).id == "tote")
check("a choice that is no bag: the best", (Transport.activeBag({ bag = true, shoes = true }, "shoes") :: any).id == "bag" and (Transport.activeBag({ bag = true }, "rocket") :: any).id == "bag")
check("6.6: the hands' room: the hands + the active bag", Transport.handsRoom({ bag = true, tote = true }, nil) == hands + 3
	and Transport.handsRoom({ bag = true, tote = true }, "bag") == hands + 2)
check("6.6: the pack's room: the bag's", Transport.packRoom(all, "tote") == 3 and Transport.packRoom({ duffel = true }, nil) == 6)
check("on foot and on a bike: the active bag only", Transport.foot(all, "thermal").room == hands + 4 and Transport.bike(2, all, "padded").room == 2 + 4)
check("the bags never add to the walk", Transport.speedMult(all) == 1)

-- The perks ------------------------------------------------------------------------------------------------------------

check("the thermal bag: food in it cools ×0.35", kit("thermal").bagWarm == 0.35 and Transport.bagWarm(all, "thermal") == 0.35 and Transport.bagWarm(all, "duffel") == 1)
check("only the thermal bag keeps warm", Transport.bagWarm({ bag = true }, nil) == 1 and Transport.bagWarm(all, "padded") == 1)
check("mixWarm: all of it in the bag, none, half", near(Transport.mixWarm(1, 0.35), 0.35) and Transport.mixWarm(0, 0.35) == 1 and near(Transport.mixWarm(0.5, 0.35), 0.675))
check("mixWarm: out of range is clamped", near(Transport.mixWarm(2, 0.35), 0.35) and Transport.mixWarm(-1, 0.35) == 1 and Transport.mixWarm(0 / 0, 0.35) == 1)
local plain = JobRules.freshDrain(1, 60, false)
local bagged = JobRules.freshDrain(1, 60, false, Transport.mixWarm(1, Transport.bagWarm(all, "thermal")))
check("the thermal bag alone does it: × 0.35 (6.7: no jacket on top)", near(bagged, plain * 0.35), bagged)
check("the padded messenger: fragile safe, the others not", Transport.bagPadded(all, "padded") and not Transport.bagPadded(all, "thermal") and not Transport.bagPadded(all, nil))
check("the duffel: sprint breath ×1.15 (no slower walk)", kit("duffel").bagBreath == 1.15 and Transport.bagBreath(all, "duffel") == 1.15 and Transport.bagBreath(all, "tote") == 1)

-- The fragile knocks on foot -------------------------------------------------------------------------------------------

local R = Config.Jobs.CargoRules
check("the knock numbers", R.FootFallSpeed > 55 and R.FootFall > 0 and R.FootHit > 0 and R.FootHit <= R.FootFall and R.FootHitMin > 0 and R.FootKnockCooldown > 0)
local jump = math.sqrt(2 * 196.2 * 6.4) -- a jump landing where it started (~50 studs / s)
check("a jump is no fall", JobRules.footKnock(jump, true, 0) == nil)
check("a hard landing is a fall", JobRules.footKnock(R.FootFallSpeed + 1, true, 0) == "fall")
check("still in the air: not yet", JobRules.footKnock(R.FootFallSpeed + 30, false, 0) == nil)
check("a bite is a hit, a scratch is not", JobRules.footKnock(0, true, R.FootHitMin) == "hit" and JobRules.footKnock(0, true, R.FootHitMin - 1) == nil)
check("the losses", JobRules.knockLoss("fall", false) == R.FootFall and JobRules.knockLoss("hit", false) == R.FootHit and JobRules.knockLoss(nil, false) == 0)
check("in the padded bag: nothing", JobRules.knockLoss("fall", true) == 0 and JobRules.knockLoss("hit", true) == 0)

-- The sprint -------------------------------------------------------------------------------------------------------------

check("a pickup goes into the bag in your hand while it has room (the hands stay free: you sprint)",
	Holding.place(true, false, 0, true, 6) == "bag" and Holding.place(true, false, 0, true, 1) == "bag" and Holding.place(true, false, 0, true, 0) == "hands")
check("not into the bag when it is not your hand", Holding.place(true, false, 0, false, 6) == "hands")
local M = Config.Movement
local light = Stamina.step(Stamina.new(), 1, true, true, M :: any)
local heavy = Stamina.step(Stamina.new(), 1, true, true, M :: any, Transport.bagBreath(all, "duffel"))
check("with the duffel you still sprint", heavy.sprinting)
check("… and the breath goes 15% faster", near(1 - heavy.breath, (1 - light.breath) * 1.15), `{1 - heavy.breath} vs {1 - light.breath}`)
check("no cost: as before", near(Stamina.step(Stamina.new(), 1, true, true, M :: any, nil).breath, light.breath))

-- The look and the swing ------------------------------------------------------------------------------------------------

for _, id in bags do
	local pieces = KitArt.pieces(id)
	local names: { [string]: boolean } = {}
	local unique, onPivot, low = true, true, 0
	for _, piece in pieces do
		unique = unique and not names[piece.name]
		names[piece.name] = true
		onPivot = onPivot and piece.attach == "BagPivot"
		if not piece.turn then
			low = math.max(low, piece.size[2] / 2 - piece.at[2])
		end
	end
	-- 6.7: real-size bags, up to 20 parts; one in the hand (its grip ~1.9 over the ground: tools/character-art/bag-check
	-- measures it on the real body) at least 0.3 clear of the ground, one worn on the shoulder or the hip lower down
	local def = kit(id)
	local inHand = (def.carry or "hand") == "hand"
	check(`{id}: its own art on the bag's pivot ({#pieces} pieces)`, #pieces >= 6 and #pieces <= 20 and unique and onPivot and KitArt.bags[id] == true)
	check(`{id}: a real-size bag, clear of the ground {if inHand then "under the hand (1.9 up)" else "where it is worn"}`, low > 0.9 and low <= (if inHand then 1.6 else 2.2), low)
	check(`{id}: in the hand`, KitFit.outfit({ [id] = true }, id).hand == id)
end
check("the plastic bag's look is still the 6.0 one", KitArt.pieces("bag")[4].name == "BagBody")
check("an unowned choice shows no bag; no choice: the plastic one", KitFit.outfit({ bag = true }, "duffel").hand == nil and KitFit.outfit({ bag = true }).hand == "bag")
local base = Config.Courier.Bag
local last = BagSwing.tuning(base, nil)
check("the plastic bag swings as in 6.1", last.Spring == base.Spring and last.Flutter == base.Flutter)
for _, id in { "tote", "thermal", "duffel" } do
	local t = BagSwing.tuning(base, Config.Courier.Bags[id])
	check(`{id}: heavier than the one before (slower, less flutter and twist)`, t.Spring < last.Spring and t.FlutterHz < last.FlutterHz and t.Flutter < last.Flutter and t.Twist < last.Twist)
	last = t
end
local padded = BagSwing.tuning(base, Config.Courier.Bags.padded)
check("the padded messenger: between the plastic bag and the duffel", padded.Spring < base.Spring and padded.Spring > Config.Courier.Bags.duffel.Spring)
check("tuning ignores unknown keys and keeps the base", BagSwing.tuning(base, { Nope = 3, Spring = 10 } :: any).Spring == 10 and (BagSwing.tuning(base, { Nope = 3 } :: any) :: any).Nope == nil and base.Spring == 70)

-- How each bag is carried (6.4: Config.Kit carry / stays, Holding.wornAs / bagLeaves) -----------------------------------

local styles = { bag = { "hand", false }, thermal = { "hand", false }, tote = { "shoulder", true }, padded = { "hip", true }, duffel = { "hand", true } }
for id, s in styles do
	local def = kit(id)
	check(`{def.name}: carried {s[1]}{if s[2] then ", stays on" else ""}`, (def.carry or "hand") == s[1] and (def.stays == true) == s[2])
	check(`{def.name}: worn {s[1]} while it is the hand`, Holding.wornAs("bag", def.carry, def.stays, false) == s[1])
	check(`{def.name}: out of the hand {if s[2] then "on the back" else "away"}`, Holding.wornAs("gun", def.carry, def.stays, false) == (if s[2] then "back" else nil)
		and Holding.wornAs("fists", def.carry, def.stays, false) == (if s[2] then "back" else nil))
	check(`{def.name}: in a seat {if s[2] then "on the back" else "put away"}`, Holding.wornAs("bag", def.carry, def.stays, true) == (if s[2] then "back" else nil))
	check(`{def.name}: leaving the hand loaded: {if s[2] then "back" else "down"}`, Holding.bagLeaves(3, def.stays) == (if s[2] then "back" else "down")
		and Holding.bagLeaves(0, def.stays) == (if s[2] then "back" else "stow"))
end
check("6.1's rule without a style: down or stowed", Holding.bagLeaves(1) == "down" and Holding.bagLeaves(0) == "stow")
check("the messenger's description: sprint first, stays on", string.find(kit("padded").description, "^Sprint with your deliveries%. Stays on your back when you draw your gun%.") ~= nil)
local places = Config.Courier.BagPlaces
check("every worn place on the torso", places.shoulder.part == "UpperTorso" and places.hip.part == "UpperTorso" and places.back.part == "UpperTorso" and places.hipBack.part == "UpperTorso")
check("the shoulder and the hip on the left, the slung bag behind", places.shoulder.at[1] < 0 and places.hip.at[1] < 0 and places.back.at[3] > 0.5 and places.hipBack.at[3] > 0.5)
check("the strap: the messenger across the body, a slung tote / duffel across the chest, none in the hand",
	#KitArt.straps("padded", "hip") > 0 and #KitArt.straps("padded", "hipBack") > 0 and #KitArt.straps("duffel", "back") > 0
	and #KitArt.straps("tote", "back") > 0 and #KitArt.straps("duffel", "hand") == 0 and #KitArt.straps("bag", "hand") == 0)
for _, piece in KitArt.straps("padded", "hip") do
	check(`strap {piece.name} on the torso, within it`, piece.attach == "UpperTorso" and math.abs(piece.at[1]) <= 1 and math.abs(piece.at[2]) <= 0.9)
end
check("the move takes about half a second, the sling and unsling gestures as long", Config.Courier.Switch >= 0.3 and Config.Courier.Switch <= 0.8
	and Config.Juice.Gestures.sling ~= nil and Config.Juice.Gestures.unsling ~= nil)
check("a worn bag's bounce: none standing, some walking, never over the amount", BagSwing.bob(1, 0, 0.06, 3.5, 28) == 0
	and BagSwing.bob(1.75, 28, 0.06, 3.5, 28) > 0.05 and BagSwing.bob(3.5, 28, 0.06, 3.5, 28) < 1e-6 and BagSwing.bob(1.75, 99, 0.06, 3.5, 28) <= 0.06 + 1e-9)
check("a broken bounce is none", BagSwing.bob(0 / 0, 10, 0.06, 3.5, 28) == 0 and BagSwing.bob(1, 10, 0.06, 0, 28) == 0)
local wear = BagSwing.tuning(base, Config.Courier.Wear)
check("on the shoulder or the hip: stiffer and smaller than in the hand", wear.Spring > base.Spring and wear.MaxTilt < base.MaxTilt and wear.Flutter == 0)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
