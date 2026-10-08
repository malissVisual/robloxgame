-- 6.0, the vests (Config.Kit armour, shared/Armour.luau): the best vest owned takes its share off every bite and bullet
-- (server/Armour.luau), the Heavy Armour slows you a little (shared/Transport.luau). Run with tests/run_tests.py.
local Config = require("./Config")
local Armour = require("./Armour")
local Transport = require("./Transport")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

-- The two vests in Config.Kit ------------------------------------------------------------------------------------

local kevlar = Transport.findKit("kevlar") :: Config.KitDef
local heavy = Transport.findKit("heavy") :: Config.KitDef
check("the Kevlar Vest: −30%, $600, level 3", kevlar ~= nil and kevlar.armour == 0.3 and kevlar.price == 600 and kevlar.level == 3 and kevlar.speed == nil)
check("the Heavy Armour: −50%, a little slower (×0.92), $1,500, level 5", heavy ~= nil and heavy.armour == 0.5 and heavy.speed == 0.92
	and heavy.price == 1500 and heavy.level == 5)
check("both: a name, an icon, words", kevlar.name ~= "" and kevlar.icon ~= "" and kevlar.description ~= "" and heavy.name ~= "" and heavy.icon ~= "" and heavy.description ~= "")
check("a vest carries nothing", Transport.handsRoom({ kevlar = true, heavy = true }) == Config.Cargo.HandsMax)
local others = true
for _, def in Config.Kit do
	if def.id ~= "kevlar" and def.id ~= "heavy" and def.armour ~= nil then
		others = false
	end
	if def.armour ~= nil and (def.armour <= 0 or def.armour > Config.Arms.MaxArmour) then
		others = false
	end
end
check("only the vests have armour, each within (0, MaxArmour]", others and Config.Arms.MaxArmour < 1)

-- The best vest ---------------------------------------------------------------------------------------------------

check("no vest: none, 0%", Armour.best({}) == nil and Armour.share({}) == 0 and Armour.percent({}) == 0)
check("other kit is no vest", Armour.best({ bag = true, shoes = true, jacket = true }) == nil)
check("kevlar: 30%", (Armour.best({ kevlar = true }) :: any).id == "kevlar" and near(Armour.share({ kevlar = true }), 0.3) and Armour.percent({ kevlar = true }) == 30)
check("heavy: 50%", near(Armour.share({ heavy = true }), 0.5) and Armour.percent({ heavy = true }) == 50)
check("both: the best counts (50%, not 80%)", (Armour.best({ kevlar = true, heavy = true }) :: any).id == "heavy" and Armour.percent({ kevlar = true, heavy = true }) == 50)
check("an unknown or false id is ignored", Armour.share({ forcefield = true, heavy = false } :: any) == 0)

-- The damage -------------------------------------------------------------------------------------------------------

check("no vest: the full hit", Armour.reduce(10, {}) == 10)
check("kevlar: 10 → 7", near(Armour.reduce(10, { kevlar = true }), 7))
check("heavy: 10 → 5", near(Armour.reduce(10, { heavy = true }), 5))
local bite = Config.Zombies.walker.damage
check("a walker's bite through heavy armour: half", near(Armour.reduce(bite, { heavy = true }), bite / 2))
check("nothing, a negative or NaN hit: 0", Armour.reduce(0, { heavy = true }) == 0 and Armour.reduce(-5, {}) == 0 and Armour.reduce(0 / 0, {}) == 0)
check("never more than the hit, never below 0", Armour.reduce(1e6, { heavy = true }) <= 1e6 and Armour.reduce(1e6, { heavy = true }) > 0)

-- The speed ---------------------------------------------------------------------------------------------------------

check("heavy armour: walk and sprint ×0.92", Transport.speedMult({ heavy = true }) == 0.92 and Transport.foot({ heavy = true }).speedMult == 0.92)
check("kevlar: no slower", Transport.speedMult({ kevlar = true }) == 1)

-- On the career road and in the shop's order -----------------------------------------------------------------------

check("the vests come after the first four pieces (the KIT tab's order)", (function()
	local at: { [string]: number } = {}
	for index, def in Config.Kit do
		at[def.id] = index
	end
	return at.kevlar > at.duffel and at.heavy > at.kevlar -- (6.7: the jacket is retired; 6.12.2: the shoes too: after the bags)
end)())

-- 6.0.1: the Courier Vest (the red reflective vest a new courier buys): a look, no armour, sold next to the bag.
local hivis = Transport.findKit(Config.Courier.VestKit) :: Config.KitDef
check("the Courier Vest: $20, level 1, an icon and words", hivis ~= nil and hivis.id == "hivis" and hivis.name == "Courier Vest" and hivis.price == 20
	and hivis.level == 1 and hivis.icon == "🦺" and hivis.description ~= "")
check("the Courier Vest takes nothing off and adds nothing", hivis.armour == nil and Armour.best({ hivis = true }) == nil and Armour.percent({ hivis = true, kevlar = true }) == 30
	and (hivis :: any).room == nil and hivis.extra == nil and hivis.speed == nil and Transport.speedMult({ hivis = true }) == 1)
check("6.7: the Courier Vest's tips: +5%, also under a Kevlar", hivis.tips == 0.05 and Transport.tipShare({ hivis = true }) == 0.05
	and Transport.tipShare({ hivis = true, kevlar = true, heavy = true }) == 0.05 and Transport.tipShare({ kevlar = true }) == 0)
check("the Courier Vest right after the bag in the KIT tab", (function()
	for index, def in Config.Kit do
		if def.id == "bag" then
			return Config.Kit[index + 1] == hivis
		end
	end
	return false
end)())

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
