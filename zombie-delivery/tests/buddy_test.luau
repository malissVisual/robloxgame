-- Logic test of the admin's test buddies (shared/BuddyBrain.luau, Config.Buddy) in the standalone Luau CLI: their
-- places round the owner, follow / stay / guard, the walk-stand hysteresis, the run, the teleport, being stuck, the
-- seat they take and how they get in, the hit chance and the cap.
-- Run: python3 tests/run_tests.py [path to the luau binary].

local Config = require("./Config")
local BuddyBrain = require("./BuddyBrain")

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

local B = Config.Buddy

-- The numbers ---------------------------------------------------------------------

check("3 buddies at most", B.Max == 3, B.Max)
check("the run is faster than the walk", B.RunSpeed > B.Speed)
check("a walking buddy stops nearer than a standing one sets off", B.Arrive < B.Restart)
check("it follows closer than it runs", B.FollowDistance < B.RunFrom)
check("the teleport is far beyond the follow", B.TeleportDistance > B.RunFrom * 3)
check("it looks for a way round before it gives up and appears", B.StuckPath < B.StuckSeconds)
check("a respawn of about 10 s", B.RespawnSeconds >= 5 and B.RespawnSeconds <= 20)
check("the loop is throttled (0.1 – 0.5 s)", B.Tick >= 0.1 and B.Tick <= 0.5)
check("it shoots slower than a pistol (3 a second)", 1 / B.FireEvery < 3)
check("its range is a pistol's or less", B.Range <= 140)
check("the guard steps out less than it shoots", B.GuardLeash < B.Range)

-- The places round the owner ----------------------------------------------------------

do
	-- owner at (100, 50) looking along +Z
	local x, z = BuddyBrain.place(1, 1, 100, 50, 0, 1)
	check("one buddy: right behind the owner", near(x, 100, 1e-4) and near(z, 50 - B.FollowDistance, 1e-4), `{x}, {z}`)
	local seen: { string } = {}
	for i = 1, 3 do
		local px, pz = BuddyBrain.place(i, 3, 100, 50, 0, 1)
		local d = math.sqrt((px - 100) ^ 2 + (pz - 50) ^ 2)
		check(`buddy {i} of 3: FollowDistance from the owner`, near(d, B.FollowDistance, 1e-4), d)
		check(`buddy {i} of 3: behind the owner`, pz < 50, pz)
		table.insert(seen, `{math.floor(px * 10)},{math.floor(pz * 10)}`)
	end
	check("three buddies: three different places", seen[1] ~= seen[2] and seen[2] ~= seen[3] and seen[1] ~= seen[3])
	local lx, _ = BuddyBrain.place(1, 2, 0, 0, 0, 1)
	local rx, _ = BuddyBrain.place(2, 2, 0, 0, 0, 1)
	check("two buddies: one to each side", lx * rx < 0, `{lx} / {rx}`)
	local tx, tz = BuddyBrain.place(1, 1, 0, 0, 1, 0)
	check("the places turn with the owner (looking along +X: behind is -X)", near(tx, -B.FollowDistance, 1e-4) and near(tz, 0, 1e-4), `{tx}, {tz}`)
	local zx, zz = BuddyBrain.place(1, 1, 0, 0, 0, 0)
	check("no look direction: still a place", zx == zx and zz == zz)
end

-- Follow ------------------------------------------------------------------------------

local function follow(x: number, z: number, moving: boolean, ox: number?, oz: number?): BuddyBrain.Decision
	local px, pz = nil, nil
	if ox and oz then
		px, pz = BuddyBrain.place(1, 1, ox, oz, 0, 1)
	end
	return BuddyBrain.decide({ mode = "follow", x = x, z = z, moving = moving, ownerX = ox, ownerZ = oz, placeX = px, placeZ = pz })
end

do
	local placeZ = -B.FollowDistance
	local d = follow(0, placeZ, false, 0, 0)
	check("at its place: it stands", d.action == "stand", d.action)
	d = follow(0, placeZ - (B.Restart - 1), false, 0, 0)
	check("a standing buddy a little off its place stays standing (no jitter)", d.action == "stand", d.action)
	d = follow(0, placeZ - (B.Restart - 1), true, 0, 0)
	check("a walking buddy that far off walks on", d.action == "move" and not d.run, d.action)
	d = follow(0, placeZ - (B.Restart + 1), false, 0, 0)
	check("its place moved on: it sets off", d.action == "move" and near(d.x, 0, 1e-4) and near(d.z, placeZ, 1e-4), `{d.action} {d.x},{d.z}`)
	d = follow(0, placeZ - (B.Arrive - 0.5), true, 0, 0)
	check("a walking buddy at its place stops", d.action == "stand", d.action)
	d = follow(0, -(B.RunFrom + 10), false, 0, 0)
	check("far from the owner: it runs", d.action == "move" and d.run, d.action)
	d = follow(0, -14, false, 0, 0)
	check("near the owner: it walks", d.action == "move" and not d.run, `{d.action} {d.run}`)
	d = follow(0, -(B.TeleportDistance + 5), false, 0, 0)
	check("too far: it appears at its place", d.action == "teleport" and near(d.z, placeZ, 1e-4), `{d.action} {d.z}`)
	d = follow(0, -50, true, nil, nil)
	check("no owner to follow (dead, no seat in the car): it waits", d.action == "stand", d.action)
end

-- Stay ------------------------------------------------------------------------------

do
	local d = BuddyBrain.decide({ mode = "stay", x = 0, z = 0, moving = true, ownerX = 500, ownerZ = 500, placeX = 495, placeZ = 495 })
	check("stay: it stands even when the owner is far", d.action == "stand", d.action)
end

-- Guard -----------------------------------------------------------------------------

local function guard(x: number, z: number, moving: boolean, ex: number?, ez: number?): BuddyBrain.Decision
	return BuddyBrain.decide({ mode = "guard", x = x, z = z, moving = moving, homeX = 0, homeZ = 0, enemyX = ex, enemyZ = ez })
end

do
	local d = guard(0, 0, false, nil, nil)
	check("guard at its spot, nobody near: it stands", d.action == "stand", d.action)
	d = guard(20, 0, false, nil, nil)
	check("guard off its spot: it walks back", d.action == "move" and near(d.x, 0) and near(d.z, 0), `{d.action} {d.x},{d.z}`)
	d = guard(0, 0, false, B.GuardCloseIn - 5, 0)
	check("an enemy close: it stands and fights", d.action == "stand", d.action)
	d = guard(0, 0, false, B.Range - 5, 0)
	check("an enemy far but within range of the spot: it steps toward it", d.action == "move" and d.x > 0, `{d.action} {d.x}`)
	check("... never farther than the leash", d.x <= B.GuardLeash + 1e-6, d.x)
	d = guard(0, 0, false, B.Range + 40, 0)
	check("an enemy out of range of the spot: it stays", d.action == "stand", d.action)
	d = BuddyBrain.decide({ mode = "guard", x = 3, z = 4, moving = false })
	check("guard without a spot: it stands", d.action == "stand", d.action)
end

-- Stuck -----------------------------------------------------------------------------

do
	local dt = B.Tick
	local s = 0
	for _ = 1, 10 do
		s = BuddyBrain.stuck(s, 0.05, dt, true)
	end
	check("not moving while it should: stuck time adds up", near(s, 10 * dt, 1e-6), s)
	check("past StuckPath after 10 ticks", s >= B.StuckPath)
	s = BuddyBrain.stuck(s, B.Speed * dt, dt, true)
	check("moving again: no longer stuck", s == 0, s)
	check("a buddy that stands is never stuck", BuddyBrain.stuck(3, 0, dt, false) == 0)
end

-- Seats and boarding -------------------------------------------------------------------

check("the first free seat", BuddyBrain.pickSeat({ false, true, true }) == 2)
check("no free seat: none", BuddyBrain.pickSeat({ false, false }) == nil)
check("a car with no passenger seats: none", BuddyBrain.pickSeat({}) == nil)
check("near a standing car: it gets in", BuddyBrain.boarding(B.BoardReach - 5, 0, 0) == "sit")
check("near a moving car: it walks to it", BuddyBrain.boarding(B.BoardReach - 5, Config.Cargo.BoardMaxSpeed + 10, 0) == "walk")
check("farther than BoardReach: it walks to the car", BuddyBrain.boarding(B.BoardReach + 20, 0, 0) == "walk")
check("left far behind: it appears in the seat", BuddyBrain.boarding(B.TeleportDistance + 1, 60, 0) == "sit")
check("stuck on the way: it appears in the seat", BuddyBrain.boarding(B.BoardReach + 20, 0, B.StuckSeconds) == "sit")

-- Shots and the cap ---------------------------------------------------------------------

check("a standing target: Accuracy", near(BuddyBrain.hitChance(0), B.Accuracy))
check("a fast target is harder", BuddyBrain.hitChance(60) < BuddyBrain.hitChance(0))
check("never below 30 % of Accuracy", near(BuddyBrain.hitChance(1000), B.Accuracy * 0.3))
check("one more by default", BuddyBrain.allowed(0, nil) == 1)
check("capped at Max", BuddyBrain.allowed(1, 10) == B.Max - 1)
check("none past Max", BuddyBrain.allowed(B.Max, 2) == 0)
check("a negative count makes none", BuddyBrain.allowed(0, -3) == 0)
check("the modes", BuddyBrain.validMode("follow") and BuddyBrain.validMode("stay") and BuddyBrain.validMode("guard") and not BuddyBrain.validMode("dance") and not BuddyBrain.validMode(nil))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
