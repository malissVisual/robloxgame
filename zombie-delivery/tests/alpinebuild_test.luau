-- 7.1 review: the real server/Alpine.luau (as AlpineServer.luau on tools/perf/world-mock.luau, WorldMock.luau, with
-- a small stand-in for the rays and the part queries) builds the same forests whatever else is in the workspace: the
-- trees stand on World's own parts and the terrain only (Include filters on World's folder as Alpine.start found it),
-- never on a car, a zombie, a courier or what the server added after World.build (a rental dock), while World's own
-- parts still keep a tree out. Alpine.start puts the far silhouettes and the pass up at once and Alpine.finish the
-- terrain and the forests; Config.Alpine.SkipInStudio leaves the terrain's fills out in a Studio test only.
-- Run with tests/run_tests.py.
local Mock = require("./WorldMock")
local G = Mock.globals
local Instance, Vector3, CFrame, Color3, Enum = G.Instance, G.Vector3, G.CFrame, G.Color3, G.Enum
local workspace, game = Mock.workspace, Mock.game
local Config = require("./Config")
local AlpineLayout = require("./AlpineLayout")
local Alpine = require("./AlpineServer")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local ring = AlpineLayout.ring()
local forest = AlpineLayout.forest()
local trees = forest.trees

-- ── The stand-in for the physics: boxes (unturned parts) and the ring's terrain ──────────────────────────────────
type Solid = { part: any, x: number, y: number, z: number, sx: number, sy: number, sz: number }
local solids: { Solid } = {} -- every part a ray or a query may find (its box kept: the stand-in looks there first)
local function block(parent: any, name: string, x: number, y: number, z: number, sx: number, sy: number, sz: number): any
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(sx, sy, sz)
	p.CFrame = CFrame.new(x, y, z)
	p.Anchored = true
	p.Parent = parent
	table.insert(solids, { part = p, x = x, y = y, z = z, sx = sx, sy = sy, sz = sz })
	return p
end
local function passes(item: any, params: any): boolean
	local listed = false
	for _, entry in params.FilterDescendantsInstances or {} do
		if item == entry or item:IsDescendantOf(entry) then
			listed = true
			break
		end
	end
	if params.FilterType == Enum.RaycastFilterType.Include then
		return listed
	end
	return not listed
end
local function live(p: any): boolean
	return p.Parent ~= nil and p:IsDescendantOf(workspace) and p.CanQuery ~= false
end
local rays, queries = 0, 0
workspace.Raycast = function(_, origin: any, _direction: any, params: any)
	rays += 1
	local best: any = nil
	for _, b in solids do
		if math.abs(origin.X - b.x) <= b.sx / 2 and math.abs(origin.Z - b.z) <= b.sz / 2 and live(b.part) and passes(b.part, params) then
			local top = b.y + b.sy / 2
			if top <= origin.Y and (best == nil or top > best.Position.Y) then
				best = { Instance = b.part, Position = Vector3.new(origin.X, top, origin.Z), Material = Enum.Material.Plastic }
			end
		end
	end
	if passes(workspace.Terrain, params) then
		local h = AlpineLayout.heightAt(ring, origin.X, origin.Z) -- (the terrain the fills leave)
		if h > -math.huge and (best == nil or h > best.Position.Y) then
			best = { Instance = workspace.Terrain, Position = Vector3.new(origin.X, h, origin.Z), Material = Enum.Material.Rock }
		end
	end
	return best
end
workspace.GetPartBoundsInBox = function(_, frame: any, size: any, params: any)
	queries += 1
	local found = {}
	local at = frame.Position
	for _, b in solids do
		local near = math.abs(at.X - b.x) < (size.X + b.sx) / 2 and math.abs(at.Y - b.y) < (size.Y + b.sy) / 2 and math.abs(at.Z - b.z) < (size.Z + b.sz) / 2
		if near and live(b.part) and passes(b.part, params) then
			table.insert(found, b.part)
		end
	end
	return found
end
local fills = 0
for _, method in { "FillCylinder", "FillBlock", "FillBall", "FillWedge" } do
	workspace.Terrain[method] = function()
		fills += 1
	end
end
local RunService = game:GetService("RunService")
local studio = false
RunService.IsStudio = function()
	return studio
end

-- World's helpers (World.luau's part / deco / sign / nightLight, as plain as they come)
local function part(parent: any, name: string, size: any, frame: any, color: any, material: any?): any
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = frame
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.Parent = parent
	return p
end
local tools = {
	part = part,
	deco = function(p: any): any
		p.CanCollide = false
		p.CanQuery = false
		return p
	end,
	sign = function(parent: any, text: string, size: any, frame: any, color: any)
		part(parent, "Sign", size, frame, color)
	end,
	nightLight = function() end,
}

-- World's folder: the valley's ground (its top at 0, out past the box as World's tiles are) and what a test adds.
local world = Instance.new("Folder")
world.Name = "World"
world.Parent = workspace
block(world, "Ground", -125, -2, -725, 7000, 4, 7000)

-- One build: the forests' parts (name and place, to 0.01 studs), the trees, the fills, the silhouettes.
type Built = { key: string, trees: number, fills: number, silhouettes: number, afterStart: { silhouettes: number, forests: boolean } }
local function build(between: (() -> ())?): Built
	local old = world:FindFirstChild("Alps")
	if old then
		old:Destroy()
	end
	fills = 0
	Alpine.start(world, tools)
	local alps = world:FindFirstChild("Alps")
	local early = alps and alps:FindFirstChild("MountainSilhouettes")
	local afterStart = { silhouettes = if early then #early:GetChildren() else 0, forests = alps ~= nil and alps:FindFirstChild("Forests") ~= nil }
	local startFills = fills
	if between then
		between()
	end
	Alpine.finish()
	local list: { string } = {}
	local count = 0
	alps = world:FindFirstChild("Alps")
	local forests = alps and alps:FindFirstChild("Forests")
	if forests then
		for _, item in forests:GetDescendants() do
			if Mock.PARTS[item.ClassName] then
				local p = item.CFrame.Position
				table.insert(list, string.format("%s %.2f %.2f %.2f", item.Name, p.X, p.Y, p.Z))
				if item.Name == "Trunk" then
					count += 1
				end
			end
		end
	end
	table.sort(list)
	local sil = alps and alps:FindFirstChild("MountainSilhouettes")
	return { key = table.concat(list, "\n"), trees = count, fills = fills - startFills, silhouettes = if sil then #sil:GetChildren() else 0, afterStart = afterStart }
end

-- ── A plain server ─────────────────────────────────────────────────────────
local plain = build()
local wantParts = 0
for _, s in ring.silhouettes do
	wantParts += if s.capY < math.huge then 8 else 4
end
check("Alpine.start puts the far silhouettes up at once (before any terrain fill or tree)", plain.afterStart.silhouettes == wantParts and not plain.afterStart.forests, `{plain.afterStart.silhouettes} of {wantParts}`)
check("Alpine.finish fills the terrain (every fill of the layout) and plants the forests", plain.fills == #ring.fills and plain.trees == #trees, `{plain.fills} fills of {#ring.fills}, {plain.trees} trees of {#trees}`)
check("Alpine.finish runs once (a second call builds nothing more)", (function()
	local before = #world:FindFirstChild("Alps"):GetChildren()
	Alpine.finish()
	return #world:FindFirstChild("Alps"):GetChildren() == before
end)())

-- ── The same server with cars, zombies and couriers on the trees' spots, a helicopter over some, a rental dock that
-- came after World.build: the same forests ──────────────────────────────────────────────────────────────────────
local cars = Instance.new("Folder")
cars.Name = "Cars"
cars.Parent = workspace
local zombies = Instance.new("Folder")
zombies.Name = "Zombies"
zombies.Parent = workspace
for n = 1, 120 do
	local t = trees[n * 17 % #trees + 1]
	if n <= 40 then
		block(cars, "Body", t.x, t.y + 3, t.z, 8, 6, 16) -- a parked car
	elseif n <= 80 then
		block(zombies, "Torso", t.x + 1, t.y + 3, t.z, 2, 6, 2) -- a zombie by the trunk
	elseif n <= 100 then
		local courier = Instance.new("Model")
		courier.Name = "Courier"
		courier.Parent = workspace
		block(courier, "HumanoidRootPart", t.x, t.y + 3, t.z + 1, 2, 2, 1)
	else
		block(workspace, "Helicopter", t.x, t.y + 160, t.z, 30, 10, 30) -- (over the tree: the first thing a ray meets)
	end
end
local busy = build(function()
	-- (after Alpine.start: a rental dock where a tree goes, as server/Rental.luau puts its docks in World's folder)
	local docks = Instance.new("Folder")
	docks.Name = "RentalDocks"
	docks.Parent = world
	block(docks, "Dock", trees[5].x, trees[5].y + 1, trees[5].z, 12, 2, 12)
end)
check("cars, zombies, couriers, a helicopter and a dock added later do not move or drop a single tree", busy.key == plain.key and busy.trees == plain.trees, `{busy.trees} trees vs {plain.trees}`)
cars:Destroy()
zombies:Destroy()
for _, item in workspace:GetChildren() do
	if item.Name == "Courier" or item.Name == "Helicopter" then
		item:Destroy()
	end
end
local dock = world:FindFirstChild("RentalDocks")
if dock then
	dock:Destroy()
end

-- ── World's own parts still count: a lamp on a tree's spot keeps it out, World's snow is ground ─────────────────
local props = Instance.new("Folder")
props.Name = "StreetProps"
props.Parent = world
local lampTree, snowTree = trees[3], trees[11]
block(props, "Lamp", lampTree.x, lampTree.y + 6, lampTree.z, 1, 12, 1) -- (on its spot: its neighbours stay clear)
local winter = Instance.new("Folder")
winter.Name = "Winter"
winter.Parent = world
block(winter, "Snow", snowTree.x, snowTree.y + 1, snowTree.z, 4, 2, 4)
local own = build()
local raised = string.format("Trunk %.2f", snowTree.x)
local snowOk = false
for line in string.gmatch(own.key, "[^\n]+") do
	if string.sub(line, 1, #raised) == raised then
		local y = tonumber(string.match(line, "^Trunk %S+ (%S+)")) or 0
		snowOk = math.abs(y - (snowTree.y + 2 + snowTree.height * 0.27 - 1)) < 0.05
	end
end
check("World's own parts count: a lamp keeps its tree out, a tree stands on World's snow", own.trees == plain.trees - 1 and snowOk, `{own.trees} trees, on the snow {snowOk}`)
props:Destroy()
winter:Destroy()

-- ── Config.Alpine.SkipInStudio: the terrain's fills left out in a Studio test, never on a live server ─────────────
Config.Alpine.SkipInStudio = true
studio = false
local live = build()
check("SkipInStudio on a live server: every fill all the same", live.fills == #ring.fills and live.key == plain.key, live.fills)
studio = true
local skipped = build()
check("SkipInStudio in Studio: no terrain fill, the silhouettes and the trees still built", skipped.fills == 0 and skipped.silhouettes == wantParts and skipped.trees == #trees, `{skipped.fills} fills, {skipped.silhouettes} silhouette parts, {skipped.trees} trees`)
Config.Alpine.SkipInStudio = false
studio = false
check("the stand-in was asked (rays and room checks)", rays > 0 and queries > 0, `{rays} rays, {queries} queries`)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
