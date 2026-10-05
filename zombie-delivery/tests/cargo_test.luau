-- Logic test of the cargo maths (shared/Economy.luau) and the job catalog (Config.Jobs, Config.Cargo): the pieces
-- split over the stops, the pay for what arrived, every business sends something that makes sense.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Economy = require("./Economy")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function sum(list: { number }): number
	local total = 0
	for _, n in list do
		total += n
	end
	return total
end

-- Splitting pieces --------------------------------------------------------------

local split = Economy.splitPieces(4, 3)
check("4 pieces over 3 stops", #split == 3 and split[1] == 2 and split[2] == 1 and split[3] == 1, table.concat(split, ","))
check("6 kids over 3 homes", table.concat(Economy.splitPieces(6, 3), ",") == "2,2,2")
check("a split keeps every piece", sum(Economy.splitPieces(7, 4)) == 7)
check("no stops, no split", #Economy.splitPieces(3, 0) == 0)

-- The ice cream truck empties evenly over its serve stops.
check("serve left at the start", Economy.serveLeft(3, 4, 0) == 3)
check("serve left after 2 of 4", Economy.serveLeft(3, 4, 2) == 2, Economy.serveLeft(3, 4, 2))
check("serve left at the end", Economy.serveLeft(3, 4, 4) == 0)
local served = 0
for n = 1, 4 do
	served += Economy.serveLeft(3, 4, n - 1) - Economy.serveLeft(3, 4, n)
end
check("every ice box is sold once", served == 3, served)

-- Pay and time ------------------------------------------------------------------

check("all pieces pay in full", Economy.cargoPay(400, 4, 4) == 400)
check("half the pieces pay half", Economy.cargoPay(400, 2, 4) == 200)
check("nothing arrived pays nothing", Economy.cargoPay(400, 0, 4) == 0)
check("no pieces = the full pay", Economy.cargoPay(300, 0, 0) == 300)
check("carrying adds time per piece", Economy.handlingTime("carry", 3) == 3 * Config.Cargo.TimePerPiece.carry)
check("serving adds no piece time", Economy.handlingTime("serve", 3) == 0)
check("unknown handling adds nothing", Economy.handlingTime("teleport", 3) == 0)

-- The catalog ---------------------------------------------------------------------

local CARRY_KINDS = { crate = true, ammo = true, sack = true, barrel = true, icebox = true, furniture = true, soup = true }

check("every tier has a business", (function()
	for tier = 1, #Config.Jobs.Tiers do
		local found = false
		for _, business in Config.Jobs.Businesses do
			if table.find(business.tiers, tier) then
				found = true
			end
		end
		if not found then
			return false
		end
	end
	return true
end)())

check("businesses send 1 - 3 pieces you can carry, to somebody", (function()
	for _, business in Config.Jobs.Businesses do
		local low, high = business.pieces[1], business.pieces[2]
		if not CARRY_KINDS[business.kind] or low < 1 or high > 3 or low > high or #business.receivers == 0 then
			print("  bad business " .. business.id)
			return false
		end
	end
	return true
end)())

check("special jobs have a piece kind, people and a handling", (function()
	local modes = { carry = true, lead = true, board = true, serve = true, pallet = true } -- 4.0: pallet (the Freight Run)
	for _, jobType in Config.JobTypes do
		if not Config.Cargo.Kinds[jobType.itemKind] or not Config.Jobs.People[jobType.id] then
			print("  bad job type " .. jobType.id)
			return false
		end
		if not modes[jobType.load] or not modes[jobType.unload] or jobType.items < 1 then
			print("  bad handling " .. jobType.id)
			return false
		end
	end
	return true
end)())

check("employer guns are earned, not sold", (function()
	for _, employer in Config.Employers do
		if employer.weapon then
			local weapon = Economy.findWeapon(employer.weapon)
			if not weapon or weapon.earned ~= employer.id or (employer.weaponAt or 0) < 1 then
				return false
			end
		end
	end
	return true
end)())

check("foot waves for every tier", #Config.Cargo.FootWaves >= #Config.Jobs.Tiers)

-- 3.2, the back that opens (server/Vehicles.luau, server/Cargo.luau) ---------------------------------------------
-- Per stop it adds: put the piece down, open the back, pick the piece up again, close the back. Four short holds:
-- with the walking it stays a few seconds a stop, not a minute.
check("the back's extra steps are quick holds", Config.Cargo.HoldDuration > 0 and Config.Cargo.HoldDuration * 4 <= 1.2, Config.Cargo.HoldDuration)
check("the back is opened standing (load speed)", Config.Cargo.MaxCarSpeed > 0 and Config.Cargo.MaxCarSpeed <= 10, Config.Cargo.MaxCarSpeed)
check("the extra steps fit the time per piece", Config.Cargo.TimePerPiece.carry >= 4 * Config.Cargo.HoldDuration + 3, Config.Cargo.TimePerPiece.carry)

-- 3.2, the pair twist (Info.pair): two people carry one piece side by side, the partner a few studs away.
local duo = Config.Missions.Duo
check("pair range fits two carriers", duo ~= nil and duo.PairRange >= 6 and duo.PairRange <= 20, duo and duo.PairRange)
check("the pair twist exists", Config.Missions.Twists.pair ~= nil)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
