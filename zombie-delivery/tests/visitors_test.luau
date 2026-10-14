-- 8.3 SANDBOX, the showroom's visitors (shared/Visitors.luau, Config.Visitors): the kinds (weights, names, looks: the
-- collector's tweed, the hiker's beanie), the groups and the gaps (near: about a minute, away: every few minutes), the
-- offer's price (always over the market price, × Min … Max, more for a rarer piece, a hot kind, a keen kind, Top at most,
-- round), the hall of every plot as the layout builds it (the start's 12 stands and all 20): a spot at every stand
-- (never on a podium, in the door's way or at the desk, inside the walls, looking at its piece), a way from the door to
-- every spot and between them whose every leg keeps clear of the podiums and the desk, the doorway beside the van (off
-- its bay), a hall of another shape (a garage with two stands) works the same, the routes are cheap; the words ("Ooh, a
-- gramophone!", the toast "🤝 The collector offers $340 for your Gramophone", the card's lines) and the remote's offer
-- checked on the client.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Visitors = require("./Visitors")
local WarehouseLayout = require("./WarehouseLayout")
local SandboxMap = require("./SandboxMap")

local T = Config.Visitors
local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- ── The kinds ───────────────────────────────────────────────────────────────
do
	local ids: { [string]: boolean } = {}
	local bad = {}
	for _, kind in Visitors.kinds() do
		if ids[kind.id] then
			table.insert(bad, `{kind.id} twice`)
		end
		ids[kind.id] = true
		if kind.weight <= 0 or #kind.names == 0 or kind.title == "" or kind.chance < 0 or kind.pay < 0 then
			table.insert(bad, kind.id)
		end
		if Visitors.kind(kind.id) ~= kind then
			table.insert(bad, `Visitors.kind({kind.id})`)
		end
	end
	check("the kinds: unique ids, a weight, names, a title, a chance and a pay; Visitors.kind finds each", #bad == 0 and #Visitors.kinds() >= 3, table.concat(bad, ", "))
	check("tourists, hikers and a collector among them", ids.tourist == true and ids.hiker == true and ids.collector == true)
	local counts: { [string]: number } = {}
	for i = 0, 999 do
		local kind = Visitors.pickKind(i / 1000)
		counts[kind.id] = (counts[kind.id] or 0) + 1
	end
	local total = 0
	for _, kind in Visitors.kinds() do
		total += kind.weight
	end
	local fair = true
	for _, kind in Visitors.kinds() do
		if math.abs((counts[kind.id] or 0) / 1000 - kind.weight / total) > 0.01 then
			fair = false
		end
	end
	check("Visitors.pickKind: each kind by its weight", fair)
	local collector = Visitors.kind("collector") :: Visitors.Kind
	local look = Visitors.look(collector, "Mr. Whitcombe")
	check("the collector's look: a tweed jacket (its colour on the shirt, a vest over it), a tie, the name and title over the head, the stroll's pace",
		look.name == "Mr. Whitcombe" and look.title == "Collector" and look.vest ~= nil and look.tie ~= nil and look.shirt ~= nil and look.shirt[1] == 138
		and look.walkSpeed == T.Walk)
	local hiker = Visitors.look(Visitors.kind("hiker") :: Visitors.Kind, "Sepp")
	check("the hiker's beanie and boots; a tourist's cap", hiker.hat == "beanie" and hiker.boots == true and Visitors.look(Visitors.kind("tourist") :: Visitors.Kind, "Yuki").hat == "cap")
	check("names from the kind's list; who: \"The collector\"", table.find(collector.names, Visitors.pickName(collector, 0.99)) ~= nil
		and Visitors.pickName(collector, 0) == collector.names[1] and Visitors.who(collector) == "The collector")
end

-- ── Groups and gaps ─────────────────────────────────────────────────────────
do
	local sizes: { [number]: number } = {}
	for i = 0, 999 do
		local n = Visitors.groupSize(i / 1000)
		sizes[n] = (sizes[n] or 0) + 1
	end
	check("a group: 1 – 3 by Group's chances", (sizes[1] or 0) == 500 and (sizes[2] or 0) == 350 and (sizes[3] or 0) == 150 and sizes[4] == nil, `{sizes[1]} {sizes[2]} {sizes[3]}`)
	check("the gaps: near NearEvery (about a minute), away AwayEvery (every few minutes)", Visitors.gap(true, 0) == T.NearEvery[1] and Visitors.gap(true, 1) <= T.NearEvery[2]
		and Visitors.gap(false, 0) == T.AwayEvery[1] and T.AwayEvery[1] >= 120 and T.NearEvery[2] <= 90)
	check("the cap: a few a hall, a small number a server", T.PerHall >= 1 and T.PerHall <= 3 and T.Cap >= T.PerHall and T.Cap <= 8)
end

-- ── The offer ───────────────────────────────────────────────────────────────
do
	local O = T.Offer
	local bad = {}
	for _, market in { 1, 2, 9, 40, 99, 100, 230, 999, 1000, 1234, 5000 } do
		for rank = 1, 5 do
			for _, hot in { false, true } do
				for _, pay in { 0, 0.1 } do
					for r = 0, 10 do
						local price = Visitors.offerPrice(market, rank, hot, pay, r / 10)
						local factor = Visitors.offerFactor(rank, hot, pay, r / 10)
						local step = if market * factor >= 1000 then 10 elseif market * factor >= 100 then 5 else 1
						if price <= market or price ~= math.floor(price) or price % step ~= 0 and price ~= market + 1 or price < market * factor - 1e-6
							or price > market * O.Top + step then
							table.insert(bad, `{market} r{rank} {hot} {pay} {r}: {price}`)
						end
					end
				end
			end
		end
	end
	check("an offer: whole, round ($5 from $100, $10 from $1,000), never under its factor, always over the market price, Top at most", #bad == 0, bad[1])
	check("× Min … Max for a common piece of an ordinary kind", Visitors.offerFactor(1, false, 0, 0) == O.Min and math.abs(Visitors.offerFactor(1, false, 0, 0.999999) - O.Max) < 1e-4)
	check("more for a rarer piece, a hot kind, a keen kind (the collector's pay)", Visitors.offerFactor(5, false, 0, 0.5) > Visitors.offerFactor(3, false, 0, 0.5)
		and Visitors.offerFactor(3, false, 0, 0.5) > Visitors.offerFactor(1, false, 0, 0.5) and Visitors.offerFactor(1, true, 0, 0.5) > Visitors.offerFactor(1, false, 0, 0.5)
		and Visitors.offerFactor(1, false, 0.1, 0.5) > Visitors.offerFactor(1, false, 0, 0.5) and Visitors.offerFactor(5, true, 0.5, 0.99) == O.Top)
	check("the example: $230 × 1.478 = $339.94, up to $340", Visitors.offerPrice(230, 1, false, 0, (1.478 - O.Min) / (O.Max - O.Min)) == 340, Visitors.offerPrice(230, 1, false, 0, (1.478 - O.Min) / (O.Max - O.Min)))
	check("the chance: Offer.Chance × the kind's, at most 1", Visitors.offerChance(Visitors.kind("collector") :: Visitors.Kind) == math.min(1, O.Chance * 1.6)
		and Visitors.offerChance(Visitors.kind("tourist") :: Visitors.Kind) < Visitors.offerChance(Visitors.kind("collector") :: Visitors.Kind))
	check("an offer stays open about half a minute, two to one player Every s apart at least", O.Expire >= 20 and O.Expire <= 45 and O.Every >= O.Expire)
end

-- ── The hall ────────────────────────────────────────────────────────────────

-- The layout's hall as server/Visitors.luau reads it (the start's level: no level argument).
local function inputOf(plot: SandboxMap.Plot, stands: number): Visitors.HallInput
	local podiums: { Visitors.Podium } = {}
	for i = 1, stands do
		local s = WarehouseLayout.stand(plot, i)
		if s then
			table.insert(podiums, { index = i, x = s.x, z = s.z, sx = s.sx, sz = s.sz, yaw = s.yaw })
		end
	end
	local desk = WarehouseLayout.terminal(plot)
	local door = WarehouseLayout.door(plot)
	return {
		inside = WarehouseLayout.inside(plot),
		door = { x = door.x, z = door.z, width = door.width },
		doorPath = WarehouseLayout.doorPath(plot),
		desk = { index = 0, x = desk.x, z = desk.z, sx = desk.sx, sz = desk.sz, yaw = desk.yaw },
		stands = podiums,
	}
end

local function inRect(r: Visitors.Rect, x: number, z: number, grow: number): boolean
	return x >= r.x0 - grow and x <= r.x1 + grow and z >= r.z0 - grow and z <= r.z1 + grow
end
local function onPodium(p: Visitors.Podium, x: number, z: number, grow: number): boolean
	local turned = math.abs(math.sin(math.rad(p.yaw))) > 0.5
	local hx, hz = (if turned then p.sz else p.sx) / 2, (if turned then p.sx else p.sz) / 2
	return math.abs(x - p.x) <= hx + grow and math.abs(z - p.z) <= hz + grow
end
-- Does the straight line from a to b keep `grow` studs off every podium and the desk, and inside the walls?
local function legClear(input: Visitors.HallInput, a: Visitors.Point, b: Visitors.Point, grow: number): (boolean, string?)
	local steps = math.max(1, math.ceil(math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2) / 0.25))
	for k = 0, steps do
		local x, z = a.x + (b.x - a.x) * k / steps, a.z + (b.z - a.z) * k / steps
		if not inRect(input.inside, x, z, -grow) then
			return false, `wall at {x},{z}`
		end
		for _, p in input.stands do
			if onPodium(p, x, z, grow) then
				return false, `stand {p.index} at {math.floor(x)},{math.floor(z)}`
			end
		end
		if input.desk and onPodium(input.desk :: Visitors.Podium, x, z, grow) then
			return false, "the desk"
		end
	end
	return true, nil
end

local function hallChecks(label: string, input: Visitors.HallInput, side: number)
	local hall = Visitors.hall(input)
	local door = Visitors.doorway(hall, side)
	local bad = {}
	local spots: { [number]: Visitors.Spot } = {}
	for _, p in input.stands do
		local spot = Visitors.spot(hall, p.index, 0.3)
		if not spot then
			table.insert(bad, `stand {p.index}: no spot`)
		else
			spots[p.index] = spot
			if spot.faceX ~= p.x or spot.faceZ ~= p.z then
				table.insert(bad, `stand {p.index}: does not look at its piece`)
			end
			if input.doorPath and inRect(input.doorPath :: Visitors.Rect, spot.x, spot.z, 0) then
				table.insert(bad, `stand {p.index}: in the door path`)
			end
			if input.desk and onPodium(input.desk :: Visitors.Podium, spot.x, spot.z, T.DeskClear - 0.01) then
				table.insert(bad, `stand {p.index}: at the desk`)
			end
			local ok, why = legClear(input, { x = spot.x, z = spot.z }, { x = spot.x, z = spot.z }, T.Margin * 0.7)
			if not ok then
				table.insert(bad, `stand {p.index}: {why}`)
			end
			local d = math.sqrt((spot.x - p.x) ^ 2 + (spot.z - p.z) ^ 2)
			if d > math.max(p.sx, p.sz) / 2 + T.View + 3 then
				table.insert(bad, `stand {p.index}: too far ({math.floor(d)})`)
			end
		end
	end
	check(`{label}: a spot at every stand, looking at its piece, near it, off the podiums, out of the door's way and off the desk`, #bad == 0, bad[1])
	-- the way in to every spot and on to the next, every leg straight and clear
	table.clear(bad)
	local legsMost = 0
	local function walkOk(from: Visitors.Point, to: Visitors.Point, what: string)
		local legs = Visitors.route(hall, from, to)
		if not legs then
			table.insert(bad, `{what}: no way`)
			return
		end
		legsMost = math.max(legsMost, #legs)
		local last = legs[#legs]
		if math.abs(last.x - to.x) > 1e-6 or math.abs(last.z - to.z) > 1e-6 then
			table.insert(bad, `{what}: ends at {last.x},{last.z}`)
		end
		local here = from
		for index, leg in legs do
			local ok, why = legClear(input, here, leg, T.Margin * 0.45)
			if not ok and not (index == 1 and not Visitors.free(hall, from.x, from.z)) then
				table.insert(bad, `{what} leg {index}: {why}`)
			end
			here = leg
		end
	end
	local before: Visitors.Point? = nil
	for _, p in input.stands do
		local spot = spots[p.index]
		if spot then
			local to = { x = spot.x, z = spot.z }
			walkOk(door.inside, to, `door → stand {p.index}`)
			if before then
				walkOk(before :: Visitors.Point, to, `→ stand {p.index}`)
			end
			walkOk(to, door.inside, `stand {p.index} → door`)
			before = to
		end
	end
	check(`{label}: a way in to every spot, on to the next and out, each leg straight and clear of the podiums, the desk and the walls (at most {legsMost} legs)`, #bad == 0 and legsMost <= 8, bad[1] or legsMost)
	-- the doorway: through the door's side beside the van, in, never in the van's bay
	local d = input.door
	check(`{label}: the doorway: outside beside the van, through the door's side (not its middle), inside on the floor`, math.abs(door.threshold.x - d.x) <= d.width / 2
		and math.abs(door.threshold.x - d.x) >= 2 and door.threshold.z > d.z and door.outside.z > d.z + 5 and Visitors.free(hall, door.inside.x, door.inside.z)
		and door.inside.z < d.z and math.abs(door.inside.x - door.threshold.x) < 3)
	return hall, door
end

for _, plot in SandboxMap.Plots do
	local label = `plot {plot.id}, the start's {WarehouseLayout.count()} stands`
	local input = inputOf(plot, WarehouseLayout.count())
	local _, door = hallChecks(label, input, if plot.id % 2 == 0 then 1 else -1)
	local bay = WarehouseLayout.bay(plot)
	check(`plot {plot.id}: the visitors come and go off the van's bay (UNLOAD HERE)`, not inRect(bay, door.outside.x, door.outside.z, 1)
		and not inRect(bay, door.threshold.x, door.threshold.z, 1), `{door.outside.x},{door.outside.z}`)
end
hallChecks(`plot 1, all {WarehouseLayout.capacity()} stands (8.1's small ones too)`, inputOf(SandboxMap.Plots[1], WarehouseLayout.capacity()), 1)

-- a hall of another shape (a level's: a narrow garage, two stands either side of its middle, the desk at the back)
local garage: Visitors.HallInput = {
	inside = { x0 = -14, x1 = 14, z0 = -40, z1 = -10 },
	door = { x = 0, z = -9, width = 12 },
	doorPath = { x0 = -6, x1 = 6, z0 = -24, z1 = -3 },
	desk = { index = 0, x = 0, z = -38.6, sx = 6.4, sz = 2.8, yaw = 180 },
	stands = {
		{ index = 1, x = -8, z = -28, sx = 8, sz = 8, yaw = 180 },
		{ index = 2, x = 8, z = -28, sx = 8, sz = 8, yaw = 180 },
	},
}
hallChecks("a garage's hall (two stands, a narrow door)", garage, -1)

-- the routes are cheap: a hundred in the biggest hall
do
	local hall = Visitors.hall(inputOf(SandboxMap.Plots[3], WarehouseLayout.capacity()))
	local door = Visitors.doorway(hall, 1)
	local started = os.clock()
	local found = 0
	for n = 1, 100 do
		local stand = (n - 1) % WarehouseLayout.capacity() + 1
		local spot = Visitors.spot(hall, stand, n / 100)
		if spot and Visitors.route(hall, door.inside, { x = spot.x, z = spot.z }) then
			found += 1
		end
	end
	local took = os.clock() - started
	check(`a hundred spots and routes in the biggest hall: {found} found in {math.floor(took * 1000)} ms (under 400)`, found == 100 and took < 0.4, took)
	check("Visitors.free: off the grid is not walkable, a podium is not, the aisle is", not Visitors.free(hall, -1e6, 0) and not Visitors.free(hall, 0 / 0, 0)
		and not Visitors.free(hall, (hall.podiums[1] :: Visitors.Podium).x, (hall.podiums[1] :: Visitors.Podium).z))
	check("Visitors.spot: no such stand, nil", Visitors.spot(hall, 99) == nil)
end

-- ── The words ───────────────────────────────────────────────────────────────
do
	check("a look: \"Ooh, a gramophone!\" (the name in lower case, \"an\" before a vowel)", Visitors.say("look", 0, "Gramophone") == "Ooh, a gramophone!"
		and Visitors.say("look", 0, "Old Globe") == "Ooh, an old globe!")
	local all = true
	for i = 0, 99 do
		local line = Visitors.say("look", i / 100, "Jukebox")
		if not line or not string.find(line, "jukebox", 1, true) then
			all = false
		end
	end
	check("every look names the piece", all)
	check("the offer names the price and the piece", Visitors.say("offer", 0, "Gramophone", 340) == "I'll give you $340 for that gramophone!")
	check("the answers: sold, declined, expired, gone", Visitors.say("sold", 0) == "Pleasure doing business!" and Visitors.say("declined", 0) ~= nil
		and Visitors.say("expired", 0) ~= nil and Visitors.say("gone", 0) ~= nil and Visitors.say("nonsense", 0) == nil)
	local greets = 0
	for i = 0, 99 do
		if Visitors.say("greet", i / 100) then
			greets += 1
		end
	end
	check("a greeting only now and then (35 %)", greets == 35, greets)
	check("the toast: \"🤝 The collector offers $340 for your Gramophone\"", Visitors.toast("Collector", 340, "Gramophone") == "🤝 The collector offers $340 for your Gramophone")
	local lines = Visitors.cardLines({ id = "o1", name = "Gramophone", item = "gramophone", price = 340, base = 260, who = "Collector", seconds = 30 })
	check("the card: \"The collector offers\", \"$340\", \"for your Gramophone\", \"Market price $260 · +31%\"", lines.who == "The collector offers" and lines.price == "$340"
		and lines.item == "for your Gramophone" and lines.market == "Market price $260 · +31%", lines.market)
	local good = { kind = "offer", id = "o7", name = "Gramophone", item = "gramophone", price = 340, base = 260, who = "Collector", seconds = 30, rarity = "rare", market = "hot" }
	local read = Visitors.readOffer(good)
	check("Visitors.readOffer: a good offer as it came", read ~= nil and read.id == "o7" and read.price == 340 and read.market == "hot" and read.rarity == "rare")
	local junk = 0
	for _, change in { { id = 7 }, { price = 0 }, { price = 3.5 }, { price = 0 / 0 }, { base = -1 }, { seconds = math.huge }, { name = "" }, { who = string.rep("x", 99) } } do
		local copy = table.clone(good)
		for k, v in change do
			(copy :: any)[k] = v
		end
		if Visitors.readOffer(copy) == nil then
			junk += 1
		end
	end
	check("… and junk refused (a number id, no price, a broken price, a NaN, a negative base, no end, no name, a long who)", junk == 8 and Visitors.readOffer("offer") == nil, junk)
	check("… an unknown market tag dropped", (Visitors.readOffer({ id = "o", name = "N", item = "i", price = 5, base = 4, who = "W", seconds = 3, market = "warm" }) :: any).market == nil)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
