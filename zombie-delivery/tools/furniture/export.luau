-- 7.0, the moving prototype's previews: every piece of furniture (shared/FurnitureLooks.luau) and one house's inside
-- (shared/HouseLayout.luau + server/HouseInterior.luau) built by the real builders on the recorder
-- (tools/fixtures/item-mock.luau), written as JSON lines for render.mjs: each part's class, shape, size, place, turn,
-- colour, material and opacity, the pieces' catalogue entries, the house's rooms, spots, entry and lights.
-- 7.x the farm: with a second seed also Walt's farm (HouseLayout.plan(seed, "farm"), layout "farm"); a piece of the
-- farm's block (FurnitureLooks.FarmPieces) is marked farm.
-- Run by tools/furniture/render.py:  luau export.luau -a <seed> [<farm seed>]
local M = require("./ItemMock")
local FurnitureLooks = require("./FurnitureLooks")
local HouseLayout = require("./HouseLayout")
local HouseInterior = require("./HouseInterior")

local args = { ... }
local seed = tonumber(args[1]) or 1
local farmSeed = tonumber(args[2])
local farmPieces: { [string]: boolean } = {}
for _, id in FurnitureLooks.FarmPieces do
	farmPieces[id] = true
end

local function encode(v: any): string
	local kind = type(v)
	if kind == "string" then
		return string.format("%q", v)
	elseif kind == "number" then
		return if v ~= v then "0" else string.format("%.4f", v)
	elseif kind == "boolean" then
		return tostring(v)
	elseif kind == "nil" then
		return "null"
	end
	local out = {}
	if #v > 0 then
		for _, x in v do
			table.insert(out, encode(x))
		end
		return "[" .. table.concat(out, ",") .. "]"
	end
	if next(v) == nil then
		return "[]"
	end
	for k, x in v do
		table.insert(out, encode(tostring(k)) .. ":" .. encode(x))
	end
	return "{" .. table.concat(out, ",") .. "}"
end

local function vec(v: any): { number }
	return { v.X, v.Y, v.Z }
end

-- A part as render.html draws it; `extra` adds the house's flags.
local function record(p: any, extra: { [string]: any }?): { [string]: any }
	local c = p.Color
	local out: { [string]: any } = {
		name = p.Name,
		class = p.ClassName,
		shape = tostring(p.Shape or "Block"),
		size = vec(p.Size),
		position = vec(p.CFrame.Position),
		rotation = p.CFrame.R,
		color = { c.R, c.G, c.B },
		material = tostring(p.Material),
		opacity = 1 - (p.Transparency or 0),
	}
	for k, x in extra or {} do
		out[k] = x
	end
	return out
end

-- Every piece, its own scene at the origin.
for index, id in FurnitureLooks.Order do
	local def = FurnitureLooks.Items[id]
	local model = FurnitureLooks.build(id, 1)
	local parts = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			table.insert(parts, record(p))
		end
	end
	print(encode({
		kind = "item",
		name = string.format("%02d-%s", index, id),
		info = {
			id = id,
			label = def.name,
			class = def.class,
			weight = def.weight,
			value = def.value,
			fragile = def.fragile,
			sentimental = def.sentimental,
			room = def.room,
			size = vec(def.size),
			parts = #parts + 1,
			farm = farmPieces[id] == true,
			bigDoor = def.bigDoor == true,
		},
		parts = parts,
	}))
	model:Destroy()
end

-- One house (or the farm), built at the origin.
local function scene(kind: string, at: number)
	local plan = HouseLayout.plan(at, kind)
	local origin = M.CFrame.new(0, 0, 0)
	local model, pieces = HouseInterior.build(plan, origin)
	local spotOf: { [any]: any } = {}
	for id, piece in pieces do
		for _, p in piece:GetDescendants() do
			spotOf[p] = plan.spots[id]
		end
	end
	local parts, lights = {}, {}
	local count = 0
	for _, p in model:GetDescendants() do
		if p.ClassName == "PointLight" or p.ClassName == "SurfaceLight" then
			local c = p.Color
			table.insert(lights, { position = vec(p.Parent.CFrame.Position), color = { c.R, c.G, c.B }, range = p.Range, brightness = p.Brightness, kind = p.ClassName })
		end
		if p:IsA("BasePart") then
			count += 1
			if p.Transparency < 1 then
				local spot = spotOf[p]
				table.insert(parts, record(p, { group = if spot then "item" else p.Parent.Name, star = spot ~= nil and spot.star }))
			end
		end
	end
	local rooms, spots = {}, {}
	for _, r in plan.rooms do
		table.insert(rooms, { id = r.id, kind = r.kind, min = vec(r.min), max = vec(r.max) })
	end
	for _, s in plan.spots do
		local def = FurnitureLooks.Items[s.item]
		table.insert(spots, { id = s.id, item = s.item, room = s.room, star = s.star, position = vec(s.at.Position), label = def.name, bigDoor = def.bigDoor == true })
	end
	local exits = {}
	for _, e in (plan :: any).exits or { plan.exit } do
		table.insert(exits, vec(e))
	end
	print(encode({
		kind = "house",
		layout = kind,
		name = string.format("%s-%d", kind, at),
		info = {
			seed = at,
			mirrored = plan.mirrored,
			min = vec(plan.min),
			max = vec(plan.max),
			rooms = rooms,
			spots = spots,
			entry = vec(plan.entry.Position),
			exits = exits,
			parts = count,
			lights = lights,
			ceiling = plan.ceiling,
		},
		parts = parts,
	}))
end
scene("house", seed)
if farmSeed then
	scene("farm", farmSeed)
end
