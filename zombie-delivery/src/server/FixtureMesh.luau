--!strict
-- 8.7.1, the house's fixtures in the owner's own Blender model (the owner: "udělej kuchyň a koupelnu";
-- design/blender-fixtures/fixtures.py → roblox/ZDCFixtureArt.fbx, the contract design/blender-fixtures/KONTRAKT.md).
-- The owner imports ZDCFixtureArt.fbx once in Roblox Studio (File → Import 3D, the defaults) and publishes; this finds
-- the imported model (a top-level child of ServerStorage or Workspace named ZDCFixtureArt, or one holding mark_o and
-- mark_counter), learns from the markers how the importer turned and scaled it, keeps its MeshParts in ServerStorage
-- and dresses the fixtures server/HouseInterior.luau builds: the kitchen's counters, stove, sink, wall cupboards, hood,
-- corner bench and its shelf, the bathroom's tub, toilet and basin, the living room's Kachelofen, the garage's
-- workbench, shelves and door. HouseInterior puts each fixture's parts in a Model "Fixture_<kind>" (attribute Fixture)
-- and hands it here: its parts that collide stay where they are, invisible and shadowless (still colliding and
-- queried: the counters, the tub, the Kachelofen's bench), the others go, and the kind's MeshParts (anchored, not
-- colliding, not queried, not touched) take their place. No import, a kind it lacks, a fixture of another size (the
-- farm's own counters) or an import that physics threw about or that came out mirrored: the parts' look as it was.
--
--   FixtureMesh.start()                       at the server's start: finds the import and takes it out of the world
--   FixtureMesh.has(kind)                     has the import this fixture kind?
--   FixtureMesh.dress(model, kind, at, size)  dresses one fixture (`at` its frame, `size` its box, as the plan has
--                                             them); false: left as it was
--   FixtureMesh.Kinds                         the fixture kinds the model makes (HouseInterior builds them in a Model)
--   FixtureMesh.Looks                         each finish's colour and material (fixtures.py's FINISHES)
--
-- The pieces are named "<kind>_<finish>" (fixtures.py, as furniture.py's export_game); "mark_<kind>" is the bottom
-- middle of that kind's box (its frame: x along the wall, y up, the front -Z into the room), "mark_<kind>_box" the box's
-- corner (W / 2, H, D / 2), mark_o / mark_x / mark_y / mark_z the origin and 10 studs to the right, up and back (the
-- game's axes). Four finishes take the colour the house rolled for that fixture, read from its parts before they go (a
-- palette): tile (the Kachelofen's tiles: its part Stove), tile2 (its upper tier: Upper), pine (the benches' wood: Seat,
-- the Kachelofen's StoveBench) and cushion (Cushion). A Neon finish (the fire's glow) stays small: a piece whose biggest
-- face is over Config.SandboxLight.Caps.NeonArea is shown unlit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local FixtureMesh = {}

local NAME = "ZDCFixtureArt"

-- The contract's fixture kinds (shared/HouseLayout.luau's plans; every size is fixed).
FixtureMesh.Kinds = {
	counter = true,
	stove = true,
	sink = true,
	cabinets = true,
	hood = true,
	corner_bench = true,
	bench = true,
	corner_shelf = true,
	tub = true,
	toilet = true,
	basin = true,
	kachelofen = true,
	workbench = true,
	shelves = true,
	garage_door = true,
} :: { [string]: boolean }

type Look = { color: Color3, material: Enum.Material, palette: { string }?, transparency: number?, reflectance: number? }
local function hex(code: string): Color3
	return Color3.fromRGB(tonumber(code:sub(1, 2), 16) :: number, tonumber(code:sub(3, 4), 16) :: number, tonumber(code:sub(5, 6), 16) :: number)
end
local M = Enum.Material
-- fixtures.py's FINISHES (a palette finish: its colour here when the fixture has no such part).
local LOOKS: { [string]: Look } = {
	tile = { color = hex("406E54"), material = M.SmoothPlastic, palette = { "Stove" }, reflectance = 0.08 },
	tile2 = { color = hex("5C8170"), material = M.SmoothPlastic, palette = { "Upper" }, reflectance = 0.08 },
	pine = { color = hex("BA8652"), material = M.Wood, palette = { "Seat", "StoveBench" } },
	cushion = { color = hex("B03430"), material = M.Fabric, palette = { "Cushion" } },
	wood = { color = hex("966A4A"), material = M.Wood },
	paint = { color = hex("C69864"), material = M.Wood },
	enamel = { color = hex("F0EEE8"), material = M.SmoothPlastic, reflectance = 0.1 },
	white = { color = hex("F6F6F4"), material = M.SmoothPlastic, reflectance = 0.06 },
	steel = { color = hex("B0B4BA"), material = M.Metal },
	chrome = { color = hex("D7DBDF"), material = M.Metal, reflectance = 0.3 },
	iron = { color = hex("2E2A28"), material = M.Metal },
	dark = { color = hex("242428"), material = M.SmoothPlastic },
	glass = { color = hex("18181A"), material = M.Glass, reflectance = 0.1 },
	water = { color = hex("96C8E2"), material = M.Glass, transparency = 0.3 },
	mirror = { color = hex("C4D6E0"), material = M.Glass, reflectance = 0.5 },
	glow = { color = hex("FF8232"), material = M.Neon },
	candle = { color = hex("F4ECD6"), material = M.SmoothPlastic },
	flowers = { color = hex("C4704A"), material = M.Fabric },
	board = { color = hex("BEA078"), material = M.SmoothPlastic },
	blue = { color = hex("3C5A8C"), material = M.Metal },
	card = { color = hex("C49E6C"), material = M.SmoothPlastic },
	door = { color = hex("C8CCCE"), material = M.Metal },
}
FixtureMesh.Looks = LOOKS

type Piece = { finish: string, part: BasePart, cf: CFrame, size: Vector3 }
type Kind = { box: Vector3, pieces: { Piece } }

local kinds: { [string]: Kind }? = nil
local tried = false
local said: { [string]: boolean } = {} -- (a fixture of another size: said once)
local function say(text: string)
	pcall(warn, `{NAME}: {text}`) -- (Studio's output; nothing outside Roblox)
end

-- The imported model: by its name, else any top-level model with the markers in it.
local function find(): Instance?
	for _, place in { ServerStorage, workspace } :: { Instance } do
		local named = place:FindFirstChild(NAME)
		if named then
			return named
		end
	end
	for _, place in { ServerStorage, workspace } :: { Instance } do
		for _, child in place:GetChildren() do
			if child:IsA("Model") and child:FindFirstChild("mark_o", true) and child:FindFirstChild("mark_counter", true) then
				return child
			end
		end
	end
	return nil
end

local function loadArt()
	tried = true
	local art = find()
	if not art then
		return
	end
	art.Parent = ServerStorage -- out of the world: only the clones in the houses are seen
	local marks: { [string]: Vector3 } = {}
	for _, d in art:GetDescendants() do
		if d:IsA("BasePart") and d.Name:sub(1, 5) == "mark_" then
			marks[d.Name:sub(6)] = d.Position
		end
	end
	local o, x, y, z = marks.o, marks.x, marks.y, marks.z
	if not (o and x and y and z) then
		say("the markers mark_o, mark_x, mark_y and mark_z are missing; the fixtures keep their own look")
		return
	end
	local scale = (x - o).Magnitude / 10
	local ux = (x - o).Unit
	local uz = ux:Cross((y - o).Unit).Unit
	local uy = uz:Cross(ux).Unit
	if scale < 0.01 or uz:Dot((z - o).Unit) < 0.9 then
		say("the import came out mirrored or flat; the fixtures keep their own look")
		return
	end
	local function off(v: Vector3): number
		return math.abs(v.Magnitude / 10 - scale) / scale
	end
	if off(y - o) > 0.02 or off(z - o) > 0.02 or math.abs(ux:Dot((y - o).Unit)) > 0.02 or math.abs(ux:Dot((z - o).Unit)) > 0.02 then
		say(`the markers moved before the game read them (the import unanchored in Workspace?): put it in ServerStorage and save; the fixtures keep their own look`)
		return
	end
	local axes = CFrame.fromMatrix(Vector3.zero, ux, uy, uz) -- the game's axes as the importer turned them
	local found: { [string]: Kind } = {}
	local count = 0
	local turn: CFrame?, moved = nil, false
	for _, d in art:GetDescendants() do
		if not d:IsA("BasePart") or d.Name:sub(1, 5) == "mark_" then
			continue
		end
		local kind, finish = string.match(d.Name, "^(.+)_(%w+)$")
		local look = if finish then LOOKS[finish] else nil
		local origin = if kind then marks[kind] else nil
		local corner = if kind then marks[kind .. "_box"] else nil
		if not kind or not finish or not look or not origin or not corner or not FixtureMesh.Kinds[kind] then
			continue
		end
		for _, extra in d:GetChildren() do
			if extra:IsA("SurfaceAppearance") or extra:IsA("Decal") or extra:IsA("Texture") then
				extra:Destroy() -- (the importer's own material: the finish below is the look)
			end
		end
		if d:IsA("MeshPart") then
			pcall(function()
				d.TextureID = ""
			end)
		end
		local size = d.Size / scale
		d.Anchored = true
		d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
		d.Material = look.material
		d.Color = look.color
		d.Transparency = look.transparency or 0
		d.Reflectance = look.reflectance or 0
		d.CastShadow = look.material ~= M.Neon and (look.transparency or 0) == 0 -- (the glow and what light passes through)
		if look.material == M.Neon and math.max(size.X * size.Y, size.Y * size.Z, size.Z * size.X) > Config.SandboxLight.Caps.NeonArea then
			d.Material = M.SmoothPlastic -- (a big Neon face lights up the room: Config.SandboxLight.Caps)
			say(`{d.Name} is too big to glow; it is shown unlit`)
		end
		local frame = CFrame.new(origin) * axes -- the kind's bottom middle, the game's axes
		local rel = frame:ToObjectSpace(d.CFrame)
		if not turn then
			turn = rel - rel.Position
		elseif rel.RightVector:Dot(turn.RightVector) < 0.999 or rel.UpVector:Dot(turn.UpVector) < 0.999 then
			moved = true -- (the importer turns every piece alike: one turned otherwise was thrown about)
		end
		local entry = found[kind]
		if not entry then
			local c = frame:PointToObjectSpace(corner) / scale
			entry = { box = Vector3.new(math.abs(c.X) * 2, c.Y, math.abs(c.Z) * 2), pieces = {} }
			found[kind] = entry
		end
		table.insert((entry :: Kind).pieces, { finish = finish, part = d, cf = rel - rel.Position + rel.Position / scale, size = size })
		count += 1
	end
	if count == 0 then
		say("no pieces named <kind>_<finish>; the fixtures keep their own look")
		return
	elseif moved then
		say("its pieces moved before the game read them (the import unanchored in Workspace?): put it in ServerStorage and save; the fixtures keep their own look")
		return
	end
	kinds = found
end

-- Has the imported model this fixture kind?
function FixtureMesh.has(kind: string): boolean
	if not tried then
		local ok, err = pcall(function(): any
			loadArt()
			return nil
		end)
		if not ok then
			say(tostring(err))
		end
	end
	return kinds ~= nil and (kinds :: { [string]: Kind })[kind] ~= nil
end

-- At the server's start (server/Main.server.luau, server/SandboxBoot.luau): the imported model out of the world before
-- anybody sees it (the houses are built only when a move starts).
function FixtureMesh.start()
	FixtureMesh.has("counter")
end

-- Dresses one fixture HouseInterior built (`model` its Model Fixture_<kind> holding its parts, `at` its frame: the
-- bottom middle of its box, `size` the box): the palette's colours read from its parts, the parts that collide hidden
-- (they keep colliding), the others gone, the kind's pieces at `at`. False: left as it was.
function FixtureMesh.dress(model: Model, kind: string, at: CFrame, size: Vector3): boolean
	if not FixtureMesh.has(kind) then
		return false
	end
	local entry = (kinds :: { [string]: Kind })[kind]
	if (size - entry.box).Magnitude > 0.05 then
		local key = `{kind} {string.format("%.2f × %.2f × %.2f", size.X, size.Y, size.Z)}`
		if not said[key] then
			said[key] = true
			say(`a {key}, the model's is {string.format("%.2f × %.2f × %.2f", entry.box.X, entry.box.Y, entry.box.Z)}: it keeps its own look`)
		end
		return false
	end
	local ok, err = pcall(function(): any
		local colours: { [string]: Color3 } = {} -- (the palette: the house's rolled colours, before the parts go)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and not colours[d.Name] then
				colours[d.Name] = d.Color
			end
		end
		local clones: { BasePart } = {}
		for _, item in entry.pieces do
			local p = item.part:Clone()
			p.Size = item.size
			p.CFrame = at * item.cf
			local palette: { string } = LOOKS[item.finish].palette or {}
			for _, name in palette do
				local colour = colours[name]
				if colour then
					p.Color = colour
					break
				end
			end
			table.insert(clones, p)
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				if d.CanCollide then
					d.Transparency = 1
					d.CastShadow = false
				else
					d:Destroy()
				end
			end
		end
		for _, p in clones do
			p.Parent = model
		end
		model:SetAttribute("MeshArt", true)
		return nil
	end)
	if not ok then
		say(`{kind}: {err}`)
		return false
	end
	return true
end

return FixtureMesh
