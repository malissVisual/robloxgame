--!strict
-- 10.6 THE FLOATING ISLANDS (design/islands/plan.py → plan.json → shared/SandboxMap.luau's ISLANDS section, written by
-- tools/islands/sandboxmap.py): the plan's islands, pure (no Roblox). SandboxMap.Islands against the plan (IslandPlan.luau,
-- tests/run_tests.py writes it from plan.json); the lobby's island the first and the biggest, one island a place to
-- empty, each place's own; none on another, far enough apart that nobody jumps from one to the next; every map island
-- seen from the lobby (Plan VIEW: 400 … 1 500 studs off it), at varying heights; every place inside its island with room
-- round it (its box, its lot, its yard, its landmarks, its walls, its arrival; the mill's waterfall over its edge); room
-- for 16 vans a place (a round's parking: shared/RoundRules.luau's numbers, the plan's PARK), clear of everything solid;
-- every island's and rock's bottom far over workspace.FallenPartsDestroyHeight (Config.Islands.Destroy, the fall catch's
-- reach); SandboxMap.groundAt / islandAt / islandOf / roadAt; shared/IslandLooks.luau's rock (its pieces under the
-- island's top and inside it but the boulders' faces, its bottom the plan's, its tip and hanging rocks decoration, its
-- materials), the floating rocks and the clouds (under every island).
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local IslandLooks = require("./IslandLooks")
local VillageLooks = require("./VillageLooks")
local Plan = require("./IslandPlan")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

type Rect = { x0: number, x1: number, z0: number, z1: number }
local EPS = 1e-6
local I = Config.Islands
local Islands = SandboxMap.Islands
local function same(a: Rect, b: Rect): boolean
	return math.abs(a.x0 - b.x0) < EPS and math.abs(a.x1 - b.x1) < EPS and math.abs(a.z0 - b.z0) < EPS and math.abs(a.z1 - b.z1) < EPS
end
local function holds(outer: Rect, r: Rect, margin: number): boolean
	return r.x0 >= outer.x0 + margin - EPS and r.x1 <= outer.x1 - margin + EPS and r.z0 >= outer.z0 + margin - EPS and r.z1 <= outer.z1 - margin + EPS
end
local function overlaps(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 - EPS and b.x0 < a.x1 - EPS and a.z0 < b.z1 - EPS and b.z0 < a.z1 - EPS
end
local function gap(a: Rect, b: Rect): number
	local dx = math.max(a.x0 - b.x1, 0, b.x0 - a.x1)
	local dz = math.max(a.z0 - b.z1, 0, b.z0 - a.z1)
	return math.sqrt(dx * dx + dz * dz)
end
local function around(x: number, z: number, r: number): Rect
	return { x0 = x - r, x1 = x + r, z0 = z - r, z1 = z + r }
end
local function grow(r: Rect, by: number): Rect
	return { x0 = r.x0 - by, x1 = r.x1 + by, z0 = r.z0 - by, z1 = r.z1 + by }
end
local function area(i: SandboxMap.Island): number
	return i.sx * i.sz
end

-- ── The plan ─────────────────────────────────────────────────────────────────

check("SandboxMap.Islands the plan's (its ids, its tops' rects, heights, depths, walls and homes: tools/islands/sandboxmap.py)", (function(): boolean
	if #Islands ~= #Plan.islands then
		return false
	end
	for n, p in Plan.islands do
		local i = Islands[n]
		local h = i.home
		if i.id ~= p.id or i.house ~= p.house or not same(i.rect, p.rect) or i.top ~= p.top or i.depth ~= p.depth or not same(i.walls, p.walls)
			or h.x ~= p.home.x or h.y ~= p.home.y or h.z ~= p.home.z or h.yaw ~= p.home.yaw then
			return false
		end
		if math.abs(i.sx - (i.rect.x1 - i.rect.x0)) > EPS or math.abs(i.sz - (i.rect.z1 - i.rect.z0)) > EPS
			or math.abs(i.x - (i.rect.x0 + i.rect.x1) / 2) > EPS or math.abs(i.z - (i.rect.z0 + i.rect.z1) / 2) > EPS then
			return false
		end
	end
	return true
end)())
check("the plan's destroy height Config.Islands.Destroy's", Plan.destroy == I.Destroy)

-- ── One island a place, the lobby's the biggest ──────────────────────────────

local lobby = Islands[1]
check("the first the lobby's (no house: the bounds, the plots, PLAY)", lobby.id == "lobby" and lobby.house == nil and #Islands == #SandboxMap.Houses + 1)
check("…its walls the lobby's bounds, its home the spawn", same(lobby.walls, SandboxMap.Lobby.bounds) and lobby.home.x == SandboxMap.Lobby.spawn.x
	and lobby.home.z == SandboxMap.Lobby.spawn.z)
do
	local bad: string? = nil
	local houses: { [string]: number } = {}
	for _, h in SandboxMap.Houses do
		local i = SandboxMap.island(h.island)
		houses[h.id] = (houses[h.id] or 0) + 1
		if not i or i.house ~= h.id or SandboxMap.islandOf(h.id) ~= i then
			bad = bad or `{h.id}: its island {h.island}`
		end
	end
	for n = 2, #Islands do
		local i = Islands[n]
		if not i.house or houses[i.house] ~= 1 then
			bad = bad or `{i.id}: its place {i.house}`
		end
	end
	check("one island a place to empty (SandboxMap.Houses' island, the island's house), each a place of its own", bad == nil, bad)
end
do
	local bad: string? = nil
	for n = 2, #Islands do
		local i = Islands[n]
		if area(i) >= area(lobby) or math.max(i.sx, i.sz) >= math.max(lobby.sx, lobby.sz) then
			bad = bad or `{i.id}: {i.sx} × {i.sz} against the lobby's {lobby.sx} × {lobby.sz}`
		end
		if math.min(i.sx, i.sz) < 140 then
			bad = bad or `{i.id}: {i.sx} × {i.sz} (fairly big: 140 studs across at least)`
		end
	end
	check("the lobby's island the biggest (in area and in length), the others fairly big (140 studs across and more)", bad == nil, bad)
end

-- ── Apart, seen, at their heights ────────────────────────────────────────────

do
	local nearest = math.huge
	local pair = ""
	for n, a in Islands do
		for m = n + 1, #Islands do
			local b = Islands[m]
			local d = gap(a.rect, b.rect)
			if d < nearest then
				nearest, pair = d, `{a.id} – {b.id}`
			end
		end
	end
	-- (a run and a jump cover 20 studs or so: 200 is far past it, and past a fall's glide too)
	check(`no island on another, nobody jumps from one to the next (200 studs apart and more; the nearest {pair} {math.floor(nearest)})`, nearest >= 200, nearest)
end
do
	local seen, bad = 0, nil
	local tops: { [number]: boolean } = {}
	local lo, hi = math.huge, -math.huge
	for n = 2, #Islands do
		local i = Islands[n]
		local d = math.sqrt((i.x - lobby.x) ^ 2 + (i.z - lobby.z) ^ 2)
		if d >= 400 and d <= 1500 then
			seen += 1
		end
		if tops[i.top] then
			bad = bad or `{i.id}: the same top as another`
		end
		tops[i.top] = true
		lo, hi = math.min(lo, i.top), math.max(hi, i.top)
		if i.top <= lobby.top or i.top > 85 then
			bad = bad or `{i.id}: its top {i.top} (over the lobby's, under the vans' ground rays' reach)`
		end
	end
	check("every map island seen from the lobby (400 … 1 500 studs off its middle)", seen == #Islands - 1, seen)
	check("…at varying heights: none at another's, 40 studs from the lowest to the highest at least, over the lobby, under 85 (Vehicles.groundY's rays)",
		bad == nil and hi - lo >= 40, bad or `{lo} … {hi}`)
end
do
	local bad: string? = nil
	for _, z in SandboxMap.Zones do
		local d = gap(z.rect, SandboxMap.Lobby.bounds)
		if d < SandboxMap.Lobby.far then
			bad = bad or `{z.id}: {math.floor(d)}`
		end
	end
	check(`every other island's walls {SandboxMap.Lobby.far} studs and more off the lobby's (Lobby.far)`, bad == nil, bad)
end

-- ── Every place on its island, with room round it ────────────────────────────

local MARGIN = 4
local RIM = 10
do
	local bad: string? = nil
	for _, i in Islands do
		if not holds(i.rect, i.walls, if i.house then RIM else 15) then
			bad = bad or `{i.id}: its walls`
		end
		if not holds(SandboxMap.Bounds, i.rect, 0) then
			bad = bad or `{i.id}: out of the Bounds`
		end
		local home = i.home
		if not holds(i.walls, around(home.x, home.z, 4), 0) or math.abs(home.y - i.top - 3) > EPS then
			bad = bad or `{i.id}: its home`
		end
	end
	check(`every island's walls (the lobby's bounds, a run zone's edge) {RIM} studs and more in from its edge, its home inside them over its top`, bad == nil, bad)
end
do
	local bad: string? = nil
	for _, h in SandboxMap.Houses do
		local i = SandboxMap.islandOf(h.id) :: SandboxMap.Island
		local zone = SandboxMap.zone(h.id)
		local things: { { string | Rect } } = { { "box", h.box }, { "lot", h.lot }, { "door", around(h.door.x, h.door.z, 1) }, { "curb", around(h.curb.x, h.curb.z, 4) } }
		for _, road in SandboxMap.Roads do
			if road.name == h.street then
				table.insert(things, { "yard", road :: any })
			end
		end
		if zone then
			table.insert(things, { "arrive", around(zone.arrive.x, zone.arrive.z, 4) })
			if not same(zone.rect, i.walls) then
				bad = bad or `{h.id}: its run zone not its island's walls`
			end
		else
			bad = bad or `{h.id}: no run zone`
		end
		for _, t in things do
			local r = t[2] :: Rect
			if not holds(i.walls, r, 0) or not holds(i.rect, r, MARGIN + RIM) then
				bad = bad or `{h.id}: its {t[1]} off its island's walls`
			end
		end
		if h.door.y ~= i.top or h.house.y ~= i.top or math.abs(h.curb.y - SandboxMap.roadAt(h.curb.x, h.curb.z)) > EPS or (zone and math.abs(zone.arrive.y - i.top - 3) > EPS) then
			bad = bad or `{h.id}: its heights (its island's top {i.top})`
		end
	end
	check(`every place inside its island's walls (its box, lot, door, curb, yard, arrival; {MARGIN} studs and more past its rim), at its island's top`, bad == nil, bad)
end
do
	local bad: string? = nil
	local falls = 0
	for _, l in SandboxMap.Landmarks do
		local r = { x0 = l.x0, x1 = l.x1, z0 = l.z0, z1 = l.z1 }
		local i = SandboxMap.islandAt((l.x0 + l.x1) / 2, (l.z0 + l.z1) / 2, 20)
		if l.kind == "waterfall" then -- (over its island's edge: it pours off it)
			falls += 1
			if not i or not (r.x0 < i.rect.x0 or r.x1 > i.rect.x1 or r.z0 < i.rect.z0 or r.z1 > i.rect.z1) then
				bad = bad or `{l.id}: not over an island's edge`
			end
		elseif not i or not holds(i.walls, r, 0) then
			bad = bad or `{l.id}: not inside an island's walls`
		end
	end
	for _, s in SandboxMap.Streams do
		for n, p in s.points do
			local i = SandboxMap.islandAt(p.x, p.z, 1)
			if not i or (n < #s.points and not holds(i.walls, around(p.x, p.z, s.width / 2), 0)) then
				bad = bad or `{s.id}: its point {n} off its island`
			end
		end
	end
	for _, w in SandboxMap.Woods do
		if not SandboxMap.islandAt((w.x0 + w.x1) / 2, (w.z0 + w.z1) / 2) then
			bad = bad or `{w.id}: off every island`
		end
	end
	if SandboxMap.Orchard and not SandboxMap.islandAt((SandboxMap.Orchard.x0 + SandboxMap.Orchard.x1) / 2, (SandboxMap.Orchard.z0 + SandboxMap.Orchard.z1) / 2) then
		bad = bad or "the orchard off every island"
	end
	check("every landmark inside its island's walls (the mill's waterfall over its island's edge), the streams, the woods and the orchard on theirs", bad == nil and falls == 1, bad or falls)
end
check("no fields, no motorway, no railway, no roads but the yards (10.6: the sky round every island)", #SandboxMap.Fields == 0 and (function(): boolean
	for _, l in SandboxMap.Landmarks do
		if l.kind == "motorway" or l.kind == "railway" or l.kind == "road" then
			return false
		end
	end
	for _, r in SandboxMap.Roads do
		if not r.yard or not SandboxMap.islandAt((r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2) then
			return false
		end
	end
	return true
end)())

-- ── Room for 16 vans a place (a round's parking) ─────────────────────────────

-- shared/RoundRules.luau's parking on the rounds branch, as the plan has it (design/islands/plan.py parking): the curb's
-- spot first, then beside it, then the rows behind it; each inside the walls (Margin in) and off the house's lot.
local P = Plan.park
local function axes(yaw: number): (number, number, number, number)
	local a = math.rad(yaw)
	return -math.sin(a), -math.cos(a), math.cos(a), -math.sin(a)
end
local function vanRect(x: number, z: number, lx: number, lz: number): Rect
	local hw, hl = P.Width / 2, P.Length / 2
	local ex = math.abs(lx) * hl + math.abs(lz) * hw
	local ez = math.abs(lz) * hl + math.abs(lx) * hw
	return { x0 = x - ex, x1 = x + ex, z0 = z - ez, z1 = z + ez }
end
local function parking(curb: SandboxMap.Spot, zone: Rect, lot: Rect): { Rect }
	local lx, lz, rx, rz = axes(curb.yaw)
	local half = P.Cols // 2
	local found: { { cost: number, rect: Rect } } = {}
	for row = 0, P.Rows - 1 do
		for col = -half, half do
			local x = curb.x + rx * col * P.Across + lx * row * P.Along
			local z = curb.z + rz * col * P.Across + lz * row * P.Along
			local r = vanRect(x, z, lx, lz)
			if holds(zone, r, P.Margin) and not overlaps(r, lot) then
				table.insert(found, { cost = row * (half + 1) * 2 + math.abs(col) * 2 + (if col < 0 then 1 else 0), rect = r })
			end
		end
	end
	table.sort(found, function(a, b): boolean
		return a.cost < b.cost
	end)
	local out: { Rect } = {}
	for _, f in found do
		table.insert(out, f.rect)
	end
	return out
end
-- What a van must not stand on: a landmark (but a waterfall), the house's box, the woods (but their clearings), the
-- orchard, the streams' water.
local function clear(v: Rect, h: SandboxMap.House): boolean
	if overlaps(v, h.box) then
		return false
	end
	for _, l in SandboxMap.Landmarks do
		if l.kind ~= "waterfall" and overlaps(v, { x0 = l.x0, x1 = l.x1, z0 = l.z0, z1 = l.z1 }) then
			return false
		end
	end
	for _, w in SandboxMap.Woods do
		if overlaps(v, w :: any) then
			local inClearing = false
			for _, c in w.clearings do
				inClearing = inClearing or holds(c, v, 0)
			end
			if not inClearing then
				return false
			end
		end
	end
	if SandboxMap.Orchard and overlaps(v, grow(SandboxMap.Orchard, 2)) then
		return false
	end
	for _, s in SandboxMap.Streams do
		for n = 1, #s.points - 1 do
			local a, b = s.points[n], s.points[n + 1]
			local steps = math.max(1, math.floor(math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2) / 2))
			for k = 0, steps do
				local x, z = a.x + (b.x - a.x) * k / steps, a.z + (b.z - a.z) * k / steps
				if overlaps(v, around(x, z, s.width / 2 + 1.5)) then
					return false
				end
			end
		end
	end
	return true
end
do
	local bad: string? = nil
	local least = math.huge
	for _, h in SandboxMap.Houses do
		local zone = SandboxMap.zone(h.id)
		local i = SandboxMap.islandOf(h.id) :: SandboxMap.Island
		local free = 0
		for _, v in parking(h.curb, if zone then zone.rect else i.walls, h.lot) do
			if clear(v, h) and holds(i.walls, v, 0) then
				free += 1
			end
		end
		least = math.min(least, free)
		if free < Plan.vans or free ~= Plan.found[h.id] then
			bad = bad or `{h.id}: {free} vans (the plan found {Plan.found[h.id]})`
		end
	end
	check(`room for {Plan.vans} vans at every place (side by side at its curb and in rows behind it, inside its walls, off its lot and everything solid; the fewest {least})`,
		bad == nil and Plan.vans >= 16, bad)
end

-- ── Under them: the sky, the fall catch's reach ─────────────────────────────

do
	local bad: string? = nil
	for _, i in Islands do
		if IslandLooks.bottom(i) ~= i.top - i.depth or i.top - i.depth <= I.Destroy + 120 then
			bad = bad or `{i.id}: its bottom {i.top - i.depth}`
		end
		if I.Fall.Below >= i.depth or i.depth < 60 then
			bad = bad or `{i.id}: its depth {i.depth}`
		end
	end
	for n, r in SandboxMap.Rocks do
		if r.top - r.depth <= I.Destroy + 120 then
			bad = bad or `rock {n}: its bottom`
		end
		for _, i in Islands do
			if gap(around(r.x, r.z, r.size), i.rect) < 30 then
				bad = bad or `rock {n}: by {i.id}`
			end
		end
	end
	check(`every island's and rock's bottom far over workspace.FallenPartsDestroyHeight (Config.Islands.Destroy {I.Destroy}: the catch long before it)`, bad == nil, bad)
end

-- ── The map's helpers ────────────────────────────────────────────────────────

do
	local bad: string? = nil
	for _, i in Islands do
		if SandboxMap.islandAt(i.x, i.z) ~= i or SandboxMap.groundAt(i.x, i.z) ~= i.top or SandboxMap.island(i.id) ~= i
			or math.abs(SandboxMap.roadAt(i.x, i.z) - (i.top + SandboxMap.RoadTop - SandboxMap.GroundTop)) > EPS then
			bad = bad or i.id
		end
		if SandboxMap.islandAt(i.rect.x1 + 1, i.z) ~= nil or SandboxMap.islandAt(i.rect.x1 + 1, i.z, 2) ~= i then
			bad = bad or `{i.id}: its margin`
		end
	end
	check("SandboxMap.islandAt / groundAt / roadAt / island: an island's middle on it at its top (a stud past its edge: on it within a margin)", bad == nil, bad)
end
check("…off every island: none, the ground's top (the sky: nothing there)", SandboxMap.islandAt(0, 0) == nil and SandboxMap.groundAt(0, 0) == SandboxMap.GroundTop
	and SandboxMap.island("nope") == nil and SandboxMap.islandOf("nope") == nil)

-- ── Their art (shared/IslandLooks.luau) ──────────────────────────────────────

local MATERIALS: { [string]: boolean } = {}
for _, m in IslandLooks.Materials do
	MATERIALS[m] = true
end
do
	local bad: string? = nil
	local B = I.Body
	local names: { [string]: number } = {}
	local total = 0
	for _, i in Islands do
		local pieces = IslandLooks.body(i)
		total += #pieces
		local low = math.huge
		for _, p in pieces do
			names[p.name] = (names[p.name] or 0) + 1
			local x0, x1, y0, y1, z0, z1 = VillageLooks.box(p)
			local reach = if p.name == "IslandBoulder" then B.Out + 6 else 0.01 -- (a boulder turned: its corners a few studs more)
			if x0 < i.rect.x0 - reach or x1 > i.rect.x1 + reach or z0 < i.rect.z0 - reach or z1 > i.rect.z1 + reach then
				bad = bad or `{i.id}: its {p.name} out of its top's rect`
			end
			if y1 > i.top - B.Grass + 0.01 then
				bad = bad or `{i.id}: its {p.name} over its grass's underside`
			end
			if not MATERIALS[p.material] or p.chunk ~= "islands" then
				bad = bad or `{i.id}: its {p.name}'s material {p.material} or chunk`
			end
			if (p.name == "IslandTip" or p.name == "IslandHanging") == p.solid then
				bad = bad or `{i.id}: its {p.name} solid or not`
			end
			low = math.min(low, y0)
		end
		if math.abs(low - IslandLooks.bottom(i)) > 0.01 then
			bad = bad or `{i.id}: its tip at {low}, not {IslandLooks.bottom(i)}`
		end
		if #pieces > 80 then
			bad = bad or `{i.id}: {#pieces} pieces`
		end
	end
	check("every island's rock: the dirt, the stone, the boulders, the taper, its tip and the hanging rocks", names.IslandDirt == #Islands and names.IslandStone == #Islands
		and (names.IslandBoulder or 0) >= 4 * #Islands and names.IslandTaper == I.Body.Taper * #Islands and names.IslandTip == 4 * #Islands
		and (names.IslandHanging or 0) >= 8 * #Islands)
	check(`…inside its top's rect (the boulders' faces Out past it, turned), under its grass, its tip at its bottom, its materials, the tip and the hanging rocks decoration ({total} pieces)`, bad == nil, bad)
	check("…the same each time (its seed's dice)", (function(): boolean
		local a, b = IslandLooks.body(Islands[2]), IslandLooks.body(Islands[2])
		for n, p in a do
			if p.at[1] ~= b[n].at[1] or p.at[2] ~= b[n].at[2] or p.size[1] ~= b[n].size[1] or p.yaw ~= b[n].yaw then
				return false
			end
		end
		return #a == #b
	end)())
end
do
	local bad: string? = nil
	for n, r in SandboxMap.Rocks do
		local pieces = IslandLooks.rock(r)
		local low, high = math.huge, -math.huge
		for _, p in pieces do
			local x0, x1, y0, y1, z0, z1 = VillageLooks.box(p)
			low, high = math.min(low, y0), math.max(high, y1)
			if p.solid or not MATERIALS[p.material] or x0 < r.x - r.size or x1 > r.x + r.size or z0 < r.z - r.size or z1 > r.z + r.size then
				bad = bad or `rock {n}: its {p.name}`
			end
		end
		if math.abs(high - r.top) > 0.01 or math.abs(low - (r.top - r.depth)) > 0.01 then
			bad = bad or `rock {n}: {low} … {high}`
		end
	end
	check("the floating rocks: from their top down to their tip, round their middle, decoration", bad == nil and #SandboxMap.Rocks >= 2, bad)
end
do
	local clouds = IslandLooks.clouds(SandboxMap.Bounds, 1)
	local lowest = math.huge
	for _, i in Islands do
		lowest = math.min(lowest, i.top - i.depth)
	end
	local bad: string? = nil
	for _, p in clouds do
		local _, _, _, y1 = VillageLooks.box(p)
		if p.solid or p.name ~= "Cloud" or not p.alpha or p.alpha <= 0 or y1 >= lowest then
			bad = bad or `a cloud at {p.at[2]}`
		end
	end
	check(`the clouds: soft (see-through) puffs under every island (under {lowest}), decoration`, bad == nil and #clouds >= I.Clouds.Count, bad)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
