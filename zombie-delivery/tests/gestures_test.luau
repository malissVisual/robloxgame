-- Logic test of the 5.7 gestures (shared/Gestures.luau, Config.Juice, Config.Body.Gestures) in the standalone Luau CLI:
-- every kind the game plays has a length and a pose, the weight starts and ends at rest, rises and falls smoothly and
-- stays within 0..1, the knock taps three times. 10.6: the city couriers' gestures are gone.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Gestures = require("./Gestures")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local J = Config.Juice
local KINDS = { "take", "knock", "pickup", "lift", "setdown" } -- (a visitor's, Gus's, the bends: Danny's lift and setting down)

for _, kind in KINDS do
	local total = Gestures.seconds(kind)
	check(`{kind} has a length`, total ~= nil and total > 0 and total < 3, total)
	if not total then
		continue
	end
	check(`{kind} at rest before it starts`, Gestures.weight(kind, -0.1) == 0 and Gestures.weight(kind, 0) == 0)
	check(`{kind} at rest from its end on`, Gestures.weight(kind, total) == 0 and Gestures.weight(kind, total + 1) == 0)
	check(`{kind} fully on in the middle`, Gestures.weight(kind, total / 2) > 0.99, Gestures.weight(kind, total / 2))
	local last, jump, inRange = 0, 0, true
	for i = 1, 200 do
		local w = Gestures.weight(kind, total * i / 200)
		inRange = inRange and w >= 0 and w <= 1
		jump = math.max(jump, math.abs(w - last))
		last = w
	end
	check(`{kind} weight within 0..1`, inRange)
	check(`{kind} weight changes smoothly`, jump < 0.12, jump)
	local pose = Gestures.pose(kind, total / 2)
	check(`{kind} has a pose`, pose ~= nil and pose.rs ~= nil and pose.re ~= nil)
	if pose then
		for joint, angles in pose do
			check(`{kind} {joint} has three angles`, #angles == 3)
		end
	end
	local right = Gestures.r6(kind, total / 2)
	check(`{kind} moves an R6 right arm`, right ~= nil)
end

check("an unknown gesture: no length, no pose, no weight", Gestures.seconds("dance") == nil and Gestures.pose("dance", 0.2) == nil
	and Gestures.weight("dance", 0.2) == 0)

-- Take: both hands forward, mirrored. The city's own are gone.
local take = Gestures.pose("take", 0.2) :: Gestures.Pose
check("take uses both hands, forward (mirrored)", take.ls ~= nil and take.rs[1] == take.ls[1] and take.rs[2] == -take.ls[2])
check("10.6: no city gesture (wave, give, receive, bag, throw, vest, sling)", (function(): boolean
	for _, kind in { "wave", "give", "receive", "bag", "throw", "vest", "sling", "unsling" } do
		if Gestures.pose(kind, 0.2) ~= nil then
			return false
		end
	end
	return true
end)())

-- The knock: three taps in time with the sound, then still.
local taps, was = 0, false
for i = 0, 300 do
	local t = J.Gestures.knock * i / 300
	local pose = Gestures.pose("knock", t) :: Gestures.Pose
	local hit = pose.rs[1] > 63
	if hit and not was then
		taps += 1
	end
	was = hit
end
check("three knocks", taps == 3, taps)
check("the knocks fit in the gesture", J.KnockGap * 3 <= J.Gestures.knock)

-- The Juice numbers.
check("volumes within 0..1", J.StepVolume <= 1 and J.CoinVolume <= 1)
check("a step every few studs", J.StepStride > 2 and J.StepStride < 10 and J.StepMinSpeed > 0)
check("the money counts up quickly", J.CountUpSeconds > 0 and J.CountUpSeconds <= 1.5)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(failures .. " CHECK(S) FAILED")
end
