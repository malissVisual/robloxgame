-- 7.0, the moves' world: the real server/MoveSites.luau run on the recorder (tools/fixtures/item-mock.luau over
-- tools/vehicle-preview/roblox-mock.luau) in the Luau CLI, as Moving.start calls it (the kiosk, the checkpoint, each
-- contract's house, the dressing). One JSON line a part (where, its turn, size, colour, material, shape, flags, its
-- lights, its text) and a few for the world round it (the depot's block and hall, Marge's house and street, a tower by
-- each evacuation spot: context, drawn grey-ish, never checked), then a summary. check.py writes MoveSitesServer.luau and
-- the shared modules next to it, checks the lines; render.py draws them.
-- 8.0 SANDBOX: the kiosk on every plot of shared/SandboxMap.luau (MoveSites.plotBoard, as Moving.start builds it in the
-- sandbox) as lines of their own kind "sandbox" (not the city's budget, never drawn), the plots' facts in the summary.
local M = require("./ItemMock")
local MoveSites = require("./MoveSitesServer")
local Looks = require("./MoveSiteLooks")
local Config = require("./Config")
local Map = require("./Map")
local TrafficLanes = require("./TrafficLanes")
local DepotLook = require("./DepotLook")

local function encode(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	elseif type(v) == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null"
		end
		return string.format("%.5f", v)
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
			table.insert(out, encode(tostring(k)) .. ":" .. encode(x))
		end
		return "{" .. table.concat(out, ",") .. "}"
	elseif v == nil then
		return "null"
	end
	error("unsupported " .. type(v))
end

local function rgb(c: any): { number }
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end
local function v3(v: any): { number }
	return { v.X, v.Y, v.Z }
end

local function wordsOf(p: any): { any }
	local list = {}
	for _, gui in p:GetChildren() do
		if gui.ClassName == "SurfaceGui" then
			local entry: any = { face = gui.Face, pps = gui.PixelsPerStud, range = gui.MaxDistance, light = gui.LightInfluence, lines = {} }
			local holder = gui
			local back = gui:FindFirstChild("Back")
			if back then
				entry.back = rgb(back.BackgroundColor3)
				entry.inset = back.Position[1]
				holder = back
			end
			for _, label in holder:GetChildren() do
				if label.ClassName == "TextLabel" then
					table.insert(entry.lines, { text = label.Text, color = rgb(label.TextColor3), size = label.Size[2], font = label.Font, order = label.LayoutOrder, scaled = label.TextScaled })
				end
			end
			table.sort(entry.lines, function(a: any, b: any): boolean
				return a.order < b.order
			end)
			table.insert(list, entry)
		end
	end
	return list
end

local count = 0
local function exportPart(set: string, model: string, p: any, kind: string?)
	local lights = {}
	for _, child in p:GetChildren() do
		if child.ClassName == "PointLight" then
			table.insert(lights, { range = child.Range, color = rgb(child.Color), night = child:GetAttribute("NightLight") == true, shadows = child.Shadows })
		end
	end
	local lit = p:GetAttribute("LitColor")
	print(encode({
		kind = kind or "part",
		set = set,
		model = model,
		name = p.Name,
		class = p.ClassName,
		position = v3(p.Position),
		rotation = p.CFrame.R,
		size = v3(p.Size),
		color = rgb(p.Color),
		material = p.Material,
		shape = if p.ClassName == "WedgePart" then "Wedge" else p.Shape or "Block",
		transparency = p.Transparency,
		anchored = p.Anchored,
		collide = p.CanCollide,
		query = p.CanQuery,
		touch = p.CanTouch,
		shadow = p.CastShadow,
		night = p:GetAttribute("NightLight") == true,
		lit = if lit then rgb(lit) else nil,
		lights = lights,
		words = wordsOf(p),
	}))
	if kind == nil then
		count += 1
	end
end

local function exportModel(set: string, model: any)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			exportPart(set, model.Name, p)
		end
	end
end

-- ── The sets, built as Moving.start builds them ─────────────────────────────

local world = M.Instance.new("Folder")
world.Name = "Moves"
local board, corkboard = MoveSites.board(world)
local drop = MoveSites.dropOff(world)
local houses = {}
for _, contract in Config.Moving.Contracts do
	local home = Map.home(contract.home)
	if home then
		local site = M.Instance.new("Model")
		site.Name = "Move_" .. contract.id
		local sign = MoveSites.house(site, contract.name, home)
		site.PrimaryPart = sign
		site.Parent = world
		table.insert(houses, { id = contract.id, model = site, sign = sign.Name })
	end
end
-- 7.x farm move: each farm contract's site at its place (Walt's farmhouse and the dress)
local farms = {}
for _, contract in Config.Moving.Contracts do
	if contract.kind == "farm" and contract.place then
		local site = M.Instance.new("Model")
		site.Name = "Move_" .. contract.id
		local sign = MoveSites.farm(site, contract.name, contract.place)
		site.PrimaryPart = sign
		site.Parent = world
		table.insert(farms, { id = contract.id, model = site, sign = sign and sign.Name, place = contract.place, kind = contract.kind })
	end
end
local dressing = MoveSites.dressing(world)

exportModel("board", board)
exportModel("checkpoint", drop)
for _, h in houses do
	exportModel("house_" .. h.id, h.model)
end
for _, f in farms do
	exportModel("farm_" .. f.id, f.model)
end
for _, model in dressing:GetChildren() do
	exportModel(if model.Name == "DepotBanner" then "banner" else model.Name, model)
end

-- 8.0 SANDBOX: the plots' kiosks (their own folder: the sandbox's world, not the city's)
local SandboxMap = require("./SandboxMap")
local sandboxWorld = M.Instance.new("Folder")
sandboxWorld.Name = "Moves"
local plotBoards = {}
for _, plot in SandboxMap.Plots do
	local model, corkboard = MoveSites.plotBoard(sandboxWorld, plot)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			exportPart(`plotboard{plot.id}`, model.Name, p, "sandbox")
		end
	end
	table.insert(plotBoards, {
		id = plot.id,
		name = model.Name,
		mode = model.ModelStreamingMode,
		primary = model.PrimaryPart and model.PrimaryPart.Name,
		corkboard = corkboard.Name,
		plot = corkboard:GetAttribute("Plot"),
		spot = { plot.board.x, plot.board.z },
		door = { plot.door.x, plot.door.z },
		unload = { plot.unload.x, plot.unload.z, plot.unload.r },
		vanSpot = { plot.vanSpot.x, plot.vanSpot.z },
	})
end

-- ── The world round them (context) ──────────────────────────────────────────

local function box(set: string, name: string, size: { number }, cf: any, color: { number }, material: string?, shape: string?, words: { any }?)
	print(encode({
		kind = "context", set = set, name = name, position = v3(cf.Position), rotation = cf.R, size = size, color = color,
		material = material or "SmoothPlastic", shape = shape or "Block", transparency = 0, words = words or {},
	}))
end
local CF, ANG = M.CFrame.new, M.CFrame.Angles
local walk, road, block, cell = Map.WalkTop, Map.RoadTop, Map.BlockSize, Map.Cell
local function ground(set: string, cx: number, cz: number, color: { number }?)
	box(set, "Sidewalk", { block, walk, block }, CF(cx, walk / 2, cz), color or { 150, 150, 146 }, "Concrete")
	box(set, "Road", { block + 2 * Map.RoadWidth + 40, 0.4, block + 2 * Map.RoadWidth + 40 }, CF(cx, road - 0.2, cz), { 52, 54, 58 }, "Asphalt")
	for _, k in { -1, 1 } do
		box(set, "LineX", { block + 2 * Map.RoadWidth, 0.05, 0.6 }, CF(cx, road + 0.03, cz + k * cell / 2), { 220, 196, 90 })
		box(set, "LineZ", { 0.6, 0.05, block + 2 * Map.RoadWidth }, CF(cx + k * cell / 2, road + 0.03, cz), { 220, 196, 90 })
	end
end

-- The depot (World.buildDepot's shell and its approved look, the roof's name board, the spawn, the scooter rack, the
-- supply drop's pad), its neighbours across the streets as plain blocks.
local dx, dz = Map.Depot.x, Map.Depot.z
ground("depot", dx, dz, { 120, 120, 116 })
local o = CF(dx, 0, dz)
local backZ = -block / 2 + 6
local wall = { 56, 61, 65 }
box("depot", "Back", { 80, 22, 2 }, o * CF(0, walk + 11, backZ + 1), wall, "Metal")
box("depot", "Left", { 2, 22, 40 }, o * CF(-39, walk + 11, backZ + 20), wall, "Metal")
box("depot", "Right", { 2, 22, 40 }, o * CF(39, walk + 11, backZ + 20), wall, "Metal")
box("depot", "Roof", { 80, 2, 40 }, o * CF(0, walk + 23, backZ + 20), { 34, 38, 42 }, "Metal")
box("depot", "Floor", { 78, 0.1, 38 }, o * CF(0, walk + 0.05, backZ + 20), { 70, 72, 74 }, "Concrete")
local frame = o * CF(0, walk, backZ + 20) * ANG(0, math.pi, 0)
for _, d in DepotLook.details do
	local r = d.rotation or { 0, 0, 0 }
	local words = if d.label then { { face = "Front", lines = { { text = d.label, color = { 216, 219, 205 }, size = 0.6, font = "GothamBold" } } } } else nil
	box("depot", d.name, d.size, frame * CF(d.position[1], d.position[2], d.position[3]) * ANG(math.rad(r[1]), math.rad(r[2]), math.rad(r[3])), d.color, d.material, nil, words)
end
box("depot", "NameBoard", { 60, 8, 1 }, o * CF(0, walk + 28, backZ + 38) * ANG(0, math.pi, 0), { 24, 27, 32 }, "Metal", nil,
	{ { face = "Front", lines = { { text = "DELIVEROS", color = { 255, 190, 60 }, size = 0.6, font = "GothamBlack" } } } })
box("depot", "SpawnPad", { 10, 0.4, 10 }, CF(dx, walk + 0.2, dz + 26), { 255, 190, 60 }, "Neon")
for k = 1, 6 do
	box("depot", "Scooter" .. k, { 0.8, 2.4, 3.6 }, CF(dx + (k - 3.5) * 3.4, walk + 1.2, dz + 44), { 214, 72, 64 }, "Metal")
end
box("depot", "SupplyPad", { 0.12, 24, 24 }, CF(dx + 24, walk + 0.07, dz + 10) * ANG(0, 0, math.rad(90)), { 90, 200, 120 }, "Neon", "Cylinder")
box("depot", "GearStall", { 9, 10, 26 }, CF(dx - 33, walk + 5, dz + 8), { 35, 40, 43 }, "Metal")
box("depot", "JobsBooth", { 16, 9, 8 }, CF(dx - 18, walk + 4.5, dz - 21), { 60, 66, 72 }, "Metal")
for _, n in { { 1, 0 }, { 2, -1 }, { 1, -2 } } do
	local nx, nz = dx + n[1] * cell - cell, dz + (n[2] + 1) * cell
	box("depot", `Neighbour{n[1]}{n[2]}`, { block, walk, block }, CF(nx, walk / 2, nz), { 140, 140, 136 }, "Concrete")
end
box("depot", "TowerEast", { 40, 46, 40 }, CF(dx + cell - 20, walk + 23, dz - 10), { 92, 96, 104 }, "Concrete")
box("depot", "Motors", { 70, 16, 46 }, CF(dx, walk + 8, dz + cell - 6), { 40, 44, 52 }, "Metal")

-- Marge's house (World.buildHouse from its lot), its lawn, path, mailbox, the street.
for _, contract in Config.Moving.Contracts do
	local home = Map.home(contract.home)
	if not home then
		continue
	end
	local district, i, j = Map.blockAt(home.door.x, home.door.z)
	local lot: any = nil
	if district then
		for _, l in Map.lotsAt(district.id, i, j) do
			if l.home and l.home.id == home.id then
				lot = l
			end
		end
		ground("house_" .. contract.id, district.ox + i * cell, district.oz + j * cell)
	end
	if lot then
		local set = "house_" .. contract.id
		local door = M.Vector3.new(home.door.x, walk, home.door.z)
		local f = M.CFrame.lookAt(door, door + M.Vector3.new(home.facing.x, 0, home.facing.z))
		local body = f * CF(0, 0, lot.d / 2)
		box(set, "Lawn", { lot.size - 2, 0.1, lot.size - 2 }, CF(lot.x, walk + 0.05, lot.z), { 86, 120, 64 }, "Grass")
		box(set, "House", { lot.w, lot.h, lot.d }, body * CF(0, lot.h / 2, 0), { 200, 190, 170 }, "WoodPlanks")
		local half = (lot.d + 2) / 2
		box(set, "RoofF", { lot.w + 2, 6, half }, body * CF(0, lot.h + 3, -half / 2), { 110, 64, 52 }, "Slate", "Wedge")
		box(set, "RoofB", { lot.w + 2, 6, half }, body * CF(0, lot.h + 3, half / 2) * ANG(0, math.pi, 0), { 110, 64, 52 }, "Slate", "Wedge")
		box(set, "Door", { 4, 7, 0.4 }, f * CF(0, 3.5, -0.2), { 90, 60, 40 }, "Wood")
		for _, x in { -lot.w / 3, lot.w / 3 } do
			box(set, "Window", { 4, 3.5, 0.3 }, f * CF(x, lot.h * 0.55, -0.15), { 40, 50, 60 }, "Glass")
		end
		local yard = lot.size / 2 - Map.HouseFront
		box(set, "Path", { 3, 0.1, yard }, f * CF(0, 0.12, -yard / 2), { 176, 172, 164 }, "Concrete")
		box(set, "MailboxPost", { 0.3, 3.2, 0.3 }, f * CF(3, 1.6, -(yard - 2.5)), { 90, 70, 50 }, "Wood")
		box(set, "Mailbox", { 1.4, 1, 1.6 }, f * CF(3, 3.6, -(yard - 2.5)), { 46, 58, 70 }, "Metal")
	end
	for _, other in Map.Homes do
		if other.id ~= home.id and math.abs(other.door.x - home.door.x) < 60 and math.abs(other.door.z - home.door.z) < 30 then
			local door = M.Vector3.new(other.door.x, walk, other.door.z)
			local f = M.CFrame.lookAt(door, door + M.Vector3.new(other.facing.x, 0, other.facing.z))
			box("house_" .. contract.id, "Neighbour", { 22, 12.5, 18 }, f * CF(0, 6.25, 9), { 170, 190, 200 }, "WoodPlanks")
		end
	end
end

-- 7.x farm move: the Old Farm round each farm site (World.buildFarm's yard, barn and silo in the place's frame)
for _, f in farms do
	local place = Looks.sitePlace(f.place)
	if place then
		local set = "farm_" .. f.id
		local frame = CF(place.x, place.y, place.z) * ANG(0, math.rad(place.yaw), 0)
		box(set, "Yard", { 300, 0.2, 300 }, frame * CF(0, -0.1, 0), { 110, 96, 70 }, "Ground")
		box(set, "Barn", { 40, 18, 30 }, frame * CF(-60, 9, -80), { 150, 40, 36 }, "WoodPlanks")
		box(set, "BarnDoors", { 14, 12, 0.3 }, frame * CF(-60, 6, -64.85), { 118, 34, 30 }, "WoodPlanks")
		box(set, "Silo", { 36, 14, 14 }, frame * CF(-20, 18, -90) * ANG(0, 0, math.rad(90)), { 170, 170, 170 }, "Metal", "Cylinder")
	end
end

-- A tower behind each evacuation spot on a Downtown block (the street's look), the ground under it.
for _, place in Looks.spotPlaces() do
	local district, i, j = Map.blockAt(place.x, place.z)
	if district then
		local set = `EvacuationSpot{place.seed}`
		ground(set, district.ox + i * cell, district.oz + j * cell, if district.style == "suburbs" then nil else { 130, 130, 126 })
		if district.style ~= "suburbs" then
			local f = CF(place.x, walk, place.z) * ANG(0, math.rad(place.yaw), 0)
			box(set, "Tower", { 40, 40, 30 }, f * CF(0, 20, 26), { 96, 92, 88 }, "Concrete")
		end
	end
end

print(encode({ kind = "summary", parts = count, budget = Config.MoveSites.Budget, lights = Config.MoveSites.Lights, textRange = Config.MoveSites.TextRange,
	clear = Config.MoveSites.Clear, bay = Config.MoveSites.Bay, dropOff = { dx + Config.Moving.DropOff[1], dz + Config.Moving.DropOff[2] },
	board = { dx + Config.Moving.Board[1], dz + Config.Moving.Board[2] }, reach = Config.Moving.Reach.Board, depot = { dx, dz }, block = block,
	walk = walk, road = road, curbRun = Map.CurbRun, inset = TrafficLanes.SidewalkInset, body = TrafficLanes.Body,
	modes = { board = board.ModelStreamingMode, checkpoint = drop.ModelStreamingMode, banner = dressing:FindFirstChild("DepotBanner").ModelStreamingMode,
		spot = dressing:FindFirstChild("EvacuationSpot1").ModelStreamingMode },
	primary = { board = board.PrimaryPart and board.PrimaryPart.Name, corkboard = corkboard.Name, checkpoint = drop.PrimaryPart and drop.PrimaryPart.Name,
		house = houses[1] and houses[1].sign, farm = farms[1] and farms[1].sign },
	homes = (function()
		local list = {}
		for _, contract in Config.Moving.Contracts do
			local home = Map.home(contract.home)
			if home then
				table.insert(list, { id = contract.id, door = { home.door.x, home.door.z }, facing = { home.facing.x, home.facing.z }, park = { home.park.x, home.park.z } })
			end
		end
		return list
	end)(),
	farms = (function() -- 7.x farm move: each farm's doors (foot, facing, width, the van's spot) and Walt's spot
		local list = {}
		for _, f in farms do
			local doors = {}
			for _, d in Looks.siteDoors(f.kind, f.place) or {} do
				table.insert(doors, { door = { d.x, d.z }, facing = { d.fx, d.fz }, width = d.width, park = { d.park.x, d.park.z } })
			end
			table.insert(list, { id = f.id, doors = doors, curb = Config.Moving.Sites[f.kind].Curb, porch = Config.MoveGreeters.Porch, ground = Map.RoadTop })
		end
		return list
	end)(),
	pieces = (function()
		local n = 0
		for _, set in Looks.all() do
			n += #set.pieces
		end
		return n
	end)(),
	plotBoards = plotBoards, -- 8.0 SANDBOX
	plots = #SandboxMap.Plots,
	boardPieces = #Looks.board(),
	plotBoardPieces = #Looks.board(true), -- 8.0 SANDBOX: the plots' corkboard (the chalet, no Wall)
	doorWidth = SandboxMap.DoorWidth,
	groundTop = SandboxMap.GroundTop,
}))
