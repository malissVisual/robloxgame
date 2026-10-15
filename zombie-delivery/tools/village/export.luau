-- 8.9: the Jinočany village's looks for design/jinocany/looks/ (tools/village/preview.py copies this as main.luau next
-- to shared/VillageLooks.luau, shared/Config.luau and Plan.luau, plan.json as Luau). Builds every shot with the real
-- VillageLooks (each kind alone, a sample street of plan.json, the whole step-1 village) and prints each as one "SHOT"
-- JSON line: its name, its caption, its camera and its parts on the map (p the middle, r the rotation's rows, s the
-- size, c the colour, mat, shape, t the transparency). Context the village does not build (the roads, the lawns, today's
-- warehouses and farmstead as plain boxes) is drawn from plan.json for the picture only.
local V = require("./VillageLooks")
local Config = require("./Config")
local Plan = require("./Plan")
local C = Config.Village
local P = C.Palette

type Piece = V.Piece
type Box = V.Box
type Part = { p: { number }, r: { number }, s: { number }, c: { number }, mat: string, shape: string, t: number }

local ROAD_TOP = 0.4 -- (SandboxMap.RoadTop)
local MEADOW = { 96, 138, 60 } -- (SandboxScenery.Colors.Meadow)
local LAWN = { 108, 150, 64 }

-- A piece's rotation (its yaw about Y, then CFrame.Angles(turn)), row-major.
local function matrix(p: Piece): { number }
	local t = p.turn or { 0, 0, 0 }
	local ax, ay, az = math.rad(t[1]), math.rad(t[2]), math.rad(t[3])
	local cx, sx, cy, sy, cz, sz = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay), math.cos(az), math.sin(az)
	local r = {
		{ cy * cz, -cy * sz, sy },
		{ cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy },
		{ sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy },
	}
	local yaw = math.rad(p.yaw)
	local c, s = math.cos(yaw), math.sin(yaw)
	return {
		c * r[1][1] + s * r[3][1], c * r[1][2] + s * r[3][2], c * r[1][3] + s * r[3][3],
		r[2][1], r[2][2], r[2][3],
		-s * r[1][1] + c * r[3][1], -s * r[1][2] + c * r[3][2], -s * r[1][3] + c * r[3][3],
	}
end

local function add(list: { Part }, pieces: { Piece })
	for _, p in pieces do
		table.insert(list, { p = p.at, r = matrix(p), s = p.size, c = p.color, mat = p.material, shape = p.shape, t = p.alpha or 0 })
	end
end

local function plain(list: { Part }, x: number, y: number, z: number, sx: number, sy: number, sz: number, color: { number }, mat: string, shape: string?)
	table.insert(list, { p = { x, y, z }, r = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, s = { sx, sy, sz }, c = color, mat = mat, shape = shape or "Block", t = 0 })
end

-- A slab over a rect, its top at `top`.
local function slab(list: { Part }, r: Box, top: number, depth: number, color: { number }, mat: string)
	plain(list, (r.x0 + r.x1) / 2, top - depth / 2, (r.z0 + r.z1) / 2, r.x1 - r.x0, depth, r.z1 - r.z0, color, mat)
end

local function road(list: { Part }, r: Box)
	slab(list, r, ROAD_TOP, 1, P.Asphalt, "Asphalt")
end

-- The house of a plan entry, on the map.
local function planHouse(list: { Part }, h: any)
	add(list, V.place(V.house(h.kind, h.box, h.yaw, V.seedOf(h.id), { rich = h.enter }), h.box, h.yaw))
end

local function trees(list: { Part }, spots: { V.Spot })
	for _, s in spots do
		add(list, V.tree(s.kind, s.x, s.z, s.seed))
	end
end

local function mark(id: string): any
	for _, l in Plan.landmarks do
		if l.id == id then
			return l
		end
	end
	error("no landmark " .. id)
end

local function moved(r: Box, dx: number, dz: number): Box
	return { x0 = r.x0 + dx, x1 = r.x1 + dx, z0 = r.z0 + dz, z1 = r.z1 + dz }
end

-- ── The shots ──────────────────────────────────────────────────────────────

type View = { from: { number }?, to: { number }?, dir: { number }?, fov: number?, fit: number?, w: number, h: number, fog: { number }?, sun: { number }? }
local shots = {}
local function shot(name: string, caption: string, parts: { Part }, view: View, subject: number?)
	table.insert(shots, { name = name, caption = caption, parts = parts, view = view, subject = subject or #parts })
end

local TILE = { w = 640, h = 440 }

-- One house alone at the origin, its door to the south (+Z), the street in front of it (plan.py's 12 setback).
local function houseShot(name: string, caption: string, kind: string, w: number, d: number, seed: number, opts: V.Options?)
	local list: { Part } = {}
	local box = { x0 = -w / 2, x1 = w / 2, z0 = -d / 2, z1 = d / 2 }
	local pieces = V.place(V.house(kind, box, 180, seed, opts), box, 180)
	add(list, pieces)
	local subject = #list
	slab(list, { x0 = -90, x1 = 90, z0 = -70, z1 = d / 2 + 70 }, 0, 2, LAWN, "Grass")
	road(list, { x0 = -90, x1 = 90, z0 = d / 2 + 12, z1 = d / 2 + 40 })
	shot(name, `{caption} · {#pieces} dílů`, list, { dir = { 0.62, 0.42, 1 }, fov = 34, fit = 1.15, w = TILE.w, h = TILE.h }, subject)
end

-- the seeds that give each roof (eaves or gable to the street)
local function seedFor(kind: string, w: number, d: number, want: string, skip: number): number
	local found = 0
	for seed = 1, 400 do
		local pieces = V.house(kind, { x0 = 0, x1 = w, z0 = 0, z1 = d }, 180, seed)
		local ridge, wedge = nil :: Piece?, false
		for _, p in pieces do
			if p.name == "Ridge" then
				ridge = p
			elseif p.name == "RoofWedge" then
				wedge = true
			end
		end
		local got = if kind == "modern" then (if wedge then "mono" else "flat") .. (if pieces[1].size[2] > 12 then "2" else "1")
			elseif ridge and ridge.size[1] > ridge.size[3] then "x" else "z"
		if got == want then
			found += 1
			if found > skip then
				return seed
			end
		end
	end
	return 1
end

houseShot("old-eaves", "starý rodinný dům (old), okapem do ulice", "old", 30, 24, seedFor("old", 30, 24, "x", 0))
houseShot("old-eaves-2", "starý rodinný dům (old), jiné kostky", "old", 30, 24, seedFor("old", 30, 24, "x", 3))
houseShot("old-gable", "starý rodinný dům (old), štítem do ulice", "old", 30, 24, seedFor("old", 30, 24, "z", 0))
houseShot("old-gable-2", "starý rodinný dům (old), štítem do ulice", "old", 30, 24, seedFor("old", 30, 24, "z", 4))
-- the houses to empty, rich: Hlavní_n_5 and Školní_e_20 as the map has them (their own seeds)
for _, h in Plan.houses do
	if h.enter and (h.id == "Hlavní_n_5" or h.id == "Školní_e_20") then
		local f = V.frame(h.box, h.yaw)
		houseShot("rich-" .. h.id, `dům ke stěhování (rich), {h.street}`, h.kind, f.w, f.d, V.seedOf(h.id), { rich = true })
	end
end
-- the terraced rows: a group of four as plan.json has it, and the one with the house to empty
do
	local groups = V.rowGroups(Plan.houses)
	local plainGroup, richGroup = nil :: V.Group?, nil :: V.Group?
	for _, g in groups do
		if #g.ids == 4 and g.richUnit == nil and not plainGroup then
			plainGroup = g
		elseif g.richUnit ~= nil then
			richGroup = g
		end
	end
	for _, g in { plainGroup, richGroup } do
		if g then
			local f = V.frame(g.box, g.yaw)
			local caption = if g.richUnit then `řadovky se stěhováním (row, rich {g.richUnit}. dům), {#g.ids} domy` else `řadovky (row), {#g.ids} domy jedním tělem`
			houseShot(if g.richUnit then "row-rich" else "row", caption, "row", f.w, f.d, g.seed, { rich = g.richUnit ~= nil, richUnit = g.richUnit })
		end
	end
end
houseShot("modern-flat", "novostavba (modern), plochá střecha", "modern", 28, 22, seedFor("modern", 28, 22, "flat1", 0))
houseShot("modern-mono", "novostavba (modern), pultová střecha, patro", "modern", 28, 22, seedFor("modern", 28, 22, "mono2", 0))

-- ── The landmarks ──────────────────────────────────────────────────────────

do -- the chapel green with its chapel, Hlavní in front (all from plan.json, at their places)
	local list: { Part } = {}
	local green, chapel = mark("green"), mark("chapel")
	add(list, V.place(V.landmark("chapel", chapel.rect, C.Facing.chapel, V.seedOf("chapel")), chapel.rect, C.Facing.chapel))
	add(list, V.place(V.landmark("green", green.rect, C.Facing.green, V.seedOf("green"), { chapel = chapel.rect }), green.rect, C.Facing.green))
	local subject = #list
	slab(list, { x0 = green.rect.x0 - 80, x1 = green.rect.x1 + 80, z0 = green.rect.z0 - 60, z1 = 40 }, 0, 2, LAWN, "Grass")
	road(list, { x0 = green.rect.x0 - 80, x1 = green.rect.x1 + 80, z0 = -74, z1 = -46 })
	shot("green", `náves s kaplí, křížem, lípami, lavičkami a nástěnkou zakázek · {subject} dílů`, list, { dir = { 0.22, 0.36, 1 }, fov = 34, fit = 0.46, w = TILE.w, h = TILE.h }, subject)
end
do -- the chapel close up
	local list: { Part } = {}
	local chapel = mark("chapel")
	add(list, V.place(V.landmark("chapel", chapel.rect, C.Facing.chapel, V.seedOf("chapel")), chapel.rect, C.Facing.chapel))
	local subject = #list
	slab(list, moved({ x0 = -60, x1 = 60, z0 = -60, z1 = 60 }, -700, -144), 0, 2, LAWN, "Grass")
	shot("chapel", `kaple (chapel) · {subject} dílů`, list, { dir = { 0.75, 0.38, 1 }, fov = 34, fit = 1.1, w = TILE.w, h = TILE.h }, subject)
end
do -- the pond
	local list: { Part } = {}
	local pond = mark("pond")
	add(list, V.place(V.landmark("pond", pond.rect, C.Facing.pond, V.seedOf("pond")), pond.rect, C.Facing.pond))
	local subject = #list
	slab(list, { x0 = pond.rect.x0 - 60, x1 = pond.rect.x1 + 60, z0 = pond.rect.z0 - 60, z1 = pond.rect.z1 + 60 }, 0, 2, LAWN, "Grass")
	shot("pond", `Malý rybník (pond) · {subject} dílů`, list, { dir = { -0.7, 0.75, 0.9 }, fov = 34, fit = 0.95, w = TILE.w, h = TILE.h }, subject)
end
do -- the Corner Drugstore at the crossroads
	local list: { Part } = {}
	local shop = mark("drugstore")
	add(list, V.place(V.landmark("shop", shop.rect, C.Facing.shop, V.seedOf("drugstore")), shop.rect, C.Facing.shop))
	local subject = #list
	slab(list, { x0 = -40, x1 = 200, z0 = -110, z1 = 90 }, 0, 2, LAWN, "Grass")
	road(list, { x0 = -40, x1 = 200, z0 = -74, z1 = -46 })
	road(list, { x0 = -14, x1 = 14, z0 = -46, z1 = 90 })
	shot("shop", `Corner Drugstore (shop, vymyšlená) · {subject} dílů`, list, { dir = { 0.55, 0.5, -1 }, fov = 34, fit = 1.0, w = TILE.w, h = TILE.h }, subject)
end
do -- a stretch of the D5 from the village's side
	local list: { Part } = {}
	local box = { x0 = 330, x1 = 390, z0 = -180, z1 = 180 }
	add(list, V.place(V.landmark("motorway", box, C.Facing.motorway, V.seedOf("d5")), box, C.Facing.motorway))
	local subject = #list
	slab(list, { x0 = 200, x1 = 520, z0 = -200, z1 = 200 }, 0, 2, P.Crops.young, "Grass")
	shot("motorway", `dálnice D5 (motorway): násep, protihluková stěna · {subject} dílů (celá D5 také 16)`, list, { from = { 262, 64, 150 }, to = { 372, 4, -30 }, fov = 46, w = TILE.w, h = TILE.h }, subject)
end
do -- Hornická's barrier at the road's west end
	local list: { Part } = {}
	local hornicka: any = nil
	for _, r in Plan.roads do
		if r.name == "Hornická" then
			hornicka = r
		end
	end
	local box, yaw = V.barrierAt(hornicka.rect)
	add(list, V.place(V.landmark("barrier", box, yaw, 1), box, yaw))
	local subject = #list
	slab(list, { x0 = hornicka.rect.x0, x1 = hornicka.rect.x0 + 120, z0 = -130, z1 = 10 }, 0, 2, P.Crops.rapeseed, "Grass")
	road(list, { x0 = hornicka.rect.x0, x1 = hornicka.rect.x0 + 120, z0 = hornicka.rect.z0, z1 = hornicka.rect.z1 })
	shot("barrier", `Hornická: ROAD CLOSED (barrier) · {subject} dílů`, list, { from = { -1120, 9, -50 }, to = { -1168, 4.5, -60 }, fov = 40, w = TILE.w, h = TILE.h }, subject)
end
do -- Sýkorka (step 2)
	local list: { Part } = {}
	local yard, lot = mark("hardware"), mark("hardware_lot")
	add(list, V.place(V.landmark("hardware", yard.rect, C.Facing.hardware, V.seedOf("hardware")), yard.rect, C.Facing.hardware))
	local subject = #list
	slab(list, { x0 = yard.rect.x0 - 40, x1 = yard.rect.x1 + 40, z0 = yard.rect.z0 - 30, z1 = lot.rect.z1 + 40 }, 0, 2, LAWN, "Grass")
	slab(list, yard.rect, 0.06, 0.06, P.Hardware.Gravel, "Pebble")
	slab(list, lot.rect, 0.1, 0.1, P.Asphalt, "Asphalt")
	shot("hardware", `Stavebniny Sýkorka (hardware, krok 2) · {subject} dílů`, list, { dir = { 0.6, 0.55, 1 }, fov = 34, fit = 0.78, w = TILE.w, h = TILE.h }, subject)
end
do -- the trees: each kind twice
	local list: { Part } = {}
	local x = 0
	for _, kind in V.Trees do
		for n = 1, 2 do
			local _, radius = V.treeSize(kind, n * 11)
			x += radius + 3
			add(list, V.tree(kind, x, if n == 1 then 0 else 14, n * 11))
			x += radius + 3
		end
	end
	local subject = #list
	slab(list, { x0 = -20, x1 = x + 20, z0 = -40, z1 = 50 }, 0, 2, LAWN, "Grass")
	shot("trees", "stromy: lípa, dub, bříza, topol, vrba, ovocný · 2 díly každý", list, { dir = { 0.15, 0.28, 1 }, fov = 34, fit = 0.92, w = TILE.w, h = TILE.h }, subject)
end
do -- the field tiles
	local list: { Part } = {}
	for i, kind in V.Fields do
		local x0 = (i - 1) * 110
		add(list, V.field(kind, { x0 = x0, x1 = x0 + 100, z0 = 0, z1 = 160 }, i))
	end
	local subject = #list
	shot("fields", "pole: řepka, obilí, oranice, mladé osení", list, { dir = { 0.25, 0.75, 1 }, fov = 34, fit = 0.8, w = TILE.w, h = TILE.h }, subject)
end

-- ── The step-1 village (a street of it, all of it) ─────────────────────────

local function village(stepMax: number, far: boolean): ({ Part }, number)
	local list: { Part } = {}
	for _, h in Plan.houses do
		if h.step <= stepMax and h.kind ~= "row" then
			planHouse(list, h)
		end
	end
	for _, g in V.rowGroups(Plan.houses) do
		if g.step <= stepMax then
			add(list, V.place(V.house("row", g.box, g.yaw, g.seed, { rich = g.richUnit ~= nil, richUnit = g.richUnit }), g.box, g.yaw))
		end
	end
	local chapelRect = mark("chapel").rect
	for _, l in Plan.landmarks do
		if l.step <= stepMax and C.Facing[l.kind] then
			add(list, V.place(V.landmark(l.kind, l.rect, C.Facing[l.kind], V.seedOf(l.id), { chapel = chapelRect }), l.rect, C.Facing[l.kind]))
		end
	end
	for _, r in Plan.roads do
		if r.name == "Hornická" then
			local box, yaw = V.barrierAt(r.rect)
			add(list, V.place(V.landmark("barrier", box, yaw, 1), box, yaw))
		end
	end
	for n, line in Plan.lines do
		trees(list, V.lineTrees(line.points, line.kind, n))
	end
	trees(list, V.orchard(mark("orchard").rect, 1))
	for n, field in Plan.fields do
		add(list, V.field(field.kind, field.rect, n))
	end
	local count = #list
	if far then
		add(list, V.horizon(Plan.bounds, 1))
		count = #list
	end
	-- context (not the village's own): the meadow, the village's lawn, the roads, today's warehouses, the farmstead,
	-- the Auction House, as plain shapes
	slab(list, Plan.bounds, -0.6, 2, MEADOW, "Grass")
	slab(list, Plan.village, 0.08, 0.1, LAWN, "Grass")
	for _, r in Plan.roads do
		if r.step <= stepMax then
			road(list, r.rect)
		end
	end
	plain(list, Plan.turnaround.x, ROAD_TOP - 0.5, Plan.turnaround.z, 1, 2 * Plan.turnaround.r, 2 * Plan.turnaround.r, P.Asphalt, "Asphalt", "Cylinder")
	list[#list].r = { 0, -1, 0, 1, 0, 0, 0, 0, 1 }
	for _, plot in Plan.plots do
		slab(list, plot.rect, 0.02, 0.04, { 176, 174, 168 }, "Concrete")
		local w = plot.warehouse
		plain(list, w.x, 12, w.z, w.sx, 24, w.sz, { 196, 198, 200 }, "Metal")
	end
	local big = Plan.bigHouse.house
	plain(list, big.x, 7.25, big.z, big.sx, 14.5, big.sz, P.Render[1], "Plaster")
	plain(list, big.x, 14.5 + 5.5, big.z + big.sz / 4, big.sx, 11, big.sz / 2, P.Tiles[1], "ClayRoofTiles", "Wedge")
	plain(list, big.x, 14.5 + 5.5, big.z - big.sz / 4, big.sx, 11, big.sz / 2, P.Tiles[1], "ClayRoofTiles", "Wedge")
	list[#list - 1].r = { -1, 0, 0, 0, 1, 0, 0, 0, -1 }
	for _, b in Plan.fixed do
		local r = b.rect
		plain(list, (r.x0 + r.x1) / 2, 8, (r.z0 + r.z1) / 2, r.x1 - r.x0, 16, r.z1 - r.z0, { 236, 224, 196 }, "Plaster")
	end
	return list, count
end

do
	local list, count = village(1, true)
	shot("street", `ulice Hlavní a náves, krok 1 (domy, náves, stromořadí, pole; silnice jen pro obrázek)`, list, { from = { -452, 44, -56 }, to = { -700, 0, -108 }, fov = 56, w = 1800, h = 1000, fog = { 400, 1600 } }, count)
	shot("village", `celé Jinočany v kroku 1 (VillageLooks: {count} dílů; šedé krabice: dnešní sklady, statek, aukční dům)`, list, { from = { 380, 1150, 1500 }, to = { -420, 0, 20 }, fov = 42, w = 1800, h = 1100, fog = { 2200, 5200 }, sun = { 0.55, 1, 0.35 } }, count)
end

-- ── The output ─────────────────────────────────────────────────────────────

local function n(v: number): string
	local s = string.format("%.3f", v)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return if s == "-0" then "0" else s
end
local function q(s: string): string
	return '"' .. string.gsub(s, '[\\"]', "\\%0") .. '"'
end
local function encode(v: any): string
	if type(v) == "string" then
		return q(v)
	elseif type(v) == "number" then
		return n(v)
	elseif type(v) == "boolean" then
		return tostring(v)
	elseif type(v) == "table" then
		local out = {}
		if #v > 0 then
			for _, x in v do
				table.insert(out, encode(x))
			end
			return "[" .. table.concat(out, ",") .. "]"
		end
		for k, x in v do
			table.insert(out, q(tostring(k)) .. ":" .. encode(x))
		end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end
for _, s in shots do
	print("SHOT " .. encode(s))
end
