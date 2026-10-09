--!strict
-- 6.11, the Central Park (Map.Park): Downtown's middle block (0, 0), where the depot stood (the owner: "make the middle
-- of the map, where the safe zone is, nice: nature, some water in the middle, a park ... so people remember where the
-- safe zone is and where all the shops are"). The shops stand all round it, the depot across the junction to the
-- north-east (Map.Depot). server/World.luau builds it as a piece of the world (CentralPark.build, with World's helpers
-- handed over: no new top-level locals there, the -O0 register limit).
--
--   the ground  the block's slab at the walk's height (Map.WalkTop) with a square hole for the pond, its kerb all round
--               (server/Curbs.luau: the eight pieces, not the union, whose hull would close the hole), the lawn inside
--               the sidewalk band (Map.Park.walk wide: the people's walk line stays on it, nothing solid there, no fence)
--   the pond    a regular octagon in the very middle, its flat sides to the four streets: real water (Terrain) from the
--               ground's 0 down to its floor, deep enough to swim (the hole in the ground under it is World's
--               buildGround); a stone coping round it, a step over the walk (no car rolls in), a post at every corner,
--               lily pads and three ducks
--   the island  in the pond's middle: the fountain (a basin, a bowl and a jet of water that reads from afar, its spray;
--               it glows at night), a wooden footbridge to it from the south
--   the paths   a ring round the pond, a path from it to the middle of each side and one to each corner (the one to the
--               north-east corner looks across the junction at the depot)
--   the rest    trees (round, blossom, columns: the park's own dice, Map.Park.seed, never the world's random numbers),
--               flowerbeds, benches facing the pond, lamps (they glow at night, every other one lights the path), a
--               gazebo on the west lawn and a CENTRAL PARK · SAFE ZONE sign facing each street
-- About 300 parts. The ground, the coping and its posts, the island, the fountain's basin, the bridge, the trunks, the
-- benches, the lamp posts, the gazebo and the signs' posts are solid; everything else is decoration (no collision, no
-- ray hits).
-- 6.12.15: the footbridge over Bone St to the Lantern Garden lands on the north lawn (server/Footbridge.luau,
-- Map.Footbridge): its ramp runs east along the lawn's north edge and down its east side onto the east path. Next to
-- it the trees are narrow columns (or left out), the north path's lamp stands further in and the east sign stands on
-- the other side of its path. 6.12.16: the ramp is wider and curved (round the north-east corner, out over the
-- sidewalk in a soft S): the north path has no lamp of its own (the bridge runs over it), the north sign stands
-- further west along the edge; the path to the north-east corner ends before the ramp's turn round that corner (where
-- the ramp is low a planted bed fills the ground under it: shared/FootbridgeShape.luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Map)

local CentralPark = {}

export type Tools = {
	part: (parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?) -> Part,
	deco: (p: Part) -> Part,
	sign: (parent: Instance, text: string, size: Vector3, cframe: CFrame, color: Color3, background: Color3?, art: string?, artHeight: number?) -> (),
	nightLight: (item: Instance, lit: Color3?, dim: Color3?, dimMaterial: string?) -> (),
}

local WALK = Map.WalkTop
local HALF = Map.BlockSize / 2
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder standing up

-- The shades (the sidewalk's grey is every block's).
local WALK_GREY = Color3.fromRGB(150, 150, 146)
local LAWN = Color3.fromRGB(76, 104, 56)
local GRAVEL = Color3.fromRGB(196, 184, 160)
local STONE = Color3.fromRGB(176, 172, 162)
local STONE_DARK = Color3.fromRGB(112, 110, 104)
local WOOD = Color3.fromRGB(124, 88, 58)
local IRON = Color3.fromRGB(44, 46, 50)
local WATER = Color3.fromRGB(150, 205, 235)
local LAMP_LIT = Color3.fromRGB(255, 214, 150)
local LAMP_DIM = Color3.fromRGB(176, 172, 160)

-- A right isosceles triangle lying flat (a WedgePart turned onto its side), `height` thick from `y0` up: its right
-- angle at (x, z), its legs `leg` long along the flat directions a and b. (A wedge's triangle: its right angle at its
-- local (-Y/2, +Z/2), legs along +Y and -Z; turned so that its X is up.)
local function flatTriangle(tools: Tools, parent: Instance, name: string, x: number, z: number, a: Vector3, b: Vector3, leg: number, y0: number, height: number, color: Color3, material: Enum.Material): Part
	local up = Vector3.yAxis
	local ay, az = a, up:Cross(a)
	if az:Dot(b) > 0 then -- (the other leg must run along -Z)
		ay, az = b, up:Cross(b)
	end
	local centre = Vector3.new(x, y0 + height / 2, z) + ay * (leg / 2) - az * (leg / 2)
	local wedge = tools.part(parent, name, Vector3.new(height, leg, leg), CFrame.fromMatrix(centre, up, ay, az), color, material)
	wedge.Shape = Enum.PartType.Wedge
	return wedge
end

local function cylinder(tools: Tools, parent: Instance, name: string, length: number, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = tools.part(parent, name, Vector3.new(length, diameter, diameter), cframe, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(tools: Tools, parent: Instance, name: string, diameter: number, at: Vector3, color: Color3, material: Enum.Material?): Part
	local p = tools.deco(tools.part(parent, name, Vector3.new(diameter, diameter, diameter), CFrame.new(at), color, material))
	p.Shape = Enum.PartType.Ball
	return p
end

local function pointLight(parent: Instance, range: number, brightness: number, color: Color3)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = color
	l.Shadows = false
	l.Parent = parent
end

-- A park lamp: a post with a lantern on top (it glows at night; `beam`: a real light over the path too).
local function lamp(tools: Tools, parent: Instance, at: Vector3, beam: boolean)
	cylinder(tools, parent, "LampPost", 8, 0.45, CFrame.new(at + Vector3.new(0, 4, 0)) * UPRIGHT, IRON, Enum.Material.Metal)
	local head = tools.deco(tools.part(parent, "Lantern", Vector3.new(1.1, 1.5, 1.1), CFrame.new(at + Vector3.new(0, 8.75, 0)), LAMP_DIM, Enum.Material.Glass))
	tools.deco(tools.part(parent, "LanternCap", Vector3.new(1.6, 0.3, 1.6), CFrame.new(at + Vector3.new(0, 9.65, 0)), IRON, Enum.Material.Metal))
	if beam then
		pointLight(head, 26, 1.3, Color3.fromRGB(255, 208, 150))
	end
	tools.nightLight(head, LAMP_LIT, LAMP_DIM, "Glass")
end

-- A bench at `at` (the middle of its seat's front edge on the ground), facing `look` (flat): a wooden seat and back on
-- two iron legs.
local function bench(tools: Tools, parent: Instance, at: Vector3, look: Vector3)
	local frame = CFrame.lookAt(at, at + look)
	tools.part(parent, "Bench", Vector3.new(5.6, 0.35, 1.7), frame * CFrame.new(0, 1.75, 0.6), WOOD, Enum.Material.WoodPlanks)
	tools.part(parent, "BenchBack", Vector3.new(5.6, 1.5, 0.25), frame * CFrame.new(0, 2.85, 1.45) * CFrame.Angles(math.rad(10), 0, 0), WOOD, Enum.Material.WoodPlanks)
	for _, x in { -2.3, 2.3 } do
		tools.deco(tools.part(parent, "BenchLeg", Vector3.new(0.3, 1.6, 1.6), frame * CFrame.new(x, 0.8, 0.7), IRON, Enum.Material.Metal))
	end
end

-- A tree on the lawn at (x, z) (its foot at the walk's top): "round", "blossom" or "column". The trunk is solid, the
-- crown decoration; a round crown's second ball leans about `away` (radians round the vertical: out of the park).
local function tree(tools: Tools, parent: Instance, x: number, z: number, style: string, rng: Random, away: number)
	local foot = Vector3.new(x, WALK, z)
	if style == "column" then
		local height = rng:NextNumber(10, 13)
		cylinder(tools, parent, "Trunk", 3, 1, CFrame.new(foot + Vector3.new(0, 1.5, 0)) * UPRIGHT, Color3.fromRGB(86, 64, 46), Enum.Material.Wood)
		local green = Color3.fromRGB(48 + rng:NextInteger(0, 14), 84 + rng:NextInteger(0, 16), 46)
		tools.deco(cylinder(tools, parent, "Leaves", height, 4.2, CFrame.new(foot + Vector3.new(0, 2 + height / 2, 0)) * UPRIGHT, green, Enum.Material.Grass))
		ball(tools, parent, "Leaves", 4.2, foot + Vector3.new(0, 2 + height, 0), green, Enum.Material.Grass)
		return
	end
	local blossom = style == "blossom"
	local height = if blossom then rng:NextNumber(5.5, 7) else rng:NextNumber(7, 9.5)
	local size = if blossom then rng:NextNumber(7, 8.5) else rng:NextNumber(9, 11.5)
	cylinder(tools, parent, "Trunk", height, if blossom then 1 else 1.3, CFrame.new(foot + Vector3.new(0, height / 2, 0)) * UPRIGHT, Color3.fromRGB(84, 62, 44), Enum.Material.Wood)
	local color = if blossom
		then Color3.fromRGB(236, 168 + rng:NextInteger(0, 24), 196 + rng:NextInteger(0, 20))
		else Color3.fromRGB(62 + rng:NextInteger(0, 18), 96 + rng:NextInteger(0, 22), 48)
	ball(tools, parent, "Leaves", size, foot + Vector3.new(0, height + size * 0.22, 0), color, Enum.Material.Grass)
	local angle = away + rng:NextNumber(-1.1, 1.1)
	local side = Vector3.new(math.cos(angle), 0, math.sin(angle)) * size * 0.32
	ball(tools, parent, "Leaves", size * 0.62, foot + side + Vector3.new(0, height + size * 0.02, 0), color:Lerp(Color3.new(1, 1, 1), 0.06), Enum.Material.Grass)
end

-- A round flowerbed at (x, z): the soil and four clumps of flowers round a green tuft.
local FLOWERS = {
	Color3.fromRGB(226, 64, 70),
	Color3.fromRGB(246, 206, 70),
	Color3.fromRGB(236, 132, 190),
	Color3.fromRGB(246, 244, 236),
	Color3.fromRGB(150, 110, 220),
	Color3.fromRGB(250, 150, 60),
}
local function flowerbed(tools: Tools, parent: Instance, x: number, z: number, rng: Random, index: number)
	tools.deco(cylinder(tools, parent, "Flowerbed", 0.3, 4.8, CFrame.new(x, WALK + 0.15, z) * UPRIGHT, Color3.fromRGB(82, 62, 46), Enum.Material.Ground))
	ball(tools, parent, "Leaves", 1.8, Vector3.new(x, WALK + 0.75, z), Color3.fromRGB(70, 112, 56), Enum.Material.Grass)
	for n = 1, 4 do
		local angle = n * math.pi / 2 + rng:NextNumber(-0.3, 0.3)
		local color = FLOWERS[(index + n) % #FLOWERS + 1]
		ball(tools, parent, "Flowers", rng:NextNumber(0.9, 1.25), Vector3.new(x + math.cos(angle) * 1.45, WALK + 0.6, z + math.sin(angle) * 1.45), color, Enum.Material.SmoothPlastic)
	end
end

-- A duck on the water at (x, z), looking `angle` (radians round the vertical).
local function duck(tools: Tools, parent: Instance, x: number, z: number, angle: number, body: Color3, head: Color3)
	local frame = CFrame.new(x, 0, z) * CFrame.Angles(0, angle, 0)
	tools.deco(tools.part(parent, "Duck", Vector3.new(0.9, 0.55, 1.5), frame * CFrame.new(0, 0.15, 0), body, Enum.Material.SmoothPlastic))
	local h = tools.deco(tools.part(parent, "DuckHead", Vector3.new(0.55, 0.55, 0.55), frame * CFrame.new(0, 0.7, -0.6), head, Enum.Material.SmoothPlastic))
	h.Shape = Enum.PartType.Ball
	tools.deco(tools.part(parent, "DuckBill", Vector3.new(0.3, 0.12, 0.35), frame * CFrame.new(0, 0.62, -0.98), Color3.fromRGB(240, 156, 40), Enum.Material.SmoothPlastic))
end

-- Builds the park on its block (Map.Park) into `parent` (World's Downtown folder).
function CentralPark.build(parent: Instance, tools: Tools)
	local P = Map.Park
	local part, deco = tools.part, tools.deco
	local folder = Instance.new("Folder")
	folder.Name = "CentralPark"
	folder.Parent = parent
	local cx, cz = P.x, P.z
	local origin = Vector3.new(cx, 0, cz)
	local rng = Random.new(P.seed)
	local pond = P.pond -- the middle to a flat side of the octagon
	local side = 2 * pond * math.tan(math.pi / 8) -- an octagon's side
	local cut = pond - side / 2 -- the square hole's corners cut off to make the octagon
	local floor = -P.depth + 0.5 -- the pond's floor (its top)
	local lawnEdge = HALF - P.walk
	local ringIn = pond + 1.5 -- the ring path: from the coping's outside …
	local ringOut = ringIn + P.ring -- … to here
	local function at(x: number, y: number, z: number): Vector3
		return Vector3.new(cx + x, y, cz + z)
	end
	local function polar(r: number, angle: number, y: number): Vector3
		return at(r * math.cos(angle), y, r * math.sin(angle))
	end

	-- ── The ground ──────────────────────────────────────────────────────────
	-- The slab: four pieces round the square hole under the pond, then its kerb (the eight pieces).
	for _, box in { { -HALF, HALF, -HALF, -pond }, { -HALF, HALF, pond, HALF }, { -HALF, -pond, -pond, pond }, { pond, HALF, -pond, pond } } do
		local x0, x1, z0, z1 = box[1], box[2], box[3], box[4]
		part(folder, "Sidewalk", Vector3.new(x1 - x0, WALK, z1 - z0), CFrame.new(at((x0 + x1) / 2, WALK / 2, (z0 + z1) / 2)), WALK_GREY, Enum.Material.Concrete)
	end
	require(script.Parent.Curbs).ring(folder, cx, cz, true)
	-- The lawn inside the sidewalk band, round the hole (its corners: the triangles below).
	for _, box in { { -lawnEdge, lawnEdge, -lawnEdge, -pond }, { -lawnEdge, lawnEdge, pond, lawnEdge }, { -lawnEdge, -pond, -pond, pond }, { pond, lawnEdge, -pond, pond } } do
		local x0, x1, z0, z1 = box[1], box[2], box[3], box[4]
		deco(part(folder, "Lawn", Vector3.new(x1 - x0, 0.08, z1 - z0), CFrame.new(at((x0 + x1) / 2, WALK + 0.04, (z0 + z1) / 2)), LAWN, Enum.Material.Grass))
	end
	-- The hole's corners: solid stone from the pond's floor up to the walk (the octagon's diagonal walls), the lawn on top.
	for _, s in { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } } do
		local sx, sz = s[1], s[2]
		local legX, legZ = Vector3.new(-sx, 0, 0), Vector3.new(0, 0, -sz)
		flatTriangle(tools, folder, "PondBank", cx + sx * pond, cz + sz * pond, legX, legZ, cut, floor, WALK - floor, STONE_DARK, Enum.Material.Slate)
		deco(flatTriangle(tools, folder, "Lawn", cx + sx * pond, cz + sz * pond, legX, legZ, cut, WALK, 0.08, LAWN, Enum.Material.Grass))
	end

	-- ── The pond ────────────────────────────────────────────────────────────
	-- The coping round it and a post at every corner.
	-- (6.11 review: the floor and the water are made with the ground's hole in World.buildGround, so a park that fails
	-- to build leaves no hole to the void)
	for k = 0, 7 do
		local angle = k * math.pi / 4
		local n = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local mid = origin + n * (pond + 0.6)
		part(folder, "Coping", Vector3.new(side, 2.4, 1.8), CFrame.lookAt(mid, mid + n) * CFrame.new(0, 0.4, 0), STONE, Enum.Material.Slate)
		local corner = polar((pond + 0.6) / math.cos(math.pi / 8), angle + math.pi / 8, 0.6)
		cylinder(tools, folder, "CopingPost", 2.8, 2.4, CFrame.new(corner) * UPRIGHT, STONE:Lerp(Color3.new(1, 1, 1), 0.12), Enum.Material.Slate)
	end
	-- Lily pads and three ducks on the water.
	for _, pad in { { -11, -9, 1.8 }, { -13.5, -5, 1.4 }, { 12, 9, 2 }, { 14, 4.5, 1.5 }, { 9.5, -13, 1.7 }, { -9, 13.5, 1.6 } } do
		deco(cylinder(tools, folder, "LilyPad", 0.06, pad[3], CFrame.new(at(pad[1], 0.04, pad[2])) * UPRIGHT, Color3.fromRGB(74, 124, 62), Enum.Material.Grass))
	end
	duck(tools, folder, cx - 12, cz + 2, math.rad(70), Color3.fromRGB(150, 128, 102), Color3.fromRGB(38, 92, 60))
	duck(tools, folder, cx - 10.2, cz + 4.5, math.rad(40), Color3.fromRGB(150, 128, 102), Color3.fromRGB(122, 98, 74))
	duck(tools, folder, cx + 11, cz - 8, math.rad(-120), Color3.fromRGB(244, 244, 238), Color3.fromRGB(244, 244, 238))

	-- ── The island and the fountain ─────────────────────────────────────────
	local top = WALK + 0.3 -- the island's top
	cylinder(tools, folder, "Island", top - floor, 2 * P.island, CFrame.new(at(0, (top + floor) / 2, 0)) * UPRIGHT, STONE, Enum.Material.Slate)
	deco(cylinder(tools, folder, "Lawn", 0.1, 2 * P.island - 1.6, CFrame.new(at(0, top + 0.05, 0)) * UPRIGHT, LAWN, Enum.Material.Grass))
	cylinder(tools, folder, "FountainBasin", 1.4, 7, CFrame.new(at(0, top + 0.7, 0)) * UPRIGHT, STONE:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.Marble)
	local basinWater = deco(cylinder(tools, folder, "FountainWater", 0.1, 6.2, CFrame.new(at(0, top + 1.25, 0)) * UPRIGHT, WATER, Enum.Material.Glass))
	basinWater.Transparency = 0.2
	cylinder(tools, folder, "FountainColumn", 2.8, 1.2, CFrame.new(at(0, top + 2.8, 0)) * UPRIGHT, STONE:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.Marble)
	cylinder(tools, folder, "FountainBowl", 0.6, 3.4, CFrame.new(at(0, top + 4.5, 0)) * UPRIGHT, STONE:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.Marble)
	-- The jet (it reads from across the safe zone, and glows at night) and its spray.
	local jet = deco(cylinder(tools, folder, "FountainJet", 9.5, 0.6, CFrame.new(at(0, top + 4.8 + 4.75, 0)) * UPRIGHT, Color3.fromRGB(226, 242, 252), Enum.Material.Glass))
	jet.Transparency = 0.3
	tools.nightLight(jet, Color3.fromRGB(196, 228, 255), Color3.fromRGB(226, 242, 252), "Glass")
	local spray = ball(tools, folder, "FountainSpray", 2.6, at(0, top + 14.6, 0), Color3.fromRGB(236, 246, 252), Enum.Material.Glass)
	spray.Transparency = 0.45
	local drops = Instance.new("ParticleEmitter")
	drops.Name = "Spray"
	drops.Color = ColorSequence.new(Color3.fromRGB(230, 244, 255))
	drops.LightEmission = 0.3
	drops.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.15) })
	drops.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	drops.Lifetime = NumberRange.new(1.1, 1.5)
	drops.Rate = 40
	drops.Speed = NumberRange.new(5, 8)
	drops.SpreadAngle = Vector2.new(70, 70)
	drops.Acceleration = Vector3.new(0, -26, 0)
	drops.Parent = spray
	pointLight(basinWater, 18, 1.2, Color3.fromRGB(170, 214, 255))
	tools.nightLight(basinWater, Color3.fromRGB(150, 210, 255), WATER, "Glass")

	-- ── The footbridge to the island (from the ring path on the south) ─────
	-- Its deck's top over z: up from the ring path over the coping, flat over the water, down onto the island. Its first
	-- stretch, over the ring path, has no railing (a low ramp you walk over going round the pond).
	local landing = ringIn + 4.5 -- (the ring path's outside)
	local function deck(z: number): number
		if z >= landing then
			return WALK
		elseif z >= pond - 1 then
			return WALK + (landing - z) / (landing - (pond - 1)) * 1.3
		elseif z >= 10 then
			return WALK + 1.3
		end
		return top + 0.1 + (z - (P.island - 0.3)) / (10 - (P.island - 0.3)) * (WALK + 1.2 - top)
	end
	local stops = { landing, ringIn, pond - 1, 10, P.island - 0.3 }
	for n = 1, #stops - 1 do
		local a, b = at(0, deck(stops[n]), stops[n]), at(0, deck(stops[n + 1]), stops[n + 1])
		local frame = CFrame.lookAt((a + b) / 2, b)
		local length = (b - a).Magnitude
		part(folder, "Bridge", Vector3.new(4.2, 0.4, length + 0.1), frame * CFrame.new(0, -0.2, 0), WOOD, Enum.Material.WoodPlanks)
		if n > 1 then
			for _, x in { -2, 2 } do
				part(folder, "BridgeRail", Vector3.new(0.25, 0.3, length + 0.1), frame * CFrame.new(x, 2.5, 0), WOOD:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Wood)
			end
		end
	end
	for n = 2, #stops do
		for _, x in { -2, 2 } do
			part(folder, "BridgePost", Vector3.new(0.4, 2.9, 0.4), CFrame.new(at(x, deck(stops[n]) + 1.4, stops[n])), WOOD:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Wood)
		end
	end
	for _, x in { -1.6, 1.6 } do
		cylinder(tools, folder, "BridgePier", WALK + 1.3 - 0.4 - floor, 0.8, CFrame.new(at(x, (WALK + 0.9 + floor) / 2, 14)) * UPRIGHT, WOOD:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Wood)
	end

	-- ── The paths ───────────────────────────────────────────────────────────
	-- The ring round the pond (eight pieces, each its outer side long; the diagonal ones a hair higher where they
	-- overlap), the paths to the middles of the sides and to the corners.
	local ringSide = 2 * ringOut * math.tan(math.pi / 8)
	for k = 0, 7 do
		local angle = k * math.pi / 4
		local n = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local thick = if k % 2 == 0 then 0.12 else 0.135
		local mid = origin + n * ((ringIn + ringOut) / 2) + Vector3.new(0, WALK + thick / 2, 0)
		deco(part(folder, "Path", Vector3.new(ringSide, thick, P.ring), CFrame.lookAt(mid, mid + n), GRAVEL, Enum.Material.Pebble))
	end
	for k = 0, 3 do
		local angle = k * math.pi / 2
		local n = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local mid = origin + n * ((ringOut - 0.5 + lawnEdge) / 2) + Vector3.new(0, WALK + 0.055, 0)
		deco(part(folder, "Path", Vector3.new(5, 0.11, lawnEdge - ringOut + 0.5), CFrame.lookAt(mid, mid + n), GRAVEL, Enum.Material.Pebble))
		local diagonal = angle + math.pi / 4
		local d = Vector3.new(math.cos(diagonal), 0, math.sin(diagonal))
		-- (its far end's corners stay on the lawn; 6.12.16 review: the north-east one ends before the footbridge's low
		-- ramp round that corner, Map.Park.corners)
		local reach = P.corners[k + 1]
		local dmid = origin + d * ((ringOut - 0.5 + reach) / 2) + Vector3.new(0, WALK + 0.0525, 0)
		deco(part(folder, "Path", Vector3.new(4, 0.105, reach - ringOut + 0.5), CFrame.lookAt(dmid, dmid + d), GRAVEL, Enum.Material.Pebble))
	end

	-- ── Benches, flowerbeds, lamps ──────────────────────────────────────────
	-- Two benches by every side path where it meets the ring, facing the pond; two flowerbeds by every corner path; a
	-- lamp at every outer corner of the ring (every other one lights the path) and one along every side path.
	for k = 0, 3 do
		local angle = k * math.pi / 2
		local n = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local t = Vector3.new(-n.Z, 0, n.X)
		for _, s in { -1, 1 } do
			bench(tools, folder, origin + n * (ringOut + 1.2) + t * (s * 6.8) + Vector3.new(0, WALK, 0), -n)
		end
		-- (6.12.15: not right by the footbridge, Map.Footbridge: further in along its path; 6.12.16: none where its
		-- wider walkway runs over the path all the way in, the north path: the bridge's lanterns light it)
		local reach = 37
		while reach > 31 and Map.footbridgeGap(cx + (n * reach + t * 3.8).X, cz + (n * reach + t * 3.8).Z) < 2.5 do
			reach -= 1
		end
		if Map.footbridgeGap(cx + (n * reach + t * 3.8).X, cz + (n * reach + t * 3.8).Z) >= 2.5 then
			lamp(tools, folder, origin + n * reach + t * 3.8 + Vector3.new(0, WALK, 0), false)
		end
		local diagonal = angle + math.pi / 4
		local d = Vector3.new(math.cos(diagonal), 0, math.sin(diagonal))
		local dt = Vector3.new(-d.Z, 0, d.X)
		for index, s in { -1, 1 } do
			local spot = origin + d * (ringOut + 2.8) + dt * (s * 6.5)
			flowerbed(tools, folder, spot.X, spot.Z, rng, k * 2 + index)
		end
	end
	local GAZEBO = 4 -- (the lawn between the west path and the north-west one: the gazebo stands there)
	for k = 0, 7 do
		if k ~= GAZEBO then -- (the gazebo has its own lantern; this one would stand at its steps)
			lamp(tools, folder, polar(29.5, (k + 0.5) * math.pi / 4, WALK), k % 2 == 0)
		end
	end

	-- ── Trees ───────────────────────────────────────────────────────────────
	-- Three in every lawn between two paths (a round one, and a column and a blossom further out), none where the
	-- gazebo stands; the trunks stay well inside the lawn (the walk line along the edge stays clear). 6.12.15: by the
	-- footbridge's ramp (Map.Footbridge) a tree whose crown would reach over it is a column (a narrow crown) where it
	-- stands, or else itself 4 studs further in toward the pond, or else left out.
	local CROWN: { [string]: number } = { round = 6.5, blossom = 5.5, column = 2.6 } -- (a crown's reach from its trunk)
	local function plant(at: Vector3, style: string, away: number)
		local inward = at - Vector3.new(at.X - cx, 0, at.Z - cz).Unit * 4
		for _, try in { { spot = at, look = style }, { spot = at, look = "column" }, { spot = inward, look = style } } do
			if Map.footbridgeGap(try.spot.X, try.spot.Z) >= CROWN[try.look] + 0.5 then
				tree(tools, folder, try.spot.X, try.spot.Z, try.look, rng, away)
				return
			end
		end
	end
	for k = 0, 7 do
		if k == GAZEBO then
			continue
		end
		local mid = (k + 0.5) * math.pi / 4
		plant(polar(37, mid, 0), "round", mid)
		for index, s in { -1, 1 } do
			plant(polar(41.5, mid + s * math.rad(11), 0), if (k + index) % 2 == 0 then "column" else "blossom", mid + s * math.rad(11))
		end
	end

	-- ── The gazebo (on the west lawn, its open side to the pond) ────────────
	do
		local mid = (GAZEBO + 0.5) * math.pi / 4
		local base = polar(37, mid, WALK)
		local frame = CFrame.lookAt(base, origin + Vector3.new(0, WALK, 0)) -- (-Z: to the pond)
		local floorTop = 0.5
		part(folder, "Gazebo", Vector3.new(10, floorTop, 10), frame * CFrame.new(0, floorTop / 2, 0), WOOD, Enum.Material.WoodPlanks)
		part(folder, "GazeboStep", Vector3.new(4, 0.25, 1.2), frame * CFrame.new(0, 0.125, -5.6), WOOD, Enum.Material.WoodPlanks)
		local white = Color3.fromRGB(236, 232, 222)
		for _, c in { { -4.4, -4.4 }, { 4.4, -4.4 }, { -4.4, 4.4 }, { 4.4, 4.4 } } do
			part(folder, "GazeboPost", Vector3.new(0.6, 7, 0.6), frame * CFrame.new(c[1], floorTop + 3.5, c[2]), white, Enum.Material.Wood)
		end
		for k = 0, 3 do
			local beam = frame * CFrame.Angles(0, k * math.pi / 2, 0)
			deco(part(folder, "GazeboBeam", Vector3.new(10, 0.6, 0.5), beam * CFrame.new(0, floorTop + 7.3, -4.6), white, Enum.Material.Wood))
			-- the roof: a pyramid of four corner wedges (each one's apex over its +X, -Z corner, at the roof's top)
			local roof = Instance.new("CornerWedgePart")
			roof.Name = "GazeboRoof"
			roof.Anchored = true
			roof.Size = Vector3.new(6, 4, 6)
			roof.CFrame = beam * CFrame.new(-3, floorTop + 7.6 + 2, 3)
			roof.Color = Color3.fromRGB(150, 70, 58)
			roof.Material = Enum.Material.Slate
			roof.CanTouch = false
			roof.Parent = folder
			if k > 0 then
				-- railings on three sides (the front, k = 0, is open)
				part(folder, "GazeboRail", Vector3.new(8.2, 0.3, 0.3), beam * CFrame.new(0, floorTop + 2.6, -4.4), white, Enum.Material.Wood)
			end
		end
		ball(tools, folder, "GazeboFinial", 0.8, (frame * CFrame.new(0, floorTop + 11.7, 0)).Position, Color3.fromRGB(214, 176, 72), Enum.Material.Metal)
		part(folder, "GazeboBench", Vector3.new(7, 0.35, 1.4), frame * CFrame.new(0, floorTop + 1.7, 3.6), WOOD, Enum.Material.WoodPlanks)
		local lantern = deco(part(folder, "GazeboLantern", Vector3.new(0.8, 1, 0.8), frame * CFrame.new(0, floorTop + 6.4, 0), LAMP_DIM, Enum.Material.Glass))
		pointLight(lantern, 16, 1.1, Color3.fromRGB(255, 208, 150))
		tools.nightLight(lantern, LAMP_LIT, LAMP_DIM, "Glass")
	end

	-- ── The signs (on the lawn's edge by every side path, facing its street and the shop across it) ─────
	for k = 0, 3 do
		local angle = k * math.pi / 2
		local n = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local t = Vector3.new(-n.Z, 0, n.X)
		-- (6.12.15: on the other side of its path where the footbridge's ramp runs; 6.12.16: or further along the edge)
		local spot = origin + n * (lawnEdge - 2) - t * 20 + Vector3.new(0, WALK, 0)
		for _, along in { 20, -32, 32 } do
			if Map.footbridgeGap(spot.X, spot.Z) < 8 then
				spot = origin + n * (lawnEdge - 2) + t * along + Vector3.new(0, WALK, 0)
			end
		end
		local frame = CFrame.lookAt(spot, spot + n)
		for _, x in { -5.5, 5.5 } do
			cylinder(tools, folder, "SignPost", 5.6, 0.35, frame * CFrame.new(x, 2.8, 0.3) * UPRIGHT, IRON, Enum.Material.Metal)
		end
		tools.sign(folder, `{string.upper(P.name)}  SAFE ZONE`, Vector3.new(12, 2.6, 0.3), frame * CFrame.new(0, 4.3, 0), Color3.new(1, 1, 1), nil, P.id, 3)
	end
end

return CentralPark
