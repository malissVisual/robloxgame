-- Logic test of 3.7's carrying and car doors (Config.Cargo): which pieces go two at a time (LightLooks, the looks of
-- real cargo, never a heavy one or a person), the two-piece step, and door numbers that keep the driver's E off the
-- passenger side (server/Cargo.luau, server/Vehicles.luau, client/CarVisuals.luau use them).
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local Tuning = Config.Cargo

-- Every look a piece can have: the special jobs' kinds and the ordinary deliveries' businesses.
local looks: { [string]: boolean } = {}
for _, kind in Tuning.Kinds do
	looks[kind.look] = true
end
for _, business in Config.Jobs.Businesses do
	looks[business.look] = true
end

-- Two in your hands -------------------------------------------------------------

check("two pieces at most", Tuning.HandsMax == 2, Tuning.HandsMax)
check("some looks are light", next(Tuning.LightLooks) ~= nil)
check("every light look is a real piece's look", (function()
	for look in Tuning.LightLooks do
		if not looks[look] then
			print("  unknown look " .. look)
			return false
		end
	end
	return true
end)())

-- Heavy, awkward or alive: always one at a time.
local HEAVY = {
	"crate", "tools", "ammo", "barrel", "icebox", "vaccine", "furniture", "gold", "water", "generator", "battery", "tnt",
	"electronics", "weapons", "painting", "tires", "horse", "kid", "patient", "survivor",
}
check("heavy pieces and people go one at a time", (function()
	for _, look in HEAVY do
		if Tuning.LightLooks[look] then
			print("  light but heavy: " .. look)
			return false
		end
	end
	return true
end)())
check("the pizzas, parcels and mail are light", Tuning.LightLooks.pizza == true and Tuning.LightLooks.parcel == true and Tuning.LightLooks.mail == true)
check("an ordinary delivery sends light pieces", (function()
	for _, business in Config.Jobs.Businesses do
		if Tuning.LightLooks[business.look] and business.pieces[2] and business.pieces[2] >= 2 then
			return true
		end
	end
	return false
end)())
check("two pieces walk slower than the walk", Tuning.TwoPieceSpeed > 3 and Tuning.TwoPieceSpeed < Config.Movement.Walk, Tuning.TwoPieceSpeed)

-- The doors ---------------------------------------------------------------------

-- The prompts stand DoorStandOut (1.4) studs outside the body (server/Vehicles.luau doorsOf). On the narrowest body (the courier
-- van, 6.2 wide) somebody standing against the passenger side (at least 0.5 out) is 3.1 + 1.4 + 3.1 + 0.5 = 8.1
-- studs from the driver's prompt: the reach must stay under that, so the driver's E never shows there.
local NARROWEST = 6.2
local apart = NARROWEST / 2 + Tuning.DoorStandOut + NARROWEST / 2 + 0.5
check("the driver's E stays on the driver's side", Tuning.DoorReach < apart and Tuning.DoorReach >= 3, `{Tuning.DoorReach} vs {apart}`)
check("a door swings out, not round", Tuning.DoorSwing >= 45 and Tuning.DoorSwing <= 90, Tuning.DoorSwing)
-- 3.10: the door follows getting in and out (tests/boarding_test.luau): open quickly, shut quickly behind you.
check("a door swings open and shut quickly", Tuning.DoorSwingSeconds > 0 and Tuning.DoorSwingSeconds <= 0.3 and Tuning.DoorShutSeconds > 0 and Tuning.DoorShutSeconds <= 0.3, `{Tuning.DoorSwingSeconds} / {Tuning.DoorShutSeconds}`)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
