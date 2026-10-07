-- 5.0, from the bottom (shared/Transport.luau, Config.Kit, Config.Jobs.Foot, shared/JobRules.luau footPay / footTime /
-- footPieces): what you carry on foot with your kit, how fast you walk, the food's drain, and the ON FOOT jobs' pay,
-- clock and pieces. Run with tests/run_tests.py.
local Config = require("./Config")
local Transport = require("./Transport")
local JobRules = require("./JobRules")
local Levels = require("./Levels")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local hands = Config.Cargo.HandsMax

-- The kit ---------------------------------------------------------------------------------------------------------

local function kit(def: string): Config.KitDef
	return Transport.findKit(def) :: Config.KitDef
end
check("the backpacks, shoes and jacket at level 1 (6.0: and more kit)", #Config.Kit >= 5 and kit("backpack").level == 1 and kit("shoes").level == 1 and kit("bigpack").level == 1 and kit("jacket").level == 1)
check("the prices: backpack $150, shoes $250, big backpack $400, jacket $300", kit("backpack").price == 150 and kit("shoes").price == 250
	and kit("bigpack").price == 400 and kit("jacket").price == 300)
check("the numbers: room 3 and 4, speed 1.1, warm 0.8", kit("backpack").room == 3 and kit("bigpack").room == 4 and kit("shoes").speed == 1.1 and kit("jacket").warm == 0.8)
check("an unknown id is nil", Transport.findKit("rocketpack") == nil)
check("6.0: the plastic bag, $25 at level 1: 2 extra", kit("bag").price == 25 and kit("bag").level == 1 and kit("bag").extra == 2 and kit("bag").room == nil)
local seen: { [string]: boolean } = {}
local unique = true
for _, def in Config.Kit do
	if seen[def.id] or def.name == "" or def.description == "" or def.icon == "" then
		unique = false
	end
	seen[def.id] = true
end
check("every piece: its own id, a name, an icon, words", unique)

-- What you carry ---------------------------------------------------------------------------------------------------

check("bare hands: HandsMax (2)", Transport.handsRoom({}) == hands and hands == 2, Transport.handsRoom({}))
check("the backpack: 3", Transport.handsRoom({ backpack = true }) == 3)
check("the big backpack: 4", Transport.handsRoom({ bigpack = true }) == 4)
check("both: the best counts (4, not 7)", Transport.handsRoom({ backpack = true, bigpack = true }) == 4)
check("shoes carry nothing", Transport.handsRoom({ shoes = true, jacket = true }) == hands)
check("an unknown or false id is ignored", Transport.handsRoom({ rocketpack = true, bigpack = false } :: any) == hands)
check("6.0: the bag alone: 2 more (4)", Transport.handsRoom({ bag = true }) == hands + 2)
check("6.0: the bag adds up with the best backpack", Transport.handsRoom({ bag = true, backpack = true }) == 5 and Transport.handsRoom({ bag = true, bigpack = true, backpack = true }) == 6)
check("6.0: the bag rides in the pack's room", Transport.packRoom({ bag = true }) == 2 and Transport.packRoom({ bag = true, bigpack = true }) == 4)
check("6.0: the bag carries but does not speed you up", Transport.speedMult({ bag = true }) == 1 and Transport.warm({ bag = true }) == 1)
check("the pack: what is over the hands", Transport.packRoom({}) == 0 and Transport.packRoom({ backpack = true }) == 1 and Transport.packRoom({ bigpack = true }) == 2)

-- Walking and the food --------------------------------------------------------------------------------------------

check("no shoes: speed 1", Transport.speedMult({}) == 1 and Transport.speedMult({ backpack = true }) == 1)
check("running shoes: 1.1", Transport.speedMult({ shoes = true }) == 1.1)
-- 6.0: the Heavy Armour slows you a little (its speed below 1), with the shoes too; the Kevlar Vest does not.
check("6.0: heavy armour: 0.92", Transport.speedMult({ heavy = true }) == 0.92)
check("6.0: shoes and heavy armour: 1.1 × 0.92", math.abs(Transport.speedMult({ shoes = true, heavy = true }) - 1.1 * 0.92) < 1e-9)
check("6.0: the kevlar vest: no slower", Transport.speedMult({ kevlar = true }) == 1 and Transport.speedMult({ kevlar = true, shoes = true }) == 1.1)
check("no jacket: the food drains as usual", Transport.warm({}) == 1)
check("a thermal jacket: × 0.8", Transport.warm({ jacket = true }) == 0.8)
local plain, warm = JobRules.freshDrain(1, 60, false), JobRules.freshDrain(1, 60, false, Transport.warm({ jacket = true }))
check("freshDrain takes the jacket", math.abs(warm - plain * 0.8) < 1e-9 and plain > 0, `{plain} {warm}`)
check("freshDrain without it is the 4.8 one", JobRules.freshDrain(2, 30, true) == JobRules.freshDrain(2, 30, true, nil))

-- The Info --------------------------------------------------------------------------------------------------------

local foot = Transport.foot({ backpack = true, shoes = true })
check("on foot: mode, room, light only, speed", foot.mode == "foot" and foot.room == 3 and foot.lightOnly == true and foot.speedMult == 1.1)
local bare = Transport.foot({})
check("on foot with nothing: 2, 1", bare.room == hands and bare.speedMult == 1)
local car = Transport.car(4)
check("in a car: its room, any cargo, no kit speed", car.mode == "car" and car.room == 4 and car.lightOnly == false and car.speedMult == 1)
check("a car's room is whole and never below 0", Transport.car(-2).room == 0 and Transport.car(3.7).room == 3)

-- The ON FOOT jobs (Config.Jobs.Foot) -----------------------------------------------------------------------------

local Foot = Config.Jobs.Foot
check("three foot offers on the board", Foot.Offers == 3)
check("1 – 3 pieces", Foot.Pieces[1] == 1 and Foot.Pieces[2] == 3)
check("the walk: 80 – 350 studs, the pick-up within 250", Foot.MinDistance == 80 and Foot.MaxDistance == 350 and Foot.PickupMax == 250 and Foot.PickupMin < Foot.PickupMax)
check("Downtown and the Suburbs only", Foot.Districts.Downtown == true and Foot.Districts.Suburbs == true and Foot.Districts.Harbor == nil)
check("pieces never more than you carry", JobRules.footPieces(3, 2) == 2 and JobRules.footPieces(3, 4) == 3 and JobRules.footPieces(1, 4) == 1)
check("pieces within the band", JobRules.footPieces(9, 9) == Foot.Pieces[2] and JobRules.footPieces(0, 9) == Foot.Pieces[1])
check("at least one piece", JobRules.footPieces(2, 0) == 1)

-- The pay: about $60 – 110 (the walk: the approach up to 250 and the drop 80 – 350).
local low = JobRules.footPay(80, 1)
local high = JobRules.footPay(250 + 350, 3)
check("the pay: about $60 – 110", low >= 55 and low <= 75 and high >= 95 and high <= 115, `{low} … {high}`)
check("the pay is kept within PayMin … PayMax", JobRules.footPay(0, 0) == Foot.PayMin and JobRules.footPay(99999, 3) == Foot.PayMax)
check("the pay in $5 steps", JobRules.footPay(333, 2) % 5 == 0 and JobRules.footPay(333, 2, 1.15) % 5 == 0)
check("a longer walk pays more", JobRules.footPay(500, 2) > JobRules.footPay(150, 2))
check("the role's multiplier", JobRules.footPay(300, 2, 1.15) > JobRules.footPay(300, 2))
check("never over PayMax × PayTop (a risky rush)", JobRules.footPay(600, 3, 1.1 * 1.4) <= Foot.PayMax * Foot.PayTop, JobRules.footPay(600, 3, 1.1 * 1.4))

-- The clock: generous for walking (14 studs / s, sprint 28).
local walk = Config.Movement.Walk
for _, distance in { 100, 300, 600 } do
	local clock = JobRules.footTime(distance, 0)
	check(`the clock for {distance} studs lets you walk it`, clock >= distance / walk * 1.3, `{clock} s`)
end
check("the clock counts the handling", JobRules.footTime(300, 36) == JobRules.footTime(300, 0) + 36)
check("a rush (× 0.7) is shorter", JobRules.footTime(500, 0, 0.7) < JobRules.footTime(500, 0))

-- The XP: a ★ job's, about 70 – 90, and about 8 of them to level 2.
local xpLow, xpHigh = Levels.jobXp(1, 1, 0, false, true), Levels.jobXp(1, 3, 0, false, true)
check("the XP: about 70 – 90", xpLow >= 65 and xpHigh <= 95, `{xpLow} … {xpHigh}`)
local jobs = Levels.xpFor(2) / ((xpLow + xpHigh) / 2)
check("about 8 foot jobs to level 2", jobs >= 6 and jobs <= 10, jobs)

-- The rest of 5.0's numbers ----------------------------------------------------------------------------------------

check("a new store (everybody starts again)", Config.DataStoreName == "ZombieDelivery_v2")
check("a new player starts with $40", Config.StartMoney == 40)
local van = Config.Cars[1]
check("the Old Van: level 4, $1,800, the first car", van.id == "van" and van.level == 4 and van.price == 1800)
check("the car tiers: ★ 4, ★★ 5, ★★★ 6, ★★★★ 9", Config.Jobs.Tiers[1].level == 4 and Config.Jobs.Tiers[2].level == 5 and Config.Jobs.Tiers[3].level == 6 and Config.Jobs.Tiers[4].level == 9)
check("the licences: ★★★ 6 + 5 jobs, ★★★★ 9 + 10 jobs", Config.Jobs.Licences[1].level == 6 and Config.Jobs.Licences[1].jobs == 5
	and Config.Jobs.Licences[2].level == 9 and Config.Jobs.Licences[2].jobs == 10)
local lent = true
for _, def in Config.JobTypes do
	if def.vehicle and (def.level or 1) < 4 then
		lent = false
	end
end
check("a job that lends a company vehicle needs level 4+", lent)
check("level 2 tells of the bike shop, level 4 of the Old Van", string.find(Config.Levels.Rewards[2].text or "", "bike", 1, true) ~= nil
	and string.find(Config.Levels.Rewards[4].text or "", "Old Van", 1, true) ~= nil)
check("the light looks include the mail, documents, medicine, pizza, parcels and bread", Config.Cargo.LightLooks.mail and Config.Cargo.LightLooks.documents
	and Config.Cargo.LightLooks.medicine and Config.Cargo.LightLooks.pizza and Config.Cargo.LightLooks.parcel and Config.Cargo.LightLooks.bread)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
