-- 7.0, the depot's helper ("Danny from the depot"): his decisions (shared/MoveHelperBrain.luau, pure). Who has him,
-- which lift he comes to help with, when he runs from a zombie, what he does now (the priority list), the van's back
-- (he opens it), his speeds (slower than a player, a sprint to your lift), stuck (9.3: progress, his ways out), the far end of
-- your piece (on the floor there), the doorways he keeps out of and his words. tests/movehelper_runtime_test.luau and
-- tests/movehelper_art_runtime_test.luau run the server side. 8.3 Danny for hire: the price (the house's pieces), the
-- hire's check (the crew, once, the money), a click on a piece (onto his list, off it, every refusal), his list's next
-- piece (in order, the first that fits, a two-person one he waits at), its words and markers, the van's seat (which
-- one, when he gets out), your call (in place, the last resort's clock, walking away, idle) and the priority list.
local Brain = require("./MoveHelperBrain")
local Config = require("./Config")
local Rules = require("./MovingRules")
local CarryGrip = require("./CarryGrip")

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

local H = Config.MoveHelper
local WALK = Config.Movement.Walk

-- Who gets him -------------------------------------------------------------------------------------------------------------

check("a crew of one gets him", Brain.wanted(1))
check("two don't (Duo is off)", not Brain.wanted(2) and H.Duo == false)
check("nobody, three, four: no", not Brain.wanted(0) and not Brain.wanted(3) and not Brain.wanted(4))
H.Duo = true
check("Duo on: two get him too", Brain.wanted(2) and Brain.wanted(1) and not Brain.wanted(3))
H.Duo = false
H.Solo = false
check("Solo off: nobody gets him", not Brain.wanted(1))
H.Solo = true
check("8.3 hired: he stays with any crew of one or more (paid for the move), never with nobody", Brain.wanted(2, true) and Brain.wanted(4, true)
	and Brain.wanted(1, true) and not Brain.wanted(0, true) and not Brain.wanted(2, false))

-- 8.3 the hire: its price, its check -------------------------------------------------------------------------------------------

local HIRE = H.Hire
check("8.3 the hire: Base + PerPiece a piece (the sandbox: $50 + $5)", HIRE.Base == 50 and HIRE.PerPiece == 5 and HIRE.Round == 10 and HIRE.Min == 100 and HIRE.Max == 400)
check("…the Old Farmstead's 20-28 pieces: $150-$190 (a third of the start money, two minutes of a first haul's income)", Brain.hirePrice(20) == 150
	and Brain.hirePrice(24) == 170 and Brain.hirePrice(28) == 190 and Brain.hirePrice(28) < Config.Sandbox.StartMoney / 2)
check("…a bigger house costs more (the Alpine Lodge's 40: $250), never past Max", Brain.hirePrice(40) == 250 and Brain.hirePrice(40) > Brain.hirePrice(28)
	and Brain.hirePrice(500) == HIRE.Max)
check("…a small house: Min at least; whole Round dollars", Brain.hirePrice(6) == HIRE.Min and Brain.hirePrice(0) == HIRE.Min and Brain.hirePrice(23) == 170
	and Brain.hirePrice(23) % HIRE.Round == 0)
check("…junk: no pieces (Min)", Brain.hirePrice(nil) == HIRE.Min and Brain.hirePrice(0 / 0) == HIRE.Min and Brain.hirePrice("9") == HIRE.Min and Brain.hirePrice(-4) == HIRE.Min)
local ok, why = Brain.hireCheck(true, false, 500, 170)
check("8.3 a crew player with the money hires him", ok and why == nil)
ok, why = Brain.hireCheck(true, false, 169, 170)
check("…not enough money: refused (money)", not ok and why == "money")
ok, why = Brain.hireCheck(true, false, 170, 170)
local ok2, why2 = Brain.hireCheck(true, false, nil, 170)
check("…the price exactly is enough; no money read (nil, NaN): refused", ok and why == nil and not ok2 and why2 == "money" and not (Brain.hireCheck(true, false, 0 / 0, 170)))
ok, why = Brain.hireCheck(true, true, 9999, 170)
check("…once a move: hired already (hired)", not ok and why == "hired")
ok, why = Brain.hireCheck(false, false, 9999, 170)
check("…a player not of the move's crew: refused (crew), before anything else", not ok and why == "crew" and select(2, Brain.hireCheck(false, true, 0, 170)) == "crew")
check("8.3 the money's words", Brain.money(170) == "$170" and Brain.money(1234) == "$1,234")

-- 8.3 a click on a piece: onto his list, off it -----------------------------------------------------------------------------

local function assign(fields: { [string]: any }): string
	local a: Brain.Assign = { crew = true, hired = true, mine = true, state = "home", held = false, his = false, queued = false, count = 0, near = true, clipboard = true }
	for key, value in fields do
		(a :: any)[key] = value
	end
	return Brain.assignCheck(a)
end
check("8.3 a piece in the house, Danny hired: onto his list (add)", assign({}) == "add" and assign({ state = "ground" }) == "add")
check("…a click on a piece of his list: off it again (remove), wherever it is now", assign({ queued = true }) == "remove" and assign({ queued = true, near = false }) == "remove")
check("…not of the move's crew: refused first (crew)", assign({ crew = false, queued = true }) == "crew")
check("…not this move's piece (another move's model): refused (piece)", assign({ mine = false }) == "piece")
check("…not hired: hire him first (hire)", assign({ hired = false }) == "hire" and assign({ hired = false, queued = true }) == "hire")
check("…too far to see it (ClickReach): refused (far)", assign({ near = false }) == "far")
check("8.3 review: his card's reach (CardReach) at least a click's (ClickReach), a little slack past where it opened (CardSlack): a click on him from afar never opens a card that shuts at once",
	H.CardReach >= H.ClickReach and H.CardSlack > 0)
check("…in his arms already: (his)", assign({ his = true, state = "carried", held = true }) == "his")
check("…in the van: (van); home or lost: (gone)", assign({ state = "truck" }) == "van" and assign({ state = "delivered" }) == "gone" and assign({ state = "lost" }) == "gone")
check("…somebody holds it: (held)", assign({ state = "carried", held = true }) == "held" and assign({ held = true }) == "held")
check("…his list full (Queue 6): (full); one less: add", assign({ count = H.Queue }) == "full" and assign({ count = H.Queue - 1 }) == "add" and H.Queue == 6)
-- 8.5 orders mode (shared/ClipboardRules.luau, server/Clipboard.luau): a piece goes to him only from a player whose
-- clipboard is out
check("8.5 the clipboard away: refused (clipboard), never added, never taken back; out: add / remove", assign({ clipboard = false }) == "clipboard"
	and assign({ clipboard = false, queued = true }) == "clipboard" and assign({ clipboard = true }) == "add" and assign({ clipboard = true, queued = true }) == "remove")
check("…but the crew, the piece and the hire come first (no clipboard to take out before he is hired)", assign({ clipboard = false, crew = false }) == "crew"
	and assign({ clipboard = false, mine = false }) == "piece" and assign({ clipboard = false, hired = false }) == "hire")
check("…and before the rest (far, in the van, full: the clipboard first)", assign({ clipboard = false, near = false }) == "clipboard"
	and assign({ clipboard = false, state = "truck" }) == "clipboard" and assign({ clipboard = false, count = H.Queue }) == "clipboard")
check("8.3 a piece of his list stays his while it is home or on the ground and nobody holds it", Brain.keepQueued("home", false) and Brain.keepQueued("ground", false)
	and not Brain.keepQueued("carried", true) and not Brain.keepQueued("home", true) and not Brain.keepQueued("truck", false) and not Brain.keepQueued("delivered", false))

-- 8.3 his list's next piece --------------------------------------------------------------------------------------------------

local function queued(spot: number, class: string, fits: boolean?): Brain.Queued
	return { spot = spot, class = class, fits = fits ~= false }
end
local spotNext, pair, full = Brain.nextQueued({ queued(4, "hand"), queued(2, "both"), queued(7, "pair") })
check("8.3 in his list's order: the first one (the lamp)", spotNext == 4 and not pair and not full)
spotNext, pair, full = Brain.nextQueued({ queued(4, "hand", false), queued(2, "both"), queued(7, "pair") })
check("…one that no longer fits the van is skipped (the next that fits)", spotNext == 2 and not pair and not full)
spotNext, pair, full = Brain.nextQueued({ queued(7, "pair"), queued(4, "hand") })
check("…a two-person piece first: that one, pair (he waits at it for you)", spotNext == 7 and pair and not full)
spotNext, pair, full = Brain.nextQueued({ queued(4, "hand", false), queued(7, "pair", false) })
check("…none fits: none, the van full for his list", spotNext == nil and not pair and full)
spotNext, pair, full = Brain.nextQueued({})
check("…an empty list: none, not full", spotNext == nil and not pair and not full)
check("8.3 his list in words", Brain.queueText(0) == "Nothing to carry" and Brain.queueText(1) == "1 piece to carry" and Brain.queueText(3) == "3 pieces to carry"
	and Brain.queueText(nil) == "Nothing to carry")
check("8.3 his status: for hire (the price), hired (his list · what he does)", Brain.status(false, 170, nil, nil) == "For hire · $170 this move"
	and Brain.status(true, 170, 2, "Carrying the Lamp to the van") == "2 pieces to carry · Carrying the Lamp to the van" and Brain.status(true, 0, 0, "") == "Nothing to carry")
-- 9.0 (the owner's screenshot: "DANNY · Nothing to carry" over "Take out your clipboard (Q) to give him pieces" while his
-- bubble said "🤝 Carrying: Sofa with you")
do
	local holdLine = Brain.doing("hold", "Sofa")
	local holdBubble = Brain.bubble("hold", "Sofa")
	check("9.0 idle: waiting by the van (its line and its bubble), the van full, for hire (with its price), staying out, nothing",
		Brain.idle(Brain.doing("wait")) and Brain.idle(Brain.bubble("wait")) and Brain.idle(Brain.bubble("wait", nil, true))
		and Brain.idle(Brain.bubble("offer", nil, false, 170)) and Brain.idle(Brain.doing("stay")) and Brain.idle(nil) and Brain.idle(""))
	check("…not idle: carrying a piece with you, to the van, going for one", not Brain.idle(holdLine) and not Brain.idle(holdBubble)
		and not Brain.idle(Brain.bubble("deliver", "Lamp")) and not Brain.idle(Brain.doing("fetch", "Lamp")))
	check("9.0 his status line's title: his list empty, carrying the Sofa with you: the bubble's words (never \"Nothing to carry\")",
		Brain.title(0, holdBubble) == "Carrying: Sofa with you" and Brain.title(nil, holdBubble) == "Carrying: Sofa with you", Brain.title(0, holdBubble))
	check("…his list with pieces: his list; idle: his list as ever", Brain.title(2, holdBubble) == "2 pieces to carry"
		and Brain.title(0, Brain.bubble("wait")) == "Nothing to carry" and Brain.title(0, nil) == "Nothing to carry")
	check("…his card's status: his list empty, carrying with you: what he does alone", Brain.status(true, 0, 0, holdLine) == "Carrying the Sofa with you"
		and Brain.status(true, 0, 0, Brain.doing("wait")) == "Nothing to carry · Waiting at the van", Brain.status(true, 0, 0, holdLine))
end
check("8.3 the marker over a piece of his list: its number, or he needs you", Brain.markText(2, false) == "🧑‍🔧 Danny · 2" and Brain.markText(1, true) == "🙋 Danny needs you")

-- 8.3 the van's seat ---------------------------------------------------------------------------------------------------------

check("8.3 the first seat nobody sits in; every one taken: none (he follows on foot)", Brain.pickSeat({ false }) == 1 and Brain.pickSeat({ true, false }) == 2
	and Brain.pickSeat({ true }) == nil and Brain.pickSeat({}) == nil)
check("8.3 seated: out when nobody drives and the van stands", Brain.getOut(false, true, true) and not Brain.getOut(true, true, true) and not Brain.getOut(false, false, true)
	and not Brain.getOut(true, false, true))
check("…at once when the van is wrecked or gone (moving or not)", Brain.getOut(true, false, false) and Brain.getOut(false, false, false))

-- 8.5 his way to the van's door: round the van, never through it (the owner: "Danny got a bit stuck under the car") -----

do
	local m, edge = H.RideMargin, 0.05
	local hx, hz = 4, 11 -- (the Sprinter's footprint: 8 × 22)
	local gx, gz = hx + H.RideStand, -5.75 -- (his spot at its passenger door)
	check("8.5 his spot at the door is out of the margin he keeps (and of the pathfinding's reach round the hull)", H.RideStand > m and m > H.PathRadius)
	local x, z, length = Brain.roundVan(14, 0, gx, gz, hx, hz, 0)
	check("8.5 the straight way keeps RideMargin off the van: straight to his spot", near(x, gx) and near(z, gz) and near(length, math.sqrt((14 - gx) ^ 2 + gz ^ 2)),
		`{x} {z} {length}`)
	x, z, length = Brain.roundVan(4, 14.6, gx, gz, hx, hz, 0)
	check("…from behind the van by its back corner (where he waits; the straight way would scrape its side): round that corner first",
		near(x, hx + m + edge) and near(z, hz + m + edge) and near(length, math.sqrt((hx + m + edge - 4) ^ 2 + (14.6 - hz - m - edge) ^ 2)
		+ math.sqrt((gx - hx - m - edge) ^ 2 + (gz - hz - m - edge) ^ 2)), `{x} {z} {length}`)
	x, z = Brain.roundVan(-14, -8, gx, gz, hx, hz, 0)
	check("…from its other side, toward the front: round the front (the shorter way)", near(x, -(hx + m + edge)) and near(z, -(hz + m + edge)), `{x} {z}`)
	x, z = Brain.roundVan(-14, 8, gx, gz, hx, hz, 0)
	check("…toward the back: round the back", near(x, -(hx + m + edge)) and near(z, hz + m + edge), `{x} {z}`)
	x, z = Brain.roundVan(hx + m - 0.6, hz + m + 0.6, gx, gz, hx, hz, H.RideCorner)
	check("…a corner within RideCorner: on to the next point (no stop at it)", near(x, gx) and near(z, gz), `{x} {z}`)
	x, z = Brain.roundVan(hx + 1, 0, gx, gz, hx, hz, 0)
	check("…within the margin (by its side): straight out of it first", near(x, hx + m + edge) and near(z, 0), `{x} {z}`)
	x, z = Brain.roundVan(-1, 2, gx, gz, hx, hz, 0)
	check("…even from inside its footprint: out of the nearer side, never on through it", near(x, -(hx + m + edge)) and near(z, 2), `{x} {z}`)
	-- walked from all round the van (half a stud a step toward the next point): never within a stud of its footprint (his
	-- body), always at his spot in the end
	local worst, arrived = math.huge, 0
	for angle = 0, 345, 15 do
		local px, pz = math.cos(math.rad(angle)) * 18, math.sin(math.rad(angle)) * 24
		for _ = 1, 400 do
			local nx, nz = Brain.roundVan(px, pz, gx, gz, hx, hz, H.RideCorner)
			local dx, dz = nx - px, nz - pz
			local d = math.sqrt(dx * dx + dz * dz)
			if d < 0.05 then
				break
			end
			local step = math.min(0.5, d)
			px, pz = px + dx / d * step, pz + dz / d * step
			worst = math.min(worst, math.max(math.abs(px) - hx, math.abs(pz) - hz))
		end
		if math.abs(px - gx) < 0.06 and math.abs(pz - gz) < 0.06 then
			arrived += 1
		end
	end
	check("…walked to his spot from all round the van: always there, never within a stud of its footprint", arrived == 24 and worst > 1, `{arrived} {worst}`)
	local a = Brain.newApproach()
	local fade = false
	for step = 1, 300 do -- (30 s coming closer, from 120 studs off)
		fade = fade or Brain.rideBlink(a, 120 - step * 0.4, 0.1)
	end
	check("8.5 his walk to the van to ride, coming closer: never the fade into the seat (even a long one)", not fade)
	a = Brain.newApproach()
	Brain.rideBlink(a, 10, 0.1)
	local steps = 0
	repeat
		steps += 1
	until Brain.rideBlink(a, 10 - H.CallGain * 0.5, 0.1) or steps > 1000
	check("…no closer by CallGain studs for RideBlink s (his way blocked, the van rolling on): the last resort", near(steps * 0.1, H.RideBlink, 0.11), steps * 0.1)
	check("…RideFar studs or more to go (driven off without him): the last resort at once", Brain.rideBlink(Brain.newApproach(), H.RideFar, 0.1)
		and not Brain.rideBlink(Brain.newApproach(), H.RideFar - 1, 0.1))
	check("…more patient than your call's (CallBlink)", H.RideBlink > H.CallBlink)
end
-- 8.5.1 his outline guard on every way outside (the owner: "Danny STILL goes through it") ------------------------------
do
	local hx, hz, pad = 4, 11, H.RideHug
	check("8.5.1 RideHug: his body's half width and a hair, inside the ride's margin", pad > 1 and pad < H.RideMargin)
	check("8.5.1 a way across the van's outline (the straight line from its passenger door to behind it, scraping its back corner)",
		Brain.crossesVan(hx + H.RideStand, -5.75, 4, 14.6, hx, hz, pad) and not Brain.crossesVan(hx + H.RideStand, -5.75, hx + pad + 0.1, 14.6, hx, hz, pad))
	check("…a way along its side, outside the outline, or from inside it out", not Brain.crossesVan(hx + pad + 0.01, -20, hx + pad + 0.01, 20, hx, hz, pad)
		and Brain.crossesVan(0, 0, 20, 0, hx, hz, pad))
	local x, z = Brain.outOfVan(0.8, 4, hx, hz, pad)
	check("8.5.1 out of the van: through its nearer side, a hair past the outline", near(x, hx + pad + 0.05) and near(z, 4), `{x} {z}`)
	x, z = Brain.outOfVan(-1, 10.5, hx, hz, pad)
	check("…by its back: out of the back", near(x, -1) and near(z, hz + pad + 0.05), `{x} {z}`)
	x, z = Brain.outOfVan(-1, 10.5, hx, hz, pad, true)
	check("…sideways (a van driving along its length): its side, the nearer one", near(x, -(hx + pad + 0.05)) and near(z, 10.5), `{x} {z}`)
	x, z = Brain.outOfVan(hx + pad + 1, 3, hx, hz, pad)
	check("…a point outside it as it is", near(x, hx + pad + 1) and near(z, 3))
	local gx, gz = 1.5, hz + 2.1 -- (the spot behind its back he loads from: nearer the van than RideMargin)
	x, z = Brain.roundVan(hx + 3, -5, gx, gz, hx, hz, 0, 2.0)
	check("8.5.1 roundVan with a margin of its own: round the corner that far out (a goal nearer the van than RideMargin)",
		near(x, hx + 2.05) and near(z, hz + 2.05), `{x} {z}`)
	x, z = Brain.roundVan(hx + 3, -5, gx, gz, hx, hz, 0)
	check("…RideMargin's own: no way round to a goal within it (straight: the guard gives it the goal's own margin)", near(x, gx) and near(z, gz), `{x} {z}`)
end
-- The way ------------------------------------------------------------------------------------------------------------------

local doors: Brain.Doors = { outX = 100, outZ = 0, inX = 5000, inZ = 0 }
check("the same world: straight", near(Brain.routeCost(false, 100, 30, false, 100, 70, doors), 40))
check("inside to the street: to the exit, from the front door", near(Brain.routeCost(true, 5000, 10, false, 100, 20, doors), 10 + 20))
check("the street to inside: to the front door, from the exit", near(Brain.routeCost(false, 100, 5, true, 5000, 12, doors), 5 + 12))
check("inside, from room to room", near(Brain.routeCost(true, 5000, 0, true, 5003, 4, doors), 5))

-- Which lift -----------------------------------------------------------------------------------------------------------

local function lift(spot: number, cost: number, extra: { [string]: any }?): Brain.Lift
	local l: Brain.Lift = { spot = spot, class = "pair", state = "carried", helped = false, crew = true, cost = cost, gaveUp = false }
	for key, value in extra or {} do
		(l :: any)[key] = value
	end
	return l
end
check("a crew player drags a pair piece alone: he comes", Brain.pickLift({ lift(3, 20) }) == 3)
check("the nearer of two", Brain.pickLift({ lift(3, 20), lift(6, 12) }) == 6)
check("not one somebody holds the other end of", Brain.pickLift({ lift(3, 20, { helped = true }) }) == nil)
check("not a stranger's", Brain.pickLift({ lift(3, 20, { crew = false }) }) == nil)
check("not one whose take failed a moment ago", Brain.pickLift({ lift(3, 20, { gaveUp = true }) }) == nil)
check("not from farther than HelpFar", Brain.pickLift({ lift(3, H.HelpFar + 1) }) == nil and Brain.pickLift({ lift(3, H.HelpFar) }) == 3)
check("not one on the ground, not a two-hands one", Brain.pickLift({ lift(3, 5, { state = "ground" }), lift(2, 5, { class = "both" }) }) == nil)

-- 8.3 your call: you wait at your end, he walks over ------------------------------------------------------------------------

check("8.3 the switch: a two-person Lift waits for Danny", H.WaitForHelper == true)
check("8.3 in place within CallReady studs of his place at its far end", Brain.inPlace(H.CallReady, 0) and Brain.inPlace(0.2, 0) and not Brain.inPlace(H.CallReady + 0.1, 0))
check("…or within CallClose, blocked CallStuck s (a wall, the piece: the hold walks him the rest)", Brain.inPlace(H.CallClose, H.CallStuck)
	and not Brain.inPlace(H.CallClose, H.CallStuck - 0.1) and not Brain.inPlace(H.CallClose + 0.1, 99))
do
	local a = Brain.newApproach()
	local resort = false
	for step = 1, 300 do -- (30 s walking closer at 10 studs a second: never the last resort)
		resort = resort or Brain.approach(a, 400 - step, 0.1)
	end
	check("8.3 his walk to your call, coming closer: never faded over (even a long one)", not resort)
	local steps = 0
	repeat
		steps += 1
	until Brain.approach(a, 100.5, 0.1) or steps > 1000
	check("…no closer by CallGain studs for CallBlink s: the last resort (a fade-over)", near(steps * 0.1, H.CallBlink, 0.11), steps * 0.1)
	a = Brain.newApproach()
	Brain.approach(a, 50, 0.1)
	local blocked = 0
	for _ = 1, math.floor(H.CallBlink / 0.1) - 5 do
		blocked += if Brain.approach(a, 50 - H.CallGain * 0.5, 0.1) then 1 else 0
	end
	local progress = Brain.approach(a, 50 - H.CallGain - 0.1, 0.1)
	check("…a little closer (under CallGain) is no progress; CallGain closer starts the clock again", blocked == 0 and not progress and a.idle == 0)
end
local reach = Config.Moving.Reach.Item + 3 + 2
check("8.3 your call goes on at your end", Brain.callKept(4, reach, false, 0) == "on" and Brain.callKept(reach + H.CallLeave, reach, true, 1) == "on")
check("…walked CallLeave studs past the Lift's reach: away", Brain.callKept(reach + H.CallLeave + 0.1, reach, false, 0) == "away")
check("…he stood ready CallIdle s and you never lifted: idle", Brain.callKept(3, reach, true, H.CallIdle) == "idle" and Brain.callKept(3, reach, false, H.CallIdle) == "on")

-- Running from zombies -----------------------------------------------------------------------------------------------------

check("no zombie: he stays", not Brain.shouldFlee(nil, false, nil))
check("a zombie within FleeRange: he runs", Brain.shouldFlee(H.FleeRange - 1, false, nil) and Brain.shouldFlee(H.FleeRange, false, "hand"))
check("farther: not yet", not Brain.shouldFlee(H.FleeRange + 2, false, nil))
check("running: on until none is within SafeRange", Brain.shouldFlee(H.SafeRange - 1, true, nil) and not Brain.shouldFlee(H.SafeRange + 1, true, nil))
check("never with the other end of your piece (you lead)", not Brain.shouldFlee(1, true, "pair"))
local fx, fz = Brain.fleeTo(0, 0, 5, 0)
check("he runs FleeStep studs straight away", near(fx, -H.FleeStep) and near(fz, 0), `{fx}, {fz}`)
fx, fz = Brain.fleeTo(3, 4, 3, 4)
check("…a zombie right on him: some way", near(math.sqrt((fx - 3) ^ 2 + (fz - 4) ^ 2), H.FleeStep))

-- What he does now: the priority list ----------------------------------------------------------------------------------------

local function decide(fields: { [string]: any }): (string, number?)
	local input: Brain.Input = { hired = true, dead = false, holding = nil, seated = false, ride = false, threat = nil, fleeing = false, lift = nil, queued = nil,
		pair = false, open = false, atHouse = true, call = nil }
	for key, value in fields do
		(input :: any)[key] = value
	end
	return Brain.decide(input)
end
check("down", decide({ dead = true, holding = "hand", call = 3, seated = true }) == "down")
check("the other end of your piece first, zombies or not", decide({ holding = "pair", threat = 2, lift = 3, open = true, call = 6, ride = true }) == "hold")
check("8.3 in the van's seat: he rides (zombies, your call, his list or not)", decide({ seated = true, threat = 2, call = 6, queued = 1, ride = true }) == "seat"
	and decide({ seated = true, hired = false }) == "seat")
check("a zombie near: he runs, with his piece", decide({ holding = "hand", threat = 3, lift = 3, call = 6 }) == "flee")
local action, spot = decide({ call = 6, lift = 3, queued = 1, ride = true })
check("8.3 your call first (you wait at your end): before anything of his own", action == "come" and spot == 6)
action, spot = decide({ call = 6, holding = "hand" })
check("…even with a piece in his arms (he loads it or sets it down first)", action == "come" and spot == 6)
action, spot = decide({ lift = 3, queued = 1 })
check("(a) your two-person piece dragged alone before anything of his own", action == "help" and spot == 3)
action, spot = decide({ lift = 3, holding = "hand" })
check("…even with a piece in his arms (he loads it or sets it down first)", action == "help" and spot == 3)
check("(b) a piece in his arms: to the van, before his ride and his list", decide({ holding = "hand", queued = 1, ride = true }) == "deliver")
check("8.3 (c) you at the van's wheel: into it, before his list and the van's back", decide({ ride = true, queued = 1, open = true }) == "ride")
check("(d) the van's back for somebody coming with a piece, before his next piece", decide({ open = true, queued = 1 }) == "open")
action, spot = decide({ queued = 5 })
check("8.3 the next piece of his list", action == "fetch" and spot == 5)
action, spot = decide({ queued = 7, pair = true })
check("8.3 …a two-person one: he waits at it for you (needs)", action == "needs" and spot == 7)
check("…only while the van stands by the house", decide({ queued = 5, atHouse = false }) == "wait" and decide({ queued = 7, pair = true, atHouse = false }) == "wait")
check("nothing to carry: he waits at the van", decide({}) == "wait")
check("8.3 not hired: he waits by the van for hire (no call, no lift, no ride, no list, no back)", decide({ hired = false, call = 6, lift = 3, ride = true, queued = 1, open = true }) == "wait")
check("…but runs from a zombie, and a piece still in his arms goes to the van", decide({ hired = false, threat = 2 }) == "flee" and decide({ hired = false, holding = "hand" }) == "deliver")

-- The van's back -----------------------------------------------------------------------------------------------------------

check("open and standing: in it goes", Brain.atTruck(true, true, 0, true) == "load" and Brain.atTruck(true, true, 0) == "load")
check("7.x shut: he opens it himself (OpenBack)", Brain.atTruck(false, true, 0, true) == "open" and H.OpenBack == true)
check("…not allowed: he waits a while", Brain.atTruck(false, true, 0, false) == "wait" and Brain.atTruck(false, true, H.WaitShut - 0.1) == "wait")
check("…then sets it down beside the van", Brain.atTruck(false, true, H.WaitShut) == "drop")
check("the van moving: not yet", Brain.atTruck(true, false, 0, true) == "wait")

-- Speeds -------------------------------------------------------------------------------------------------------------------

check("empty-handed: 0.7 × a player's walk", near(Brain.speed(WALK, "fetch", nil, 0), WALK * 0.7) and H.Speed == 0.7)
check("with the lamp: 0.7 × a player's lamp walk", near(Brain.speed(WALK, "deliver", "hand", 1), Rules.carrySpeed(WALK, "hand", 1) * 0.7))
check("…slower than a player with it", Brain.speed(WALK, "deliver", "hand", 3) < Rules.carrySpeed(WALK, "hand", 3))
check("7.x a two-hands piece of his own: slower still", near(Brain.speed(WALK, "deliver", "both", 4), Rules.carrySpeed(WALK, "both", 4) * 0.7)
	and Brain.speed(WALK, "deliver", "both", 4) < Brain.speed(WALK, "deliver", "hand", 4))
check("7.x to your lift: a sprint, faster than your two-person walk", near(Brain.speed(WALK, "help", nil, 0), WALK * H.Sprint)
	and Brain.speed(WALK, "help", nil, 0) > Rules.carrySpeed(WALK, "pair", 8) * 1.1
	and Brain.speed(WALK, "come", nil, 0) == Brain.speed(WALK, "help", nil, 0) and Brain.speed(WALK, "ride", nil, 0) == Brain.speed(WALK, "help", nil, 0)) -- (8.3: to your call, to the van's seat too)
check("running from a zombie: Flee × the walk", near(Brain.speed(WALK, "flee", nil, 0), WALK * H.Flee))

-- Stuck ----------------------------------------------------------------------------------------------------------------------

-- 9.3 (the owner: "he runs for 2 seconds and then on the spot he somehow teleports around"): the clock is his progress
-- along his way, not his movement (a walk back or aside is no progress); his ways out walked, the fade only at the end
do
	local U = H.Unstuck
	local p = Brain.newProgress()
	Brain.rebase(p, 20)
	local stuck = Brain.progress(p, 19, 0.1, 0)
	check("9.3 walking on along his way: not stuck", stuck == 0 and p.best == 19)
	stuck = Brain.progress(p, 18.8, 0.1, stuck)
	stuck = Brain.progress(p, 19.4, 0.1, stuck)
	check("…nearer by less than Unstuck.Progress, or farther (a walk back): the seconds add up", near(stuck, 0.2) and U.Progress == 0.5)
	check("…progress again clears them", Brain.progress(p, 18.4, 0.1, stuck) == 0)
	Brain.rebase(p, 30)
	check("…a new way: its own length the best (a longer way round is no stuck spell)", Brain.progress(p, 29.4, 0.1, 0.3) == 0)
	Brain.rebase(p, 33, true)
	check("…within a stuck spell never a longer best (back, aside, then forward to the same block: no progress)", p.best == 29.4
		and Brain.progress(p, 29.2, 0.1, 2) > 2)
	check("9.3 stuck under Unstuck.Repath s: he walks on", (Brain.unstuck(U.Repath - 0.05)) == "walk")
	local phase, round = Brain.unstuck(U.Repath)
	check("…Repath s: a new way from where he stands", phase == "repath" and round == 0)
	check("…then his ways out, walked: back off what blocks him, then a sidestep", (Brain.unstuck(U.Repath + U.Back)) == "back"
		and (Brain.unstuck(U.Repath + U.Side)) == "side" and U.Back < U.Side and U.Side < U.Cycle)
	phase, round = Brain.unstuck(U.Repath + U.Cycle + 0.01)
	check("…round again (a new way first; the other side next time)", phase == "repath" and round == 1)
	check("…only Unstuck.Fade s without progress the last resort, a fade over (never 8.9's nudge on the spot after 4 s)",
		(Brain.unstuck(U.Fade - 0.05)) ~= "rescue" and (Brain.unstuck(U.Fade)) == "rescue" and U.Fade >= 10 and (Brain.unstuck(4)) ~= "rescue")
	local w = H.Walk
	check("9.3 into his goal: full speed until Walk.Ease studs, then slowing to Walk.EaseMin", Brain.ease(w.Ease + 1) == 1 and near(Brain.ease(0), w.EaseMin)
		and Brain.ease(w.Ease / 2) < 1 and Brain.ease(w.Ease / 2) > w.EaseMin)
	check("…there within `near`, or settled Walk.Settle s within Walk.Arrive more (the humanoid stops a hair short)", Brain.arrived(0.4, 0.5, 0)
		and not Brain.arrived(0.9, 0.5, 0) and Brain.arrived(0.9, 0.5, w.Settle) and not Brain.arrived(0.5 + w.Arrive + 0.1, 0.5, 5))
end

-- The far end of your piece (7.x) ------------------------------------------------------------------------------------------

check("his root Standoff past the far face", near(Brain.farEnd(3.2), 1.6 + H.Standoff))
do
	-- 8.6 his end (the owner: "he teleports from side to side"): the face across the piece from you, in its own frame
	local ax, az, half = Brain.holdEnd(7.2, 3.2, -6.1, 0) -- (the Sofa lengthwise: you at its -X end)
	check("8.6 his end: the far end of its length (you at one end: he at the other)", ax == 1 and az == 0 and near(half, 3.6))
	ax, az, half = Brain.holdEnd(6.0, 3.8, 0, 2.4) -- (the Dining Table broadside: you at its +Z side)
	check("…the face across it from you wherever you hold it (its -Z face, its half depth)", ax == 0 and az == -1 and near(half, 1.9))
	ax, az = Brain.holdEnd(3.8, 3.8, 0, 0)
	local bx, bz = Brain.holdEnd(6.0, 3.8, 0, 0)
	check("…you at its middle (nothing to go by): the old far face for a square, its length's +X end for a long one",
		ax == 0 and az == -1 and bx == 1 and bz == 0)
	ax, az = Brain.holdEnd(6.0, 3.8, -3.1, 1.9) -- (at a corner: the line through its middle leaves by its +X face)
	check("…at a corner: the face the line from you through its middle comes out at", ax == 1 and az == 0)
	ax, az = Brain.holdEnd(0 / 0, 3.8, 0 / 0, 2)
	check("…NaN in: a face, never NaN", (ax == 0 or ax == 1 or ax == -1) and (az == 0 or az == 1 or az == -1) and ax == ax)
	-- 8.6 his lead follows his end's own way, changing HoldLead.Rate studs a second at most
	local L = H.HoldLead
	local trail = Brain.newTrail()
	local function look(x: number, z: number, seconds: number): (number, number)
		return Brain.endLead(trail, x, z, 0.1, seconds, false)
	end
	local lx, lz = look(0, 0, 0.2)
	check("8.6 his lead: none at the first look", lx == 0 and lz == 0)
	local x, most, last = 0, 0, 0
	for _ = 1, 30 do
		x += 1
		lx = look(x, 0, 0.2)
		most = math.max(most, math.abs(lx - last))
		last = lx
	end
	check("…his end walking +X at 10 studs/s: its velocity × the lead time (2 studs) at the end", near(lx, 2, 1e-3), lx)
	check("…reached at HoldLead.Rate studs a second at most (never a jump of his aim)", most <= L.Rate * 0.1 + 1e-9 and L.Rate > 0 and L.Rate < 10, most)
	most = 0
	for _ = 1, 20 do
		x -= 1 -- (the way back at once: a 180°)
		lx = look(x, 0, 0.2)
		most = math.max(most, math.abs(lx - last))
		last = lx
	end
	check("…a 180°: the lead swings across at Rate at most (8.3's jumped 2 × lead in a look)", most <= L.Rate * 0.1 + 1e-9 and near(lx, -2, 1e-3), `{most} {lx}`)
	lx, lz = Brain.endLead(trail, x + 50, 0, 0.1, 0.2, false)
	check("…his end put far off at once (past HoldPace.Jump: a door's fade), or a reset: no lead", lx == 0 and lz == 0
		and select(1, Brain.endLead(trail, x + 51, 0, 0.1, 0.2, true)) == 0)
	lx, lz = Brain.endLead(trail, 0 / 0, 0, 0.1, 0.2, false)
	check("…no place (NaN): none, never NaN", lx == 0 and lz == 0)
	-- 9.0 (the owner's screenshot: Danny inside the Sofa) his end's way out of the piece (+X): never a lead toward its
	-- middle (HoldLead.In), the rest his hands' reach; away from it (he walks backwards) HoldLead.Back s more of it
	local function walked(dx: number, seconds: number): (number, number, Brain.Trail)
		local t = Brain.newTrail()
		local at, gx, gz = 0, 0, 0
		Brain.endLead(t, at, 0, 0.1, seconds, false, 1, 0)
		for _ = 1, 40 do
			at += dx
			gx, gz = Brain.endLead(t, at, 0, 0.1, seconds, false, 1, 0)
		end
		return gx, gz, t
	end
	local inX, inZ, inTrail = walked(-1, 0.2) -- (his end toward the piece's middle at 10 studs/s: he follows you)
	check("9.0 following you (his end toward the piece's middle): his lead toward it HoldLead.In at most (0: never into the piece)",
		L.In == 0 and inX >= -L.In - 1e-9 and math.abs(inZ) < 1e-9, inX)
	check("…his hands reach on by the lead it did not take (10 studs/s × 0.2 s: 2 studs)", near(inTrail.reach, 2, 1e-3), inTrail.reach)
	local outX, _, outTrail = walked(1, 0.2) -- (his end away from the piece: he walks backwards)
	check("…walking backwards himself (his end away from it): the lead and HoldLead.Back s more, his hands reaching on by that more",
		L.Back > 0 and near(outX, 10 * (0.2 + L.Back), 1e-3) and near(outTrail.reach, 10 * L.Back, 1e-3), `{outX} {outTrail.reach}`)
	local offX, _, offTrail = walked(1, 0)
	check("…no lead (Base 0, Ping 0: off): none of it either", offX == 0 and offTrail.reach == 0, offX)
	local crossX, crossZ = Brain.endLead(Brain.newTrail(), 0, 0, 0.1, 0.2, false, 1, 0)
	check("…a first look: nothing", crossX == 0 and crossZ == 0)
	-- 8.6 the ease back is HoldCap at most
	local eased = Brain.newTrail()
	local top = 0
	for _ = 1, 40 do
		top = math.max(top, (Brain.holdTrack(eased, 200, false, 10, 0.1)))
	end
	check("8.6 eased back from far off (200 studs): HoldCap at most (it was the gap / HoldEase: 400 studs a second)", near(top, H.HoldCap), top)
end
check("on the floor there: level with you", near(Brain.endRise(-1.75, -1.75), -1.75))
check("…a step up or down: with the floor", near(Brain.endRise(-1, -1.75), -1) and near(Brain.endRise(-3, -1.75), -3))
check("…a step's reach at most (HoldStep): the floor there", near(Brain.endRise(-1.75 + H.HoldStep, -1.75), -1.75 + H.HoldStep)
	and near(Brain.endRise(-1.75 - H.HoldStep, -1.75), -1.75 - H.HoldStep))
-- 8.3 (the owner: "he just jumps weirdly"): the porch's roof over his end (the 3.3-stud Dining Table's ray found it, 8.8
-- over the middle) was clamped HoldStep over you: a 2.5-stud hop. A floor out of a step's reach is not his.
check("8.3 a floor farther off than a step (a roof, a ceiling, a header; a pit): not his, level with you (never a hop)",
	near(Brain.endRise(8.8, -1.7), -1.7) and near(Brain.endRise(-1.75 + H.HoldStep + 0.01, -1.75), -1.75) and near(Brain.endRise(-40, -1.75), -1.75))
check("…no floor read: level with you", near(Brain.endRise(0 / 0, -1.75), -1.75))
do
	-- 8.3 his height follows the floor under his end at HoldClimb studs a second at most: a step stepped, never popped
	local trail = Brain.newTrail()
	check("8.3 a new hold: his height there at once", near(Brain.holdClimb(trail, 3, 0.1, false), 3) and trail.height == 3)
	local most, last, steps = 0, 3, 0
	repeat
		local y = Brain.holdClimb(trail, 4.5, 0.1, false)
		most = math.max(most, y - last)
		last = y
		steps += 1
	until near(y, 4.5) or steps > 50
	check("…a 1.5-stud step up: HoldClimb × dt a tick at most, there in 1.5 / HoldClimb s", near(last, 4.5) and most <= H.HoldClimb * 0.1 + 1e-9
		and steps == math.ceil(1.5 / (H.HoldClimb * 0.1) - 1e-9), `{steps} ticks, {most} at most`)
	check("…and down the same way", near(Brain.holdClimb(trail, 2, 0.1, false), 4.5 - H.HoldClimb * 0.1))
	check("…through a door's fade (the other world): there at once", near(Brain.holdClimb(trail, -5000, 0.1, true), -5000))
	check("…HoldClimb about a person's step (8 studs a second: a kerb's stud in an eighth of a second)", H.HoldClimb >= 4 and H.HoldClimb <= 12)
end
do
	-- 8.3 his legs (the owner: "walk like me, backwards too"): his whole speed, backwards when the way is behind him
	local L = H.HoldLegs
	local trail = Brain.newTrail()
	check("8.3 standing (under HoldLegs.From): his legs stand", Brain.holdLegs(trail, 0.5, 0, 0.1) == 0 and not trail.walking)
	check("…walking ahead (forwards along his facing): forwards at his speed", near(Brain.holdLegs(trail, 4.9, 0, 0.1), 4.9) and trail.walking)
	check("…the way behind him (you walk toward him): backwards at his speed", near(Brain.holdLegs(trail, -9.8, 0, 0.1), -9.8) and trail.back)
	check("…a step to the side: steps at his whole speed, the way they went (no flicker, no slide on still legs)",
		near(Brain.holdLegs(trail, 0.2, 5, 0.1), -math.sqrt(0.04 + 25)) and near(Brain.holdLegs(trail, -0.2, -5, 0.1), -math.sqrt(0.04 + 25)))
	check("…a diagonal: his whole speed, not its share along his facing", near(Brain.holdLegs(trail, -3, 4, 0.1), -5))
	check("…forwards again once more than Band of the way is ahead", near(Brain.holdLegs(trail, 4, 3, 0.1), 5) and not trail.back)
	check("…slowing: walking on down to HoldLegs.To, standing under it", near(Brain.holdLegs(trail, (L.From + L.To) / 2, 0, 0.1), (L.From + L.To) / 2)
		and Brain.holdLegs(trail, L.To * 0.9, 0, 0.1) == 0 and Brain.holdLegs(trail, (L.From + L.To) / 2, 0, 0.1) == 0)
	check("…the slow pair walk steps (the pair's walk turning: Pair × PairTurnWalk)", Brain.holdLegs(Brain.newTrail(), WALK * Config.Moving.Speed.Pair * H.PairTurnWalk, 0, 0.1) > 0)
end

-- 8.1 holding the far end: never put there (the owner: "when I turn around he teleports") ------------------------------

local pairWalk = Rules.carrySpeed(WALK, "pair", 8)
check("8.1 his top speed holding it: the pair's walk × HoldMargin + HoldExtra (about the pair's walk and a margin)",
	near(Brain.holdSpeed(pairWalk), pairWalk * H.HoldMargin + H.HoldExtra) and Brain.holdSpeed(pairWalk) > pairWalk and Brain.holdSpeed(pairWalk) < WALK * H.Sprint * 1.2)
check("…faster with a faster leader (a steady grip, a Mover, the admin's speed), never under HoldExtra", Brain.holdSpeed(pairWalk * 2) > Brain.holdSpeed(pairWalk)
	and near(Brain.holdSpeed(-3), H.HoldExtra))
check("8.1 his body turns to you at HoldTurn × PairTurn at most", near(Brain.holdTurn(), math.rad(H.PairTurn) * H.HoldTurn))

-- 8.3 keeping up (the owner: "when I run, he just goes behind me with his arms stretched out") ---------------------------

check("8.3 his top speed follows your real speed (pace) when it is more than the carry's walk: × HoldMargin + HoldExtra",
	near(Brain.holdSpeed(pairWalk, pairWalk * 1.2), pairWalk * 1.2 * H.HoldMargin + H.HoldExtra) and Brain.holdSpeed(pairWalk, pairWalk * 1.2) > pairWalk * 1.2)
check("…never under the carry's own (a slower pace, none, a NaN)", near(Brain.holdSpeed(pairWalk, 2), Brain.holdSpeed(pairWalk))
	and near(Brain.holdSpeed(pairWalk, nil), Brain.holdSpeed(pairWalk)) and near(Brain.holdSpeed(pairWalk, 0 / 0), Brain.holdSpeed(pairWalk)))
check("…a sprint (28) kept up with: more than 28, at most HoldCap", Brain.holdSpeed(pairWalk, Config.Movement.Sprint) > Config.Movement.Sprint
	and Brain.holdSpeed(pairWalk, Config.Movement.Sprint) <= H.HoldCap and near(Brain.holdSpeed(pairWalk, 500), H.HoldCap))
check("…an admin's boosted walk over HoldCap is never cut", near(Brain.holdSpeed(pairWalk * 4, pairWalk * 5), pairWalk * 4 * H.HoldMargin + H.HoldExtra)
	and Brain.holdSpeed(pairWalk * 4) > H.HoldCap)
do
	local trail = Brain.newTrail()
	check("8.3 your real speed: nothing measured at the first look", Brain.holdPace(trail, 0, 0, 0.1, false) == 0)
	local x = 0
	for _ = 1, 10 do
		x += pairWalk * 0.1
		Brain.holdPace(trail, x, 0, 0.1, false)
	end
	check("…walking at the pair's walk: that", near(trail.pace, pairWalk, 1e-6), trail.pace)
	x += pairWalk * 1.2 * 0.1
	check("…a rise taken at once (20% faster: a lag spike, a slope)", near(Brain.holdPace(trail, x, 0, 0.1, false), pairWalk * 1.2, 1e-6))
	x += pairWalk * 0.5 * 0.1
	local after = Brain.holdPace(trail, x, 0, 0.1, false)
	check("…a fall over HoldPace.Fall s (one slow look never slows him at once)", after > pairWalk and after < pairWalk * 1.2, after)
	for _ = 1, 30 do
		Brain.holdPace(trail, x, 0, 0.1, false)
	end
	check("…standing a while: none", trail.pace < 0.05 and math.abs(trail.vx) < 0.01, trail.pace)
	check("…a burst (8 studs in a look): HoldCap at most", near(Brain.holdPace(trail, x + 8, 0, 0.1, false), H.HoldCap))
	check("…put there at once (past HoldPace.Jump: a door's fade): nothing measured", Brain.holdPace(trail, x + 8 + H.HoldPace.Jump + 1, 0, 0.1, false) == 0
		and trail.vx == 0)
	Brain.holdPace(trail, 0, 0, 0.1, false)
	check("…a reset (a new hold, the other world): nothing measured", Brain.holdPace(trail, 0.5, 0, 0.1, true) == 0 and trail.fromX == 0.5)
	Brain.holdPace(trail, 0 / 0, 0 / 0, 0.1, true) -- (no root to look at: never kept)
	local again = Brain.holdPace(trail, 1, 0, 0.1, false)
	Brain.holdPace(trail, 2, 0, 0.1, false)
	local lnx, lnz = Brain.holdLead(trail, 0.1)
	check("…no root a look (NaN): never kept; the next looks measure again (no NaN speed, no NaN lead)", again == 0 and near(trail.pace, 10)
		and lnx == lnx and lnz == lnz and lnx > 0, trail.pace)
	-- the lead
	check("8.3 Danny's lead: HoldLead.Base + your ping × Ping, 0 … Most", near(Brain.leadTime(0), H.HoldLead.Base) and near(Brain.leadTime(0.1), H.HoldLead.Base + 0.1 * H.HoldLead.Ping)
		and near(Brain.leadTime(5), H.HoldLead.Most) and near(Brain.leadTime(nil), H.HoldLead.Base) and near(Brain.leadTime(0 / 0), H.HoldLead.Base)
		and H.HoldLead.Base > 0 and H.HoldLead.Most < 0.5)
	trail = Brain.newTrail()
	local z = 0
	for _ = 1, 20 do
		z -= pairWalk * 0.1
		Brain.holdPace(trail, 0, z, 0.1, false)
	end
	local lx, lz = Brain.holdLead(trail, 0.1)
	check("…your velocity × the lead, your way (walking -Z at the pair's walk: a stud ahead in 0.1 s)", near(lx, 0, 1e-6) and near(lz, -pairWalk * 0.1, 1e-3), lz)
	lx, lz = Brain.holdLead(trail, 10)
	check("…HoldLead.Far studs at most", near(math.sqrt(lx * lx + lz * lz), H.HoldLead.Far, 1e-6))
	for _ = 1, 10 do
		Brain.holdPace(trail, 0, z, 0.1, false)
	end
	lx, lz = Brain.holdLead(trail, 0.1)
	check("…you stop: the lead is gone within a second (smoothed over HoldLead.Smooth s)", math.abs(lz) < 0.01, lz)
end
do
	local top = Brain.holdSpeed(pairWalk)
	local trail = Brain.newTrail()
	local snapped, faster = false, false
	for _ = 1, 20 do -- (2 s a step behind his place: a slow swing)
		local limit, snap = Brain.holdTrack(trail, 1.5, false, top, 0.1)
		snapped = snapped or snap
		faster = faster or limit ~= top
	end
	check("8.1 close behind (under HoldBehind studs): his top speed, never put there", not snapped and not faster and trail.behind == 0)
	snapped, faster = false, false
	for _ = 1, 600 do -- (a minute 200 studs behind, far off: still never put there)
		local _, snap = Brain.holdTrack(trail, 200, false, top, 0.1)
		snapped = snapped or snap
	end
	check("…far behind for a minute (200 studs): never put there at once", not snapped)
	trail = Brain.newTrail()
	local first: number? = nil
	local easeSteps, easeSpeed = 0, 0
	for step = 1, 80 do -- (20 studs off, 8 s: stuck behind a wall)
		local limit, snap = Brain.holdTrack(trail, 20, false, top, 0.1)
		snapped = snapped or snap
		if limit > top + 1e-9 then
			first = first or step
			easeSteps += 1
			easeSpeed = limit
		end
	end
	check("8.1 more than HoldBehind studs off for HoldStuck s: eased back (20 studs over HoldEase s: 40 a second), not put there", not snapped and first ~= nil
		and near((first :: number) * 0.1, H.HoldStuck, 0.11) and near(easeSpeed, 20 / H.HoldEase) and easeSpeed > top)
	check("…the ease lasts HoldEase s, then his top speed again (and another ease HoldStuck s later if still stuck)", easeSteps == 2 * math.floor(H.HoldEase / 0.1 + 0.5), easeSteps)
	trail = Brain.newTrail()
	local limit, snap = Brain.holdTrack(trail, 4000, true, top, 0.1)
	check("8.1 only a door's fade puts him there: the piece in the other world", snap and near(limit, top) and trail.behind == 0)
	local _, again = Brain.holdTrack(trail, 0.2, false, top, 0.1)
	check("…and holding on from there: never again", not again)
end

do
	-- 9.2 the server's look at his end the leader's client drives (MoveHelperBrain.leadKept)
	local L = H.PairLead
	local away, kept = Brain.leadKept(0, L.Sane - 0.1, false, 0.1)
	check("9.2 leadKept: within PairLead.Sane studs of his end the drive stays (a glide in, a stumble: nothing counted)", away == 0 and kept)
	local steps = 0
	repeat
		away, kept = Brain.leadKept(away, L.Sane + 5, false, 0.1)
		steps += 1
	until not kept or steps > 100
	check("…more than Sane studs off for Grace s (an exploit's fling, a client that stopped driving): the server takes him back",
		not kept and near(steps * 0.1, L.Grace, 0.1 + 1e-9), steps * 0.1)
	away, kept = Brain.leadKept(L.Grace - 0.05, 300, true, 0.1)
	local door = away == 0 and kept
	away, kept = Brain.leadKept(L.Grace - 0.05, L.Sane - 1, false, 0.1)
	check("…a door's trip (the piece far off at once) is no fault, and back near his end the count starts again", door and away == 0 and kept)
	_, kept = Brain.leadKept(L.Grace, 0 / 0, false, 0.1)
	check("…no place known (NaN) counts as off", not kept)
end

check("7.x your grip bar while he holds the other end: the box Steadied (1.3) × bigger", near(CarryGrip.profile("pair", 8, false, false, true).zone,
	CarryGrip.profile("pair", 8, false, false).zone * Config.CarryGrip.Steadied) and Config.CarryGrip.Steadied == 1.3
	and near(CarryGrip.profile("pair", 8, false, false, false).zone, CarryGrip.profile("pair", 8, false, false).zone))

-- Doorways (7.x: he never stands where you walk through) --------------------------------------------------------------------

local door: Brain.Doorway = { x = 10, z = 0, half = 2, dirX = 0, dirZ = 1, depth = H.Aside.Depth } -- a wall along X, through along Z
local x, z, moved = Brain.aside(10.5, 1, door)
check("in the doorway: beside it, along the wall on his side", moved and near(x, 10 + 2 + H.Aside.Step) and near(z, H.Aside.Off), `{x}, {z}`)
x, z, moved = Brain.aside(9, -2, door)
check("…the other side: the other way", moved and near(x, 10 - 2 - H.Aside.Step) and near(z, -2), `{x}, {z}`)
x, z, moved = Brain.aside(17, 0, door)
check("beside the wall already: where he is", not moved and x == 17 and z == 0)
x, z, moved = Brain.aside(10, 6, door)
check("well into the room: where he is", not moved and x == 10 and z == 6)
local front: Brain.Doorway = { x = 0, z = 0, half = 2, dirX = 1, dirZ = 0, depth = H.Aside.FrontDepth }
x, z, moved = Brain.aside(4, 0.5, front)
check("the porch in front of the front door: beside it", moved and near(x, 4) and near(z, 2 + H.Aside.Step), `{x}, {z}`)

-- Words --------------------------------------------------------------------------------------------------------------------

check("what he does, in words (the van)", Brain.doing("deliver", "Lamp") == "Carrying the Lamp to the van" and Brain.doing("hold", "Sofa") == "Carrying the Sofa with you"
	and Brain.doing("wait") == "Waiting at the van" and Brain.doing("open") == "Opening the van's back" and Brain.doing("help", "Sofa") == "Coming to lift the Sofa"
	and Brain.doing("fetch", "Lamp") == "Going for the Lamp")
check("…the van full", Brain.doing("wait", nil, true) == "Waiting: the van is full")
check("…something unknown: waiting", Brain.doing("dance") == "Waiting at the van")
check("his lines: Got the other end! On three... lift! Watch the doorframe! That's going in the van.", Brain.Lines.lift == "Got the other end!"
	and Brain.Lines.three == "On three... lift!" and Brain.Lines.door == "Watch the doorframe!" and Brain.Lines.van == "That's going in the van."
	and string.find(Brain.Lines.full, "Van's full, boss", 1, true) == 1 and string.find(Brain.Lines.full, "Wall", 1, true) ~= nil)
check("8.3 what he does for your call, his list, for hire and in the van, in words", Brain.doing("come", "Sofa") == "Coming to lift the Sofa with you"
	and Brain.doing("ready", "Sofa") == "At the Sofa: on three!" and Brain.doing("needs", "Piano") == "Waiting for you at the Piano"
	and Brain.doing("offer") == "Waiting by the van for hire" and Brain.doing("ride") == "Getting in the van" and Brain.doing("seat") == "Riding in the van")
check("8.3 his lines for hire: hello asks to be hired (the sandbox's names no depot), hired, a piece given, the list cleared or done, a piece you took",
	string.find(Brain.Lines.hello, "Hire me!", 1, true) ~= nil and string.find(Brain.line("hello", true) :: string, "depot", 1, true) == nil
	and Brain.Lines.hired ~= nil and Brain.Lines.queued ~= nil and Brain.Lines.cleared ~= nil and Brain.Lines.empty ~= nil and Brain.Lines.mine == "All yours, boss.")
check("8.3 …a two-person piece of his list: 'too heavy for me alone, give me a hand!'; the ride: in and out", Brain.Lines.ask == "This one's too heavy for me alone, give me a hand!"
	and Brain.Lines.ride ~= nil and Brain.Lines.out ~= nil)
check("8.3 the old orders' lines are gone (AUTO, HELP ME, WAIT HERE, WAIT AT VAN, the ask's no-takers)", Brain.Lines.autoMode == nil and Brain.Lines.helpMode == nil
	and Brain.Lines.stayMode == nil and Brain.Lines.vanMode == nil and Brain.Lines.askOff == nil and (Brain :: any).Modes == nil and (Brain :: any).order == nil)
local ascii, short, truck = true, true, false
for _, text in Brain.Lines do
	if string.find(text, "[\128-\255]") then
		ascii = false
	end
	if #text > Config.MoveStory.Limits.Bubble then
		short = false
	end
	if string.find(string.lower(text), "truck", 1, true) then
		truck = true
	end
end
check("his lines are plain text (a bubble's font shows them), short, the van's (no truck)", ascii and short and not truck)

-- 8.6 the bubble over his head: the same action's words as the status line's ------------------------------------------------

do
	-- every action the server sets (MoveHelperBrain.decide's, the call's "ready", the hire's "offer", the van's "alight",
	-- GET OUT's "stay", down) has both words
	local ACTIONS = { "down", "hold", "flee", "help", "deliver", "open", "fetch", "wait", "come", "ready", "needs", "offer", "ride", "seat", "alight", "stay" }
	local missing: { string } = {}
	for _, action in ACTIONS do
		if Brain.Doing[action] == nil then
			table.insert(missing, action)
		end
	end
	check("8.6 every action he can be at has the status line's words and the bubble's (one entry each: Doing)", #missing == 0, table.concat(missing, ", "))
	local apart: { string } = {}
	for action, words in Brain.Doing do
		for _, full in { false, true } do
			local line = Brain.doing(action, "Sofa", full)
			local text, alert = Brain.bubble(action, "Sofa", full, 170)
			local w = if action == "wait" and full then Brain.Doing.full else words
			local sameName = (string.find(line, "Sofa", 1, true) ~= nil) == (string.find(text, "Sofa", 1, true) ~= nil)
			local starts = string.sub(text, 1, #w.icon + 1) == w.icon .. " "
			if line == "" or text == "" or not sameName or not starts or alert ~= (w.alert == true) or string.find(text, "%s", 1, true) ~= nil then
				table.insert(apart, `{action}{if full then " (full)" else ""}: "{line}" / "{text}"`)
			end
		end
	end
	check("8.6 …for every action (the van full or not): the bubble starts with its icon, names the piece exactly when the status line does, its tone the entry's", #apart == 0,
		table.concat(apart, " | "))
	check("8.6 the owner's examples: carrying to the van, going for a piece, waiting at a two-person piece (needs you, orange), getting in, riding, waiting, running",
		Brain.bubble("deliver", "Sofa") == "📦 Carrying: Sofa → van" and Brain.bubble("fetch", "Lamp") == "🚶 Going for: Lamp"
		and Brain.bubble("needs", "Piano") == "⏳ Needs you: Piano" and select(2, Brain.bubble("needs", "Piano")) == true
		and Brain.bubble("ride") == "🚐 Getting in the van" and Brain.bubble("seat") == "🪑 Riding" and Brain.bubble("wait") == "💤 Waiting by the van"
		and Brain.bubble("flee") == "🏃 Running from a zombie" and select(2, Brain.bubble("flee")) == true and select(2, Brain.bubble("deliver", "Sofa")) == false,
		Brain.bubble("deliver", "Sofa"))
	check("8.6 for hire: \"🧑‍🔧 For hire · $170\", the status line's price", Brain.bubble("offer", nil, false, 170) == "🧑‍🔧 For hire · $170"
		and string.find(Brain.status(false, 170, nil, nil), "$170", 1, true) ~= nil and Brain.doing("offer") == "Waiting by the van for hire")
	check("8.6 the van full: both say so; GET OUT's stay: both say he stays out", Brain.doing("wait", nil, true) == "Waiting: the van is full"
		and Brain.bubble("wait", nil, true) == "💤 Waiting: the van is full" and Brain.doing("stay") == "Staying out of the van (your order)"
		and Brain.bubble("stay") == "✋ Staying out of the van")
	check("8.6 something unknown: both as waiting at the van", Brain.doing("dance") == Brain.doing("wait") and Brain.bubble("dance") == Brain.bubble("wait"))
	check("8.6 the list's counter: \"list: 3\", none for an empty list or garbage", Brain.listChip(3) == "list: 3" and Brain.listChip(1) == "list: 1"
		and Brain.listChip(0) == nil and Brain.listChip(nil) == nil and Brain.listChip(0 / 0) == nil and Brain.listChip("3") == nil)
end

-- 8.6 the crew's orders: PUT IT DOWN, GET OUT ---------------------------------------------------------------------------------

do
	local function o(fields: { [string]: any }): Brain.Order
		local made: any = { hired = true, down = false, holding = nil, seated = false, boarding = false, riding = false, leaving = false, moving = false }
		for key, value in fields do
			made[key] = value
		end
		return made
	end
	check("8.6 PUT IT DOWN: a piece in his arms or the far end of yours: ok; nothing in his hands: \"empty\"", Brain.orderCheck("putdown", o({ holding = "hand" })) == "ok"
		and Brain.orderCheck("putdown", o({ holding = "pair" })) == "ok" and Brain.orderCheck("putdown", o({})) == "empty")
	check("8.6 …not hired: \"hire\"; down: \"down\"", Brain.orderCheck("putdown", o({ hired = false, holding = "hand" })) == "hire"
		and Brain.orderCheck("putdown", o({ down = true, holding = "hand" })) == "down" and Brain.orderCheck("getout", o({ hired = false, seated = true })) == "hire")
	check("8.6 GET OUT: seated, getting in, or on his way to the van to ride: ok; anywhere else: \"notin\"", Brain.orderCheck("getout", o({ seated = true })) == "ok"
		and Brain.orderCheck("getout", o({ boarding = true })) == "ok" and Brain.orderCheck("getout", o({ riding = true })) == "ok"
		and Brain.orderCheck("getout", o({})) == "notin" and Brain.orderCheck("getout", o({ holding = "hand" })) == "notin")
	check("8.6 …getting out already: \"leaving\"; the van rolling with him in it: \"moving\" (on foot after it: ok)", Brain.orderCheck("getout", o({ leaving = true })) == "leaving"
		and Brain.orderCheck("getout", o({ seated = true, moving = true })) == "moving" and Brain.orderCheck("getout", o({ riding = true, moving = true })) == "ok")
	check("8.6 an unknown order: \"unknown\" (the old ones too)", Brain.orderCheck("follow", o({ seated = true })) == "unknown" and Brain.orderCheck("stay", o({})) == "unknown")
	check("8.6 the orders that apply now: PUT IT DOWN while he carries, GET OUT while he is in (the van rolling too: its press says to stop), none else",
		Brain.orders(o({ holding = "hand" })) == "putdown" and Brain.orders(o({ seated = true })) == "getout" and Brain.orders(o({ seated = true, moving = true })) == "getout"
		and Brain.orders(o({})) == nil and Brain.orders(o({ hired = false, holding = "hand" })) == nil and Brain.orders(o({ down = true, seated = true })) == nil
		and Brain.orders(o({ leaving = true })) == nil)
	local list = Brain.orderList("putdown,getout,dance")
	check("8.6 …as a list (unknown kinds and garbage dropped)", #list == 2 and list[1] == "putdown" and list[2] == "getout" and #Brain.orderList(nil) == 0
		and #Brain.orderList(3) == 0)
	check("8.6 the buttons' words", Brain.orderWords("putdown") == "⬇ PUT IT DOWN" and Brain.orderWords("getout") == "🚪 GET OUT")
	local bad: { string } = {}
	for _, why in { "hire", "down", "empty", "notin", "leaving", "moving" } do
		local text = Brain.orderWhy(why)
		if not text or not string.find(text, H.Name, 1, true) or string.find(text, "click", 1, true) or string.find(text, "%s", 1, true) then
			table.insert(bad, why)
		end
	end
	check("8.6 every refusal has a notice naming him (no device's words: no \"click\"), \"ok\" and \"unknown\" none", #bad == 0 and Brain.orderWhy("ok") == nil
		and Brain.orderWhy("unknown") == nil and Brain.orderWhy("empty") == "Danny isn't carrying anything." and Brain.orderWhy("notin") == "Danny isn't in the van.",
		table.concat(bad, ", "))
	check("8.6 his answers: \"Setting it down.\", \"Hopping out, boss.\" (plain text, short: checked with every line above)", Brain.Lines.putDown == "Setting it down."
		and Brain.Lines.getOut == "Hopping out, boss." and Brain.Lines.putTogether ~= nil and Brain.Lines.stayOut ~= nil)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
