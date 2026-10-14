--!strict
-- 7.2, the house a move empties in the owner's own Blender model (the owner: "a 3D model of that house, so it looks like
-- a classic European house"; design/blender-house/house.py → roblox/ZDCHouseArt.fbx). The owner imports ZDCHouseArt.fbx
-- once in Roblox Studio (File → Import 3D, the defaults) and publishes. A house's own parts come here in a Model with
-- its "House" box: server/World.luau's buildHouse (each Suburbs chalet, Marge's 155 Willow Ln among them) and, 8.0.5,
-- server/SandboxWorld.luau's The Old Chalet (house.py's TARGET "sandbox", the model the owner imports now). A house of
-- HouseMesh.Homes whose box is the model's (mark_box) wears the model's MeshParts (anchored, not colliding, not queried,
-- not touched). Its own parts stay where they are, invisible: the House box (the model's walls stand on its faces) and
-- whatever else collides on the ground still does (the sandbox's FrontDoor keeps its "Enter house"); what stands over
-- the walls (the old roof and gables, under the model's roof) stops colliding. No import, a house not listed or of
-- another size: the house as it was built.
--
--   HouseMesh.start()               at the server's start: finds the import and takes it out of the world
--   HouseMesh.dress(model, homeId)  dresses one house (World's buildHouse); false: left as it was
--   HouseMesh.Homes                 the homes that wear it (Map.Homes ids)
--   HouseMesh.Looks                 each finish's colour and material
--
-- The pieces are named "house_<finish>" ("house2_<finish>" ... where a finish has more than 10,000 triangles;
-- house.py export_game). mark_o / mark_x / mark_y / mark_z are the middle of the house's bottom and 10 studs to the
-- right, up and back (the game's axes: the front, to the street, is -Z); mark_box is the box's corner (W / 2, H, D / 2).
local ServerStorage = game:GetService("ServerStorage")

local DayNight = require(script.Parent.DayNight)

local HouseMesh = {}

local NAME = "ZDCHouseArt"

HouseMesh.Homes = {
	home_suburbs_2_0_00 = true, -- 155 Willow Ln, Marge's (the city's moves' prologue, Config.Moving)
	sandbox_house = true, -- 8.0.5: the sandbox's The Old Chalet (server/SandboxWorld.luau, SandboxMap.House)
} :: { [string]: boolean }

type Look = { color: Color3, material: Enum.Material, reflectance: number?, night: Color3? }
local function hex(code: string): Color3
	return Color3.fromRGB(tonumber(code:sub(1, 2), 16) :: number, tonumber(code:sub(3, 4), 16) :: number, tonumber(code:sub(5, 6), 16) :: number)
end
local M = Enum.Material
-- house.py's FINISHES. Smooth materials (the model has no texture coordinates); the lantern glows at night.
local LOOKS: { [string]: Look } = {
	plaster = { color = hex("E8D3A2"), material = M.SmoothPlastic },
	trim = { color = hex("F3F0E8"), material = M.SmoothPlastic },
	stone = { color = hex("8D8A84"), material = M.SmoothPlastic },
	stone2 = { color = hex("E3DCCB"), material = M.SmoothPlastic },
	tile = { color = hex("B5502E"), material = M.SmoothPlastic },
	tile2 = { color = hex("A44629"), material = M.SmoothPlastic },
	tile3 = { color = hex("8C3A22"), material = M.SmoothPlastic },
	soffit = { color = hex("7A5A3E"), material = M.SmoothPlastic },
	door = { color = hex("2F5E45"), material = M.SmoothPlastic },
	brass = { color = hex("C9A44C"), material = M.Metal, reflectance = 0.15 },
	glass = { color = hex("2E3C48"), material = M.Glass, reflectance = 0.2 },
	zinc = { color = hex("9BA2A6"), material = M.Metal },
	black = { color = hex("1C1C1E"), material = M.SmoothPlastic },
	glow = { color = hex("D9CBA6"), material = M.SmoothPlastic, night = hex("FFE2A8") },
	wood2 = { color = hex("6B4A2F"), material = M.SmoothPlastic },
	red = { color = hex("D1372F"), material = M.SmoothPlastic },
	leaf = { color = hex("3E7A38"), material = M.SmoothPlastic },
	shrub = { color = hex("4F7F3B"), material = M.SmoothPlastic },
	curtain = { color = hex("EEE7D8"), material = M.SmoothPlastic },
}
HouseMesh.Looks = LOOKS

type Piece = { finish: string, part: BasePart, cf: CFrame, size: Vector3 }

local pieces: { Piece }? = nil
local box: Vector3? = nil -- the house the model was made for (W, H, D)
local tried = false
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
			if child:IsA("Model") and child:FindFirstChild("mark_o", true) and child:FindFirstChild("mark_box", true) then
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
	art.Parent = ServerStorage -- out of the world: only the clones on the house are seen
	local marks: { [string]: Vector3 } = {}
	for _, d in art:GetDescendants() do
		if d:IsA("BasePart") and d.Name:sub(1, 5) == "mark_" then
			marks[d.Name:sub(6)] = d.Position
		end
	end
	local o, x, y, z, corner = marks.o, marks.x, marks.y, marks.z, marks.box
	if not (o and x and y and z and corner) then
		say("the markers mark_o, mark_x, mark_y, mark_z and mark_box are missing; the house keeps its own look")
		return
	end
	local scale = (x - o).Magnitude / 10
	local ux = (x - o).Unit
	local uz = ux:Cross((y - o).Unit).Unit
	local uy = uz:Cross(ux).Unit
	if scale < 0.01 or uz:Dot((z - o).Unit) < 0.9 then
		say("the import came out mirrored or flat; the house keeps its own look")
		return
	end
	local function off(v: Vector3): number
		return math.abs(v.Magnitude / 10 - scale) / scale
	end
	if off(y - o) > 0.02 or off(z - o) > 0.02 or math.abs(ux:Dot((y - o).Unit)) > 0.02 or math.abs(ux:Dot((z - o).Unit)) > 0.02 then
		say(`the markers moved before the game read them (the import unanchored in Workspace?): put it in ServerStorage and save; the house keeps its own look`)
		return
	end
	local frame = CFrame.new(o) * CFrame.fromMatrix(Vector3.zero, ux, uy, uz) -- the house's bottom middle, the game's axes
	local c = frame:PointToObjectSpace(corner) / scale
	local found: { Piece } = {}
	local turn: CFrame?, moved = nil, false
	for _, d in art:GetDescendants() do
		if not d:IsA("BasePart") or d.Name:sub(1, 5) == "mark_" then
			continue
		end
		local _, finish = string.match(d.Name, "^(%a+%d*)_(%w+)$")
		local look = if finish then LOOKS[finish] else nil
		if not finish or not look then
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
		d.Anchored = true
		d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
		d.Material = look.material
		d.Color = look.color
		d.Transparency = 0
		d.Reflectance = look.reflectance or 0
		d.CastShadow = finish ~= "glass" and finish ~= "glow"
		local rel = frame:ToObjectSpace(d.CFrame)
		if not turn then
			turn = rel - rel.Position
		elseif rel.RightVector:Dot(turn.RightVector) < 0.999 or rel.UpVector:Dot(turn.UpVector) < 0.999 then
			moved = true -- (the importer turns every piece alike: one turned otherwise was thrown about)
		end
		table.insert(found, { finish = finish, part = d, cf = rel - rel.Position + rel.Position / scale, size = d.Size / scale })
	end
	if #found == 0 then
		say("no pieces named house_<finish>; the house keeps its own look")
		return
	elseif moved then
		say("its pieces moved before the game read them (the import unanchored in Workspace?): put it in ServerStorage and save; the house keeps its own look")
		return
	end
	pieces = found
	box = Vector3.new(math.abs(c.X) * 2, c.Y, math.abs(c.Z) * 2)
end

local function ready(): boolean
	if not tried then
		local ok, err = pcall(function(): any
			loadArt()
			return nil
		end)
		if not ok then
			say(tostring(err))
		end
	end
	return pieces ~= nil
end

-- At the server's start (server/Main.server.luau): the imported model out of the world before anybody sees it.
function HouseMesh.start()
	ready()
end

-- Dresses one of World's houses (`model`: its House box, Roof wedges, Door and Windows): the model's pieces on the
-- box's bottom middle, the house's own parts invisible (still colliding where they did). False: left as it was.
function HouseMesh.dress(model: Model, homeId: string): boolean
	if not HouseMesh.Homes[homeId] or not ready() then
		return false
	end
	local house = model:FindFirstChild("House")
	local want = box
	if not (house and house:IsA("BasePart")) or not want then
		return false
	end
	if (house.Size - want).Magnitude > 0.05 then
		say(`{homeId}: the house is {house.Size}, the model was made for {want}; it keeps its own look`)
		return false
	end
	local top = house.Position.Y + house.Size.Y / 2
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CastShadow = false
			-- (over the walls the model's own roof stands: the old one's wedges and gables, unseen, would poke through
			-- it, so they stop colliding; the box below and everything on the ground keep theirs)
			local cf, size = d.CFrame, d.Size
			local reach = (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z) / 2
			if d ~= house and d.Position.Y - reach >= top - 0.05 then
				d.CanCollide, d.CanQuery = false, false
			end
		end
	end
	local base = house.CFrame * CFrame.new(0, -house.Size.Y / 2, 0)
	for _, item in pieces :: { Piece } do
		local p = item.part:Clone()
		p.Size = item.size
		p.CFrame = base * item.cf
		p.Parent = model
		local look = LOOKS[item.finish]
		if look.night then
			DayNight.nightLight(p, look.night, look.color, "SmoothPlastic")
		end
	end
	model:SetAttribute("MeshArt", true)
	return true
end

return HouseMesh
