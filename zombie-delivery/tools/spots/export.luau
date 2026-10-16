-- 9.5: the countryside's spots for the owner (design/countryside/spots/; tools/spots/preview.py copies this as main.luau
-- next to the shared modules and server/HouseInterior.luau on the recorder, tools/fixtures/item-mock.luau). Prints one
-- "SHOT" JSON line a picture (tools/village/render.html's format: its name, caption, camera and parts, p the middle, r
-- the rotation's rows, s the size, c the colour, mat, shape, t the transparency) and one "LABELS" line a plan (where its
-- rooms and pieces are, for preview.py to write their names on the top-down picture):
--   look-<kind>-<n>     each spot's house (shared/VillageLooks.luau), on its lawn, from its front right and front left
--   plan-<kind>         each spot's inside (shared/Layouts/Countryside.luau through HouseLayout, built by the real
--                       server/HouseInterior.luau) from straight above, its ceiling and what hangs from it left out
--   piece-<id>          each of the countryside's own pieces (shared/FurnitureLooks.luau, Config.Furniture.Pieces)
local M = require("./ItemMock")
local V = require("./VillageLooks")
local Config = require("./Config")
local FurnitureLooks = require("./FurnitureLooks")
local HouseLayout = require("./HouseLayout")
local HouseInterior = require("./HouseInterior")
local Countryside = require("./Countryside")

local C = Config.Village
type Piece = V.Piece
type Part = { p: { number }, r: { number }, s: { number }, c: { number }, mat: string, shape: string, t: number }

local SEEDS: { [string]: number } = { cabin = 2, lodge = 3, mill = 5, cottage = 4 } -- (the plans shown: a mirrored cabin, the lodge's four rooms ...)
local BOXES: { [string]: { number } } = { cabin = { 24, 18 }, lodge = { 28, 22 }, mill = { 24, 26 }, cottage = { 26, 20 } }
local NAMES: { [string]: string } = { cabin = "The Pond Cabin", lodge = "The Forest Lodge", mill = "The Old Mill", cottage = "The Orchard Cottage" }
local LAWN = { 108, 150, 64 }
local WATER = { 70, 112, 120 }

-- A piece's rotation (its yaw about Y, then CFrame.Angles(turn)), row-major (as tools/village/export.luau's).
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

local function plain(list: { Part }, x: number, y: number, z: number, sx: number, sy: number, sz: number, color: { number }, mat: string)
	table.insert(list, { p = { x, y, z }, r = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, s = { sx, sy, sz }, c = color, mat = mat, shape = "Block", t = 0 })
end

-- Every part of a built model (the recorder's), but `skip`'s names and the hidden ones.
local function partsOf(model: any, skip: { [string]: boolean }, list: { Part })
	for _, obj in model:GetDescendants() do
		if not obj:IsA("BasePart") or skip[obj.Name] or obj.Transparency >= 0.95 then
			continue
		end
		local cf = obj.CFrame
		local pos = cf.Position
		local shape = if obj.ClassName == "WedgePart" then "Wedge" elseif obj.Shape == "Cylinder" then "Cylinder" elseif obj.Shape == "Ball" then "Ball" else "Block"
		local col = obj.Color
		table.insert(list, {
			p = { pos.X, pos.Y, pos.Z },
			r = table.clone(cf.R),
			s = { obj.Size.X, obj.Size.Y, obj.Size.Z },
			c = { math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5) },
			mat = tostring(obj.Material),
			shape = shape,
			t = obj.Transparency or 0,
		})
	end
end

local shots = {}
local labels = {}
local TILE = { w = 640, h = 440 }

-- ── The looks ──────────────────────────────────────────────────────────────
for _, kind in V.Countryside do
	local w, d = BOXES[kind][1], BOXES[kind][2]
	local box = { x0 = -w / 2, x1 = w / 2, z0 = -d / 2, z1 = d / 2 }
	for n, dir in { { 0.7, 0.42, 1 }, { -0.75, 0.45, 0.9 } } do
		-- (the cottage's second picture: its other roof)
		local seed = V.seedOf(kind)
		if kind == "cottage" and n == 2 then
			local first = V.house(kind, box, 180, seed)
			for s = 1, 50 do
				local other = V.house(kind, box, 180, s)
				local a, b = nil :: string?, nil :: string?
				for _, p in first do
					a = if p.name == "Roof" then p.material else a
				end
				for _, p in other do
					b = if p.name == "Roof" then p.material else b
				end
				if a ~= b then
					seed = s
					break
				end
			end
		end
		local pieces = V.place(V.house(kind, box, 180, seed, { rich = true }), box, 180)
		local list: { Part } = {}
		for _, p in pieces do
			table.insert(list, { p = p.at, r = matrix(p), s = p.size, c = p.color, mat = p.material, shape = p.shape, t = p.alpha or 0 })
		end
		local subject = #list
		plain(list, 0, -1, 0, 160, 2, 160, LAWN, "Grass")
		if kind == "cabin" then
			plain(list, 0, -0.25, -d / 2 - 22, 120, 0.6, 40, WATER, "Glass") -- (the pond behind it: the map's)
		end
		local side = if n == 1 then "from the front right" else "from the front left"
		table.insert(shots, { name = `look-{kind}-{n}`, caption = `{NAMES[kind]} ({kind}), {side} · {#pieces} parts`, parts = list, view = { dir = dir, fov = 34, fit = 1.12, w = TILE.w, h = TILE.h }, subject = subject })
	end
end

-- ── The plans, from above ──────────────────────────────────────────────────
local SKIP = {
	Ceiling = true, Beam = true, Lamp = true, Header = true, PorchRoof = true, BackPorchRoof = true, Trap = true, Chain = true, Hook = true,
	Sack = true, Lantern = true, LanternCap = true, ExitSign = true, Daylight = true, BackDaylight = true, Pipe = true, Lintel = true,
}
for _, kind in Countryside.Kinds do
	local plan: any = HouseLayout.plan(SEEDS[kind], kind)
	local model = HouseInterior.build(plan, M.CFrame.new(0, 0, 0))
	local list: { Part } = {}
	partsOf(model, SKIP, list)
	local mx, mz = (plan.min.X + plan.max.X) / 2, (plan.min.Z + plan.max.Z) / 2
	local span = math.max(plan.size.X, plan.size.Z * 1.5) + 14 -- (the picture 3 : 2, the house and its porch in it with a margin)
	local height = 900
	local fov = 2 * math.deg(math.atan(span / 3 / height)) -- (the picture's height: span / 1.5 of it)
	local view = { from = { mx, height, mz - height * 0.0005 }, to = { mx, 0, mz }, fov = fov, w = 1500, h = 1000, sun = { 0.04, 1, 0.08 } }
	local stars, coll = 0, 0
	local spots = {}
	for _, s in plan.spots do
		local def = FurnitureLooks.Items[s.item]
		local p = s.at.Position
		stars += if s.star then 1 else 0
		coll += if def.rarity then 1 else 0
		table.insert(spots, { x = p.X, z = p.Z, text = def.name, star = s.star, rarity = def.rarity or "" })
	end
	local rooms = {}
	for _, room in plan.rooms do
		table.insert(rooms, { x = (room.min.X + room.max.X) / 2, z = room.min.Z + 1.6, text = string.upper(room.id) })
	end
	local caption = `{NAMES[kind]} ({kind}, seed {SEEDS[kind]}): {plan.size.X} × {plan.size.Z} studs, {#plan.rooms} rooms, {#plan.spots} pieces ({coll} collectibles, {stars} ★)`
	local title = `{NAMES[kind]}: the inside ({kind}, seed {SEEDS[kind]})`
	table.insert(shots, { name = `plan-{kind}`, caption = caption, parts = list, view = view, subject = #list })
	table.insert(labels, { name = `plan-{kind}`, mid = { mx, mz }, height = height, fov = fov, w = view.w, h = view.h, spots = spots, rooms = rooms, caption = caption, title = title })
end

-- ── The pieces ─────────────────────────────────────────────────────────────
local P = Config.Furniture.Pieces
local ids = {}
for _, id in FurnitureLooks.Order do
	if P[id] then
		table.insert(ids, id)
	end
end
for _, id in ids do
	local def = FurnitureLooks.Items[id]
	local model = FurnitureLooks.build(id, 1)
	local list: { Part } = {}
	partsOf(model, {}, list)
	local subject = #list
	plain(list, 0, -def.size.Y / 2 - 0.1, 0, 40, 0.2, 40, { 200, 196, 186 }, "SmoothPlastic")
	local what = if def.class == "pair" then "2 people" elseif def.class == "both" then "both hands" else "one hand"
	local caption = `{def.name} · {what}, {def.weight}/10, ${def.value}{if def.fragile then ", fragile" else ""}{if def.sentimental then " ★" else ""}`
	table.insert(shots, { name = `piece-{id}`, caption = caption, parts = list, view = { dir = { 0.75, 0.55, -1 }, fov = 30, fit = 1.15, w = 360, h = 300 }, subject = subject })
end

-- ── Out ────────────────────────────────────────────────────────────────────
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
for _, l in labels do
	print("LABELS " .. encode(l))
end
