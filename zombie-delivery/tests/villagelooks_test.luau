-- 8.9 SANDBOX, Jinočany: the village's art kit (shared/VillageLooks.luau, Config.Village; nothing of it is on the map
-- yet). Every house kind within its part budget (a terraced row's for each of its houses, one of the six to empty
-- Budget.Rich), every piece inside its box, nothing under the ground and nothing floating; the doors on the front wall
-- (+Z in the house's frame) and turned by the yaw onto plan.json's doors; the same seed the same house, and the seeds
-- varied; nothing alpine; only real Roblox materials and the shapes a builder knows; every house of plan.json
-- (JinocanyPlan.luau, written by tests/run_tests.py) within its budget, the terraced ones in their groups of four; the
-- landmarks in their plan rects (the green clear of its chapel, the pond's water a hair under its rim); the trees, the
-- tree lines, the orchard, the field tiles and the far view (all of it outside the Bounds); the streaming chunks; and
-- the step-1 village's parts within Budget.Step1 (with Kept, the map's 2,500). Run with tests/run_tests.py.
local Config = require("./Config")
local SandboxScenery = require("./SandboxScenery")
local V = require("./VillageLooks")
local Plan = require("./JinocanyPlan")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

type Box = V.Box
type Piece = V.Piece
local C = Config.Village
local EPS = 1e-6
local TOUCH = 0.02 -- (two pieces closer than this touch)
-- Enum.Material's names (Roblox's; the definitions' EnumMaterial)
local ROBLOX_MATERIALS = { "Air", "Asphalt", "Basalt", "Brick", "Cardboard", "Carpet", "CeramicTiles", "ClayRoofTiles", "Cobblestone", "Concrete", "CorrodedMetal", "CrackedLava", "DiamondPlate", "Fabric", "Foil", "ForceField", "Glacier", "Glass", "Granite", "Grass", "Ground", "Ice", "LeafyGrass", "Leather", "Limestone", "Marble", "Metal", "Mud", "Neon", "Pavement", "Pebble", "Plaster", "Plastic", "Rock", "RoofShingles", "Rubber", "Salt", "Sand", "Sandstone", "Slate", "SmoothPlastic", "Snow", "Water", "Wood", "WoodPlanks" }
local ALPINE_NAMES = { "spruce", "fir", "needle", "snow", "chalet", "balcony", "geranium", "shingle", "peak", "alp", "cowbell", "pine", "glacier" }
local ALPINE_MATERIALS = { Snow = true, Glacier = true, Ice = true }

local function set(list: { string }): { [string]: boolean }
	local s = {}
	for _, v in list do
		s[v] = true
	end
	return s
end
local MATERIALS, SHAPES = set(V.Materials), set(V.Shapes)

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- ── Every piece: its fields, its material, its shape, nothing alpine ─────────

local seen = 0
local badPiece: string? = nil
local alpine: string? = nil
local function inspect(where: string, pieces: { Piece })
	for _, p in pieces do
		seen += 1
		local s = p.size
		local why: string? = nil
		if not MATERIALS[p.material] then
			why = `material {p.material}`
		elseif not SHAPES[p.shape] then
			why = `shape {p.shape}`
		elseif #s ~= 3 or #p.at ~= 3 or #p.color ~= 3 then
			why = "size, at or colour not three numbers"
		elseif math.min(s[1], s[2], s[3]) <= 0 or math.max(s[1], s[2], s[3]) > 2048 then
			why = `size {s[1]} × {s[2]} × {s[3]} (a part is 0 … 2048)`
		elseif p.shape == "Ball" and not (math.abs(s[1] - s[2]) < EPS and math.abs(s[2] - s[3]) < EPS) then
			why = "a ball not round"
		elseif p.shape == "Cylinder" and math.abs(s[2] - s[3]) > EPS then
			why = "a cylinder not round (its Y and Z)"
		elseif type(p.chunk) ~= "string" or p.chunk == "" then
			why = "no chunk"
		elseif type(p.solid) ~= "boolean" then
			why = "solid not a boolean"
		end
		for _, c in p.color do
			if c ~= math.floor(c) or c < 0 or c > 255 then
				why = `colour {p.color[1]}, {p.color[2]}, {p.color[3]}`
			end
		end
		if why and not badPiece then
			badPiece = `{where} {p.name}: {why}`
		end
		local name = string.lower(p.name)
		for _, word in ALPINE_NAMES do
			if string.find(name, word, 1, true) and not alpine then
				alpine = `{where} {p.name}`
			end
		end
		if ALPINE_MATERIALS[p.material] and not alpine then
			alpine = `{where} {p.name} ({p.material})`
		end
	end
end

-- Nothing under the ground (but the ground itself), nothing floating: every piece stands on the ground or touches a
-- piece that does (their boxes). Returns the first floating piece's name, or nil.
local function floating(pieces: { Piece }): string?
	local boxes = {}
	for i, p in pieces do
		local x0, x1, y0, y1, z0, z1 = V.box(p)
		boxes[i] = { x0, x1, y0, y1, z0, z1 }
	end
	local held = {}
	local todo = {}
	for i, b in boxes do
		if b[3] <= EPS or pieces[i].ground then
			held[i] = true
			table.insert(todo, i)
		end
	end
	while #todo > 0 do
		local i = table.remove(todo) :: number
		local a = boxes[i]
		for j, b in boxes do
			if not held[j] and a[1] <= b[2] + TOUCH and b[1] <= a[2] + TOUCH and a[3] <= b[4] + TOUCH and b[3] <= a[4] + TOUCH and a[5] <= b[6] + TOUCH and b[5] <= a[6] + TOUCH then
				held[j] = true
				table.insert(todo, j)
			end
		end
	end
	for i, p in pieces do
		if not held[i] then
			return p.name
		end
	end
	return nil
end

local function underground(pieces: { Piece }): string?
	for _, p in pieces do
		local _, _, y0, y1 = V.box(p)
		if p.ground then
			if math.abs(y1) > EPS then
				return `{p.name} (the ground's top at {y1})`
			end
		elseif y0 < -EPS then
			return `{p.name} ({y0})`
		end
	end
	return nil
end

-- The first piece (in its frame) outside the box w × d round the frame's middle, or nil.
local function outside(pieces: { Piece }, w: number, d: number): string?
	for _, p in pieces do
		local x0, x1, _, _, z0, z1 = V.box(p)
		if x0 < -w / 2 - EPS or x1 > w / 2 + EPS or z0 < -d / 2 - EPS or z1 > d / 2 + EPS then
			return `{p.name} ({string.format("%.2f … %.2f, %.2f … %.2f", x0, x1, z0, z1)} in {w} × {d})`
		end
	end
	return nil
end

local function count(pieces: { Piece }, name: string): number
	local n = 0
	for _, p in pieces do
		if p.name == name then
			n += 1
		end
	end
	return n
end

local function first(pieces: { Piece }, name: string): Piece?
	for _, p in pieces do
		if p.name == name then
			return p
		end
	end
	return nil
end

-- ── The houses: budgets, their boxes, the ground, the doors, the dice ─────────

local SAMPLE: { [string]: { number } } = { old = { 30, 24 }, row = { 72, 26 }, modern = { 28, 22 } }
local function sampleBox(kind: string, yaw: number): Box
	local w, d = SAMPLE[kind][1], SAMPLE[kind][2]
	-- (the plan's way: a house looking east or west has its width along z)
	if yaw == 90 or yaw == 270 then
		w, d = d, w
	end
	return { x0 = 100, x1 = 100 + w, z0 = -50, z1 = -50 + d }
end

do
	local over, out, low, loose, doorBad = nil :: string?, nil :: string?, nil :: string?, nil :: string?, nil :: string?
	local most: { [string]: number } = {}
	local calls = 0
	for _, kind in V.Houses do
		for _, rich in { false, true } do
			for _, yaw in { 0, 90, 180, 270 } do
				for seed = 1, 40 do
					local box = sampleBox(kind, yaw)
					local f = V.frame(box, yaw)
					local units = if kind == "row" then 4 else 1
					local pieces = V.house(kind, box, yaw, seed * 7 + yaw, { rich = rich, richUnit = if rich then 1 + seed % 4 else nil })
					calls += 1
					inspect(`{kind} {seed}`, pieces)
					local key = kind .. (if rich then " rich" else "")
					most[key] = math.max(most[key] or 0, #pieces)
					if #pieces > V.budget(kind, units, rich) and not over then
						over = `{key}: {#pieces} parts`
					end
					out = out or outside(pieces, f.w, f.d)
					low = low or underground(pieces)
					loose = loose or floating(pieces)
					-- the doors: on the front wall (the body's +Z face), facing +Z unturned; one a house
					local body = first(pieces, "House") or first(pieces, "Row")
					local doors = 0
					for _, p in pieces do
						if p.tag == "door" then
							doors += 1
							local _, _, _, _, z0, z1 = V.box(p)
							local _, _, _, _, _, front = V.box(body :: Piece)
							local turned = p.turn ~= nil and (p.turn[1] ~= 0 or p.turn[2] ~= 0 or p.turn[3] ~= 0)
							if turned or p.yaw ~= 0 or math.abs(z0 - front) > 0.01 or z1 <= front or p.size[3] > math.min(p.size[1], p.size[2]) then
								doorBad = doorBad or `{key} {seed}: door at z {z0} … {z1}, the front wall at {front}`
							end
						end
					end
					if doors ~= units then
						doorBad = doorBad or `{key} {seed}: {doors} doors for {units} houses`
					end
				end
			end
		end
	end
	check(`every house kind within its budget over {calls} houses (old {most.old}, rich {most["old rich"]} / {C.Budget.Rich}; a row of four {most.row}, rich {most["row rich"]} / {V.budget("row", 4, true)}; modern {most.modern}, rich {most["modern rich"]})`, over == nil, over)
	check("old and modern at most 15 parts, the six to empty at most 25", C.Budget.old == 15 and C.Budget.modern == 15 and C.Budget.row == 15 and C.Budget.Rich == 25 and (most.old or 99) <= 15 and (most["old rich"] or 99) <= 25 and (most.modern or 99) <= 15 and (most["modern rich"] or 99) <= 25)
	check("a terraced row: one body for the group, far under 15 a house", (most.row or 99) <= 4 * 10)
	check("every piece of a house inside its box (its roof's eaves too)", out == nil, out)
	check("nothing of a house under the ground", low == nil, low)
	check("nothing of a house floating (each on the ground or on a piece that is)", loose == nil, loose)
	check("the doors on the front wall facing +Z, unturned in the house's frame: one for each house", doorBad == nil, doorBad)
end

-- One terraced house alone (a box RowUnit wide), and the row's doors in the middle of each house
do
	local box = { x0 = 0, x1 = C.RowUnit, z0 = 0, z1 = 26 }
	local one = V.house("row", box, 180, 3)
	local f = V.frame(box, 180)
	check(`one terraced house alone: {#one} parts, one door`, #one <= C.Budget.row and #V.doorSpots(one, box, 180) == 1 and outside(one, f.w, f.d) == nil)
	local four = V.house("row", { x0 = 0, x1 = 4 * C.RowUnit, z0 = 0, z1 = 26 }, 180, 3)
	local ok = true
	for _, p in four do
		if p.tag == "door" then
			local unit = p.unit :: number
			ok = ok and math.abs(p.at[1] - (-2 * C.RowUnit + (unit - 0.5) * C.RowUnit)) < EPS
		end
	end
	check(`a row of four: one body ({count(four, "Row")}), four doors each in its house's middle`, ok and count(four, "Row") == 1 and #V.doorSpots(four, { x0 = 0, x1 = 72, z0 = 0, z1 = 26 }, 180) == 4)
end

-- The yaw: a piece's box on the map is its box in the frame turned (a roof slab tilted about X, a wedge turned 180°)
do
	local box = { x0 = 0, x1 = 24, z0 = 0, z1 = 30 }
	local ok, why = true, nil :: string?
	for _, yaw in { 0, 90, 180, 270 } do
		local f = V.frame(box, yaw)
		local pieces = V.house("old", box, yaw, 11)
		for i, q in V.place(pieces, box, yaw) do
			local x0, x1, y0, y1, z0, z1 = V.box(pieces[i])
			local a0, a1, b0, b1, c0, c1 = V.box(q)
			-- the frame's box corners on the map
			local t = math.rad(f.turn)
			local xs, zs = {}, {}
			for _, c in { { x0, z0 }, { x1, z0 }, { x0, z1 }, { x1, z1 } } do
				table.insert(xs, f.x + math.cos(t) * c[1] + math.sin(t) * c[2])
				table.insert(zs, f.z - math.sin(t) * c[1] + math.cos(t) * c[2])
			end
			local mx0, mx1 = math.min(table.unpack(xs)), math.max(table.unpack(xs))
			local mz0, mz1 = math.min(table.unpack(zs)), math.max(table.unpack(zs))
			if math.abs(a0 - mx0) + math.abs(a1 - mx1) + math.abs(c0 - mz0) + math.abs(c1 - mz1) + math.abs(b0 - y0) + math.abs(b1 - y1) > 1e-6 then
				ok, why = false, `yaw {yaw}: {q.name}`
			end
			if a0 < box.x0 - EPS or a1 > box.x1 + EPS or c0 < box.z0 - EPS or c1 > box.z1 + EPS then
				ok, why = false, `yaw {yaw}: {q.name} off its box on the map`
			end
		end
	end
	check("placed on the map (VillageLooks.place), every piece's box is its box in the frame turned, inside the plan's box", ok, why)
end

-- The dice: the same seed the same house; the seeds give variety
do
	local same = true
	for _, kind in V.Houses do
		for seed = 1, 12 do
			local box = sampleBox(kind, 180)
			same = same and deepEqual(V.house(kind, box, 180, seed, { rich = seed % 2 == 0 }), V.house(kind, box, 180, seed, { rich = seed % 2 == 0 }))
		end
	end
	same = same and deepEqual(V.landmark("chapel", { x0 = 0, x1 = 24, z0 = 0, z1 = 40 }, 180, 5), V.landmark("chapel", { x0 = 0, x1 = 24, z0 = 0, z1 = 40 }, 180, 5))
	same = same and deepEqual(V.tree("linden", 3, 4, 77), V.tree("linden", 3, 4, 77)) and deepEqual(V.horizon(Plan.bounds, 9), V.horizon(Plan.bounds, 9))
	check("the same seed gives the same house, landmark, tree and far view", same)
	local renders, tiles, along, roofs = {}, {}, {}, {}
	for seed = 1, 80 do
		local pieces = V.house("old", sampleBox("old", 180), 180, V.seedOf(`Hlavní_n_{seed}`))
		local body, ridge, roof = first(pieces, "House"), first(pieces, "Ridge"), first(pieces, "Roof")
		renders[table.concat((body :: Piece).color, ",")] = true
		tiles[table.concat((roof :: Piece).color, ",")] = true
		along[if (ridge :: Piece).size[1] > (ridge :: Piece).size[3] then "x" else "z"] = true
		local m = V.house("modern", sampleBox("modern", 180), 180, seed)
		roofs[if first(m, "RoofWedge") then "mono" else "flat"] = true
	end
	local function size(t: { [string]: boolean }): number
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end
	check(`the seeds vary the old houses ({size(renders)} renders, {size(tiles)} tile colours, the eaves or the gable to the street) and the new builds' roofs`, size(renders) >= 4 and size(tiles) >= 3 and along.x and along.z and roofs.mono and roofs.flat)
	check("a plan id's seed is steady and differs from its neighbour's", V.seedOf("Hlavní_n_5") == V.seedOf("Hlavní_n_5") and V.seedOf("Hlavní_n_5") ~= V.seedOf("Hlavní_n_6"))
end

-- ── Every house of plan.json ───────────────────────────────────────────────

do
	local over, out, loose, doorBad = nil :: string?, nil :: string?, nil :: string?, nil :: string?
	local kinds: { [string]: number } = {}
	for _, h in Plan.houses do
		kinds[h.kind] = (kinds[h.kind] or 0) + 1
		local pieces = V.house(h.kind, h.box, h.yaw, V.seedOf(h.id), { rich = h.enter })
		inspect(h.id, pieces)
		local f = V.frame(h.box, h.yaw)
		if #pieces > V.budget(h.kind, 1, h.enter) then
			over = over or `{h.id}: {#pieces}`
		end
		out = out or outside(pieces, f.w, f.d)
		loose = loose or floating(pieces) or underground(pieces)
		-- turned by its yaw, its door on plan.json's (just in front of it), looking out the same way
		local spots = V.doorSpots(pieces, h.box, h.yaw)
		local s = spots[1]
		if #spots ~= 1 or math.sqrt((s.x - h.door.x) ^ 2 + (s.z - h.door.z) ^ 2) > 2 or s.yaw ~= h.door.yaw then
			doorBad = doorBad or `{h.id}: {if s then string.format("%.1f, %.1f yaw %d", s.x, s.z, s.yaw) else "no door"} for {h.door.x}, {h.door.z} yaw {h.door.yaw}`
		end
		-- the door's way out on the map (local +Z turned by the frame) is the plan door's look (yaw 0 north = -z)
		local t = math.rad(f.turn)
		local y = math.rad(h.door.yaw)
		if math.abs(math.sin(t) + math.sin(y)) > 1e-9 or math.abs(math.cos(t) + math.cos(y)) > 1e-9 then
			doorBad = doorBad or `{h.id}: +Z turned {f.turn} does not look {h.door.yaw}`
		end
	end
	check(`every house of plan.json builds within its budget ({#Plan.houses}: {kinds.old or 0} old, {kinds.row or 0} terraced, {kinds.modern or 0} modern; the ones to empty rich)`, over == nil and #Plan.houses > 0, over)
	check("each inside its plan box, on the ground, nothing floating", out == nil and loose == nil, out or loose)
	check("each house's door, turned by its yaw, on plan.json's door (within 2 studs), looking out the same way", doorBad == nil, doorBad)
end

-- The terraced houses in their groups of four: one body each, every row house in one group, the doors on the plan's
do
	local groups = V.rowGroups(Plan.houses)
	local rows: { [string]: any } = {}
	for _, h in Plan.houses do
		if h.kind == "row" then
			rows[h.id] = h
		end
	end
	local seenIds: { [string]: number } = {}
	local over, doorBad, sizes = nil :: string?, nil :: string?, {} :: { [number]: number }
	local most = 0
	for _, g in groups do
		sizes[#g.ids] = (sizes[#g.ids] or 0) + 1
		for _, id in g.ids do
			seenIds[id] = (seenIds[id] or 0) + 1
		end
		local rich = g.richUnit ~= nil
		local pieces = V.house("row", g.box, g.yaw, g.seed, { rich = rich, richUnit = g.richUnit })
		inspect(`row group {g.ids[1]}`, pieces)
		most = math.max(most, #pieces)
		local f = V.frame(g.box, g.yaw)
		if #pieces > V.budget("row", #g.ids, rich) or outside(pieces, f.w, f.d) or floating(pieces) then
			over = over or `{g.ids[1]} (+{#g.ids - 1}): {#pieces}`
		end
		local spots = V.doorSpots(pieces, g.box, g.yaw)
		if #spots ~= #g.ids then
			doorBad = doorBad or `{g.ids[1]}: {#spots} doors for {#g.ids}`
		end
		for _, s in spots do
			local h = rows[g.ids[s.unit :: number]]
			if not h or math.sqrt((s.x - h.door.x) ^ 2 + (s.z - h.door.z) ^ 2) > 2 or s.yaw ~= h.door.yaw then
				doorBad = doorBad or `{g.ids[1]} unit {s.unit}`
			end
		end
		if rich and not rows[g.ids[g.richUnit :: number]].enter then
			doorBad = doorBad or `{g.ids[1]}: its rich house is not the one to empty`
		end
	end
	local once = true
	for id in rows do
		once = once and seenIds[id] == 1
	end
	local shape = {}
	for n, c in sizes do
		table.insert(shape, `{c} × {n}`)
	end
	table.sort(shape)
	check(`plan.json's terraced houses in {#groups} groups ({table.concat(shape, ", ")}), each house in one group, at most four`, once and #groups > 0 and sizes[5] == nil)
	check(`each group one body within its budget (at most {most} parts), in its box, nothing floating`, over == nil, over)
	check("each group's doors on its houses' plan.json doors (the one to empty the rich one)", doorBad == nil, doorBad)
end

-- ── The landmarks ──────────────────────────────────────────────────────────

local function planMark(id: string): any
	for _, l in Plan.landmarks do
		if l.id == id then
			return l
		end
	end
	return nil
end

do
	local chapelRect = planMark("chapel").rect
	local hornicka: any = nil
	for _, r in Plan.roads do
		if r.name == "Hornická" then
			hornicka = r
		end
	end
	local barrierBox, barrierYaw = V.barrierAt(hornicka.rect)
	local marks = {
		{ kind = "chapel", rect = chapelRect },
		{ kind = "green", rect = planMark("green").rect },
		{ kind = "pond", rect = planMark("pond").rect },
		{ kind = "shop", rect = planMark("drugstore").rect },
		{ kind = "motorway", rect = planMark("d5").rect },
		{ kind = "hardware", rect = planMark("hardware").rect },
		{ kind = "barrier", rect = barrierBox, yaw = barrierYaw },
	}
	local counts = {}
	for _, m in marks do
		local yaw = m.yaw or C.Facing[m.kind]
		local pieces = V.landmark(m.kind, m.rect, yaw, 21, { chapel = chapelRect })
		inspect(m.kind, pieces)
		local f = V.frame(m.rect, yaw)
		table.insert(counts, `{m.kind} {#pieces}`)
		check(`{m.kind}: {#pieces} parts within its budget ({C.Budget[m.kind]})`, #pieces <= V.budget(m.kind) and #pieces > 0)
		local why = outside(pieces, f.w, f.d) or underground(pieces) or floating(pieces)
		check(`{m.kind}: inside its plan rect, on the ground, nothing floating`, why == nil, why)
		for _, s in V.doorSpots(pieces, m.rect, yaw) do
			check(`{m.kind}: its door looks out at its front (yaw {yaw})`, s.yaw == yaw)
		end
		if m.kind == "motorway" then
			check("the D5 kept on every client (chunk far)", pieces[1].chunk == "far")
		elseif m.kind ~= "motorway" then
			check(`{m.kind}: in the chunk of its middle`, pieces[1].chunk == V.chunkOf(f.x, f.z))
		end
	end
	-- the green: nothing of it on its chapel; the contracts noticeboard to the road; the cross, the lindens
	local green = V.place(V.landmark("green", planMark("green").rect, C.Facing.green, 21, { chapel = chapelRect }), planMark("green").rect, C.Facing.green)
	local on: string? = nil
	for _, p in green do
		local x0, x1, _, _, z0, z1 = V.box(p)
		if x0 < chapelRect.x1 - EPS and x1 > chapelRect.x0 + EPS and z0 < chapelRect.z1 - EPS and z1 > chapelRect.z0 + EPS and not on then
			on = p.name
		end
	end
	local board = first(green, "Noticeboard")
	check("the green leaves its chapel's rect free", on == nil, on)
	check(`the green's noticeboard for the move contracts, "{board and board.text}", looking to Hlavní; the cross, six lindens, three benches`, board ~= nil and board.tag == "contracts" and count(green, "CrossShaft") == 1 and count(green, "Crown") == 6 and count(green, "BenchSeat") == 3)
	local chapel = V.landmark("chapel", chapelRect, C.Facing.chapel, 21)
	check("the chapel: a tower with its spire and cross, a nave, an apse", count(chapel, "Tower") == 1 and count(chapel, "Spire") == 4 and count(chapel, "CrossArm") == 1 and count(chapel, "Nave") == 1 and count(chapel, "Apse") == 1)
	-- the pond: the water a hair under the rim, all of it inside the rim's outer edge
	local pond = V.landmark("pond", planMark("pond").rect, C.Facing.pond, 21)
	local rimTop, waterTop = -math.huge, -math.huge
	local rx0, rx1, rz0, rz1 = math.huge, -math.huge, math.huge, -math.huge
	local wx0, wx1, wz0, wz1 = math.huge, -math.huge, math.huge, -math.huge
	for _, p in pond do
		local x0, x1, _, y1, z0, z1 = V.box(p)
		if p.name == "Rim" then
			rimTop = math.max(rimTop, y1)
			rx0, rx1, rz0, rz1 = math.min(rx0, x0), math.max(rx1, x1), math.min(rz0, z0), math.max(rz1, z1)
		elseif p.name == "Water" then
			waterTop = math.max(waterTop, y1)
			wx0, wx1, wz0, wz1 = math.min(wx0, x0), math.max(wx1, x1), math.min(wz0, z0), math.max(wz1, z1)
		end
	end
	check(string.format("the pond's water a hair under its rim (%.2f under)", rimTop - waterTop), rimTop - waterTop > 0 and rimTop - waterTop <= 0.1)
	check("the water inside the rim's outer edge", wx0 > rx0 and wx1 < rx1 and wz0 > rz0 and wz1 < rz1)
	local shop = V.landmark("shop", planMark("drugstore").rect, C.Facing.shop, 21)
	local sign = first(shop, "Sign")
	check(`the Corner Drugstore's sign: "{sign and sign.text}" (a made-up shop, no real brand)`, sign ~= nil and sign.tag == "sign" and sign.text == "CORNER DRUGSTORE")
	local barrier = V.landmark("barrier", barrierBox, barrierYaw, 21)
	local closed = first(barrier, "ClosedBoard")
	check(`Hornická's barrier across the road at its west end, ROAD CLOSED, looking east to the village`, closed ~= nil and closed.text == "ROAD CLOSED" and barrierYaw == 270 and barrierBox.x0 > hornicka.rect.x0 and barrierBox.z0 == hornicka.rect.z0 and barrierBox.z1 == hornicka.rect.z1)
	local d5 = V.landmark("motorway", planMark("d5").rect, C.Facing.motorway, 21)
	check("the D5: its embankment, two carriageways, the noise wall on the village's side", count(d5, "Embankment") == 2 and count(d5, "Carriageway") == 2 and count(d5, "NoiseWall") >= 4)
	local ok = pcall(V.landmark, "spruce", chapelRect, 0, 1)
	check(`an unknown landmark kind is an error ({table.concat(counts, ", ")})`, not ok)
end

-- ── Trees, tree lines, the orchard ─────────────────────────────────────────

do
	local bad: string? = nil
	for _, kind in V.Trees do
		local T = C.Trees[kind]
		for seed = 1, 30 do
			local x, z = seed * 13, -seed * 7
			local pieces = V.tree(kind, x, z, seed)
			inspect(`tree {kind}`, pieces)
			local height, radius = V.treeSize(kind, seed)
			local trunk, crown = first(pieces, "Trunk"), first(pieces, "Crown")
			local why: string? = nil
			if #pieces ~= C.Budget.tree or not trunk or not crown then
				why = `{#pieces} pieces`
			elseif height < T.Height[1] - EPS or height > T.Height[2] + EPS then
				why = `height {height}`
			else
				local x0, x1, y0, y1, z0, z1 = V.box(crown)
				local _, _, ty0, ty1 = V.box(trunk)
				-- (the crown's top the tree's height, within its radius; the trunk from the ground into the crown)
				if math.abs(y1 - height) > 1e-6 or math.abs(ty0) > EPS or math.max(x1 - x, x - x0, z1 - z, z - z0) > radius + EPS or ty1 <= y0 + 0.5 then
					why = "its crown or its trunk"
				elseif floating(pieces) or underground(pieces) then
					why = "floating"
				elseif trunk.chunk ~= V.chunkOf(x, z) then
					why = "its chunk"
				end
			end
			if why and not bad then
				bad = `{kind} {seed}: {why}`
			end
		end
	end
	check(`the trees ({table.concat(V.Trees, ", ")}): a trunk from the ground into one round crown, their heights Config's, in their chunk`, bad == nil, bad)
	local far, mix, total = nil :: string?, {}, 0
	for _, line in Plan.lines do
		local spots = V.lineTrees(line.points, line.kind, 4)
		total += #spots
		for _, s in spots do
			mix[s.kind] = true
			-- near its line: within a few studs of one of its legs
			local near = math.huge
			for i = 1, #line.points - 1 do
				local a, b = line.points[i], line.points[i + 1]
				local dx, dz = b.x - a.x, b.z - a.z
				local t = math.clamp(((s.x - a.x) * dx + (s.z - a.z) * dz) / (dx * dx + dz * dz), 0, 1)
				near = math.min(near, math.sqrt((a.x + dx * t - s.x) ^ 2 + (a.z + dz * t - s.z) ^ 2))
			end
			if near > 6 or (line.kind == "alley" and s.kind ~= "fruit") then
				far = far or `{line.kind} {s.kind} {near}`
			end
		end
	end
	check(`plan.json's tree lines: {total} trees on their lines (windbreaks of lindens, oaks, birches and poplars; alleys of fruit trees)`, far == nil and mix.linden and mix.oak and mix.birch and mix.poplar and mix.fruit, far)
	local rect = planMark("orchard").rect
	local spots = V.orchard(rect, 4)
	local inOrchard = #spots > 20
	for _, s in spots do
		local _, radius = V.treeSize(s.kind, s.seed)
		inOrchard = inOrchard and s.kind == "fruit" and s.x - radius >= rect.x0 and s.x + radius <= rect.x1 and s.z - radius >= rect.z0 and s.z + radius <= rect.z1
	end
	check(`the orchard: {#spots} fruit trees in rows, their crowns inside it`, inOrchard)
end

-- ── The ground: field tiles; the far view ──────────────────────────────────

do
	local bad: string? = nil
	for _, field in Plan.fields do
		local pieces = V.field(field.kind, field.rect, 2)
		inspect(`field {field.kind}`, pieces)
		local tile = pieces[1]
		local x0, x1, _, y1, z0, z1 = V.box(tile)
		local r = field.rect
		if #pieces > C.Budget.field or not tile.ground or tile.chunk ~= "ground" or math.abs(y1) > EPS or x0 ~= r.x0 or x1 ~= r.x1 or z0 ~= r.z0 or z1 ~= r.z1 then
			bad = bad or `{field.kind}: the tile`
		end
		for i = 2, #pieces do
			local a0, a1, b0, _, c0, c1 = V.box(pieces[i])
			if a0 < r.x0 or a1 > r.x1 or c0 < r.z0 or c1 > r.z1 or math.abs(b0) > EPS or pieces[i].ground then
				bad = bad or `{field.kind}: a row`
			end
		end
		bad = bad or floating(pieces)
	end
	check(`plan.json's {#Plan.fields} fields: each a tile of the ground in its crop's colour (top at the ground's), its rows on it`, bad == nil, bad)
	check("the crops: rapeseed yellow, grain gold, ploughed brown", C.Palette.Crops.rapeseed[1] > C.Palette.Crops.rapeseed[3] + 120 and C.Palette.Crops.wheat[1] > C.Palette.Crops.wheat[3] + 80 and C.Palette.Crops.ploughed[1] < 140)
	local far = V.horizon(Plan.bounds, 1)
	inspect("far", far)
	local b = Plan.bounds
	local inside: string? = nil
	for _, p in far do
		local x0, x1, _, _, z0, z1 = V.box(p)
		if x1 > b.x0 + EPS and x0 < b.x1 - EPS and z1 > b.z0 + EPS and z0 < b.z1 - EPS then
			inside = inside or p.name
		end
		if p.chunk ~= "far" then
			inside = inside or `{p.name}'s chunk`
		end
	end
	check(`the far view: {#far} parts (at most {C.Budget.Horizon}), all outside the Bounds, kept on every client`, #far <= C.Budget.Horizon and inside == nil, inside)
	local why = underground(far) or floating(far)
	check("the far view on the ground, nothing floating (its wires on the pylons' arms)", why == nil, why)
	check("the far view: far fields, tree lines, pylons, far roofs and a church tower, no peaks", count(far, "FarField") >= 8 and count(far, "FarTrees") >= 6 and count(far, "PylonArm") >= 6 and count(far, "FarRoof") >= 10 and count(far, "FarChurch") == 1)
end

-- ── All of it ──────────────────────────────────────────────────────────────

check(`every piece looked at ({seen}): a real Roblox material (VillageLooks.Materials), a shape the builder knows, a part's size, a colour, a chunk`, badPiece == nil, badPiece)
do
	local real = set(ROBLOX_MATERIALS)
	local unknown: string? = nil
	for _, m in V.Materials do
		if not real[m] then
			unknown = m
		end
	end
	check(`VillageLooks.Materials are all Enum.Material's ({#V.Materials})`, unknown == nil, unknown)
end
check("nothing alpine: no spruce, fir, snow, chalet, balcony or geraniums, no snow or ice", alpine == nil, alpine)

-- The step-1 village: every part VillageLooks gives it (plan.json's step-1 houses, the rows in their groups; the
-- step-1 landmarks and Hornická's barrier; the tree lines and the orchard; the fields; the far view)
do
	local census = { houses = 0, rows = 0, landmarks = 0, trees = 0, fields = 0, far = 0 }
	for _, h in Plan.houses do
		if h.step == 1 and h.kind ~= "row" then
			census.houses += #V.house(h.kind, h.box, h.yaw, V.seedOf(h.id), { rich = h.enter })
		end
	end
	for _, g in V.rowGroups(Plan.houses) do
		if g.step == 1 then
			census.rows += #V.house("row", g.box, g.yaw, g.seed, { rich = g.richUnit ~= nil, richUnit = g.richUnit })
		end
	end
	local chapelRect = planMark("chapel").rect
	for _, l in Plan.landmarks do
		if l.step == 1 and C.Facing[l.kind] then
			census.landmarks += #V.landmark(l.kind, l.rect, C.Facing[l.kind], V.seedOf(l.id), { chapel = chapelRect })
		end
	end
	for _, r in Plan.roads do
		if r.name == "Hornická" then
			local box, yaw = V.barrierAt(r.rect)
			census.landmarks += #V.landmark("barrier", box, yaw, 1)
		end
	end
	for n, line in Plan.lines do
		census.trees += C.Budget.tree * #V.lineTrees(line.points, line.kind, n)
	end
	census.trees += C.Budget.tree * #V.orchard(planMark("orchard").rect, 1)
	for n, field in Plan.fields do
		census.fields += #V.field(field.kind, field.rect, n)
	end
	census.far = #V.horizon(Plan.bounds, 1)
	local total = census.houses + census.rows + census.landmarks + census.trees + census.fields + census.far
	print(string.format("INFO  the step-1 village: %d parts (houses %d, terraced rows %d, landmarks %d, trees %d, fields %d, the far view %d)",
		total, census.houses, census.rows, census.landmarks, census.trees, census.fields, census.far))
	local theirs = V.census(Plan :: any, 1)
	check(`VillageLooks.census counts the same ({theirs.total}: tools/perf/sandbox_count.py's projection)`, theirs.total == total and theirs.houses == census.houses
		and theirs.rows == census.rows and theirs.landmarks == census.landmarks and theirs.trees == census.trees and theirs.far == census.far, theirs.total)
	local later = V.census(Plan :: any, 3)
	check(`steps 2 and 3 add to it ({later.total} parts with every house and Sýkorka)`, later.total > theirs.total and later.landmarks > theirs.landmarks)
	check(`the step-1 village within Budget.Step1 ({total} parts, at most {C.Budget.Step1})`, total <= C.Budget.Step1, total)
	check(`with what the map keeps (Kept {C.Budget.Kept}) within the map's budget ({C.Budget.Step1} + {C.Budget.Kept} ≤ {SandboxScenery.Budget})`, C.Budget.Step1 + C.Budget.Kept <= SandboxScenery.Budget)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
