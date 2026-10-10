-- 6.22: every inventory thing's look (shared/ItemLooks.luau ItemLooks.all) built by the real builders on the recorder
-- (tools/fixtures/item-mock.luau) and written as JSON lines for render.mjs: its parts (class, shape, size, place,
-- turn, colour, material, opacity) and the in-game camera (ItemLooks.frame at Config.ItemModel's angle, a square
-- frame). Run by tools/item-models/render.py.
local M = require("./ItemMock")
local Config = require("./Config")
local ItemLooks = require("./ItemLooks")

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
	for k, x in v do
		table.insert(out, encode(tostring(k)) .. ":" .. encode(x))
	end
	return "{" .. table.concat(out, ",") .. "}"
end

-- A thing's name for the sheet (Config's), else its key.
local function label(key: string): string
	local kind, id = ItemLooks.parse(key)
	if kind == "fists" then
		return "Fists"
	elseif kind == "melee" then
		return "Baseball Bat"
	end
	local lists = { gun = Config.Weapons, item = Config.Items, kit = Config.Kit }
	for _, def in (lists :: any)[kind] or {} do
		if def.id == id then
			return def.name
		end
	end
	if kind == "cargo" then
		for _, k in Config.Cargo.Kinds do
			if k.look == id then
				return k.piece
			end
		end
	end
	return id
end

for index, key in ItemLooks.all() do
	local model = ItemLooks.build(key)
	local parts = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local c = p.Color
			table.insert(parts, {
				class = p.ClassName,
				shape = tostring(p.Shape or "Block"),
				size = { p.Size.X, p.Size.Y, p.Size.Z },
				position = { p.CFrame.Position.X, p.CFrame.Position.Y, p.CFrame.Position.Z },
				rotation = p.CFrame.R,
				color = { c.R, c.G, c.B },
				material = tostring(p.Material),
				opacity = 1 - (p.Transparency or 0),
			})
		end
	end
	local lo, hi = ItemLooks.bounds(model)
	local eye, centre = ItemLooks.frame(lo, hi, 1)
	print(encode({
		name = string.format("%02d-%s", index, (string.gsub(key, ":", "-"))),
		info = { key = key, label = label(key), eye = eye, target = centre, fov = Config.ItemModel.Fov, parts = #parts,
			ambient = Config.ItemModel.Ambient, light = Config.ItemModel.LightColor, direction = Config.ItemModel.LightDirection },
		parts = parts,
	}))
end
local _ = M
