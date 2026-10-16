-- 8.3: the sandbox's map for design/sandbox/map.png (tools/sandbox-map/render.py copies this as main.luau next to the
-- real server modules on tools/perf/world-mock.luau): builds the map, the kiosks, the warehouses (plot n at level n) and
-- the TOP MOVERS board, then prints every BasePart as a "PART" JSON line (where, its turn, size, colour, material, shape,
-- the folders it is in) and the labels' spots as one "FACTS" line (9.4: the countryside's lanes, landmarks, woods and
-- orchard and the six places to empty too).
setfenv(1, require("./mock").env)
local SandboxMap = require("./shared/SandboxMap")
local SandboxLeadersRules = require("./shared/SandboxLeadersRules")
local WarehouseLayout = require("./shared/WarehouseLayout") -- (8.3: each level's stands and building)
local SandboxWorld = require("./server/SandboxWorld")
local MoveSites = require("./server/MoveSites")
local Collection = require("./server/Collection") -- (the stand-in)
local SandboxPlots = require("./server/SandboxPlots") -- (the stand-in)
local Upgrades = require("./server/Upgrades") -- (the stand-in: plot n at warehouse level n)

local world = SandboxWorld.build()

local kiosks = Instance.new("Folder")
kiosks.Name = "MovingBoards"
kiosks.Parent = workspace
for _, plot in SandboxMap.Plots do
	MoveSites.plotBoard(kiosks, plot)
end

for _, plot in SandboxMap.Plots do
	local owner = { UserId = plot.id, DisplayName = `Player{plot.id}`, Name = `Player{plot.id}`, Parent = workspace }
	local entries = {}
	if plot.id == 1 then -- (the close-up's garage: two pieces on its two stands)
		entries = {
			{ uid = "a", item = "jukebox", variant = 1, condition = 1, name = "Jukebox", stand = 1 },
			{ uid = "b", item = "knight_armour", variant = 1, condition = 1, name = "Knight's Armour", stand = 2 },
		}
	end
	Collection.__own(owner, entries, WarehouseLayout.count(plot.id)) -- (level n's big stands)
	SandboxPlots.__own(plot.id, owner)
	Upgrades.__own(owner, plot.id)
end
local Warehouse = require("./server/Warehouse")
Warehouse.start()

local SandboxLeaders = require("./server/SandboxLeaders")
SandboxLeaders.start()

local function n(v: number): string
	return string.format("%.3f", v)
end
local function q(s: string): string
	return (string.format("%q", s):gsub("\\\n", "\\n"))
end

local function groupOf(d: any): string
	local chain = {}
	local at = d.Parent
	while at and at ~= workspace and at.Parent do
		table.insert(chain, 1, at.Name)
		at = at.Parent
	end
	return table.concat(chain, "/")
end

for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") and d.ClassName ~= "Terrain" then
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d.CFrame:GetComponents()
		local c = d.Color
		local mesh = d:FindFirstChildOfClass("SpecialMesh")
		local meshType = if mesh and mesh.MeshType then tostring(mesh.MeshType.Name) else ""
		print(string.format(
			'PART {"name":%s,"group":%s,"class":"%s","shape":"%s","mesh":"%s","p":[%s,%s,%s],"r":[%s,%s,%s,%s,%s,%s,%s,%s,%s],"s":[%s,%s,%s],"c":[%d,%d,%d],"t":%s,"mat":"%s","shadow":%s}',
			q(d.Name), q(groupOf(d)), d.ClassName, tostring(d.Shape and d.Shape.Name or "Block"), meshType,
			n(x), n(y), n(z), n(r00), n(r01), n(r02), n(r10), n(r11), n(r12), n(r20), n(r21), n(r22),
			n(d.Size.X), n(d.Size.Y), n(d.Size.Z),
			math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5),
			n(d.Transparency), tostring(d.Material and d.Material.Name or "Plastic"), tostring(d.CastShadow)
		))
	end
end

-- The facts the labels need (SandboxMap's spots, the board's spot, each plot's level and building)
local facts = { plots = {}, house = SandboxMap.House, roads = SandboxMap.Roads, turnaround = SandboxMap.Turnaround, bounds = SandboxMap.Bounds }
-- 9.4 the countryside: its landmarks, the orchard, the woods and the six places to empty (SandboxMap.Houses)
facts.landmarks = SandboxMap.Landmarks
facts.orchard = SandboxMap.Orchard
facts.woods = SandboxMap.Woods
facts.enter = {}
for _, h in SandboxMap.Houses do
	table.insert(facts.enter, { id = h.id, name = h.name, street = h.street, box = h.box })
end
for _, plot in SandboxMap.Plots do
	local level = Warehouse.level(plot.id)
	local def = WarehouseLayout.level(level) -- (Config.Warehouse.Levels')
	table.insert(facts.plots, {
		id = plot.id,
		rect = plot.rect,
		door = plot.door,
		vanSpot = plot.vanSpot,
		unload = plot.unload,
		spawn = plot.spawn,
		board = plot.board,
		level = level,
		levelName = def.name,
		size = def.size,
		stands = WarehouseLayout.count(level),
	})
end
facts.leaders = SandboxLeadersRules.spot()

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
print("FACTS " .. encode(facts))
