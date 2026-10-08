--!strict
-- 6.8, the clients' portraits (the MISSIONS window, client/MissionsUi.luau): a head-and-shoulders bust of the person,
-- built here on the client from the very look their NPC wears in the world (shared/NpcLooks.luau look: the role's
-- clothes, the skin and hair from the name; the hats, the hair, the vest, the apron, the coat and the tie placed the
-- way server/Npcs.luau dresses an R15 body), shown in a ViewportFrame over a soft gradient in the chapter's colour.
-- No uploaded images, no server template, nothing of the courier's CharacterArt: the people of the world only.
--
--   Portrait.mount(holder, people, color, options?) -> boolean
--       fills `holder` (any GuiObject; its children are replaced) with the portrait of `people` (one Cast person, or
--       two side by side: the DUO twins); `color` is the background. options: { dim = true } for a locked chapter
--       (greyed), { key = string } to skip the rebuild when the same portrait is already there. Returns false when the
--       3D bust could not be made: then a flat stand-in is drawn instead (Portrait.flat: a silhouette, the role's
--       emoji, the colour).
-- The busts are built once per person and cloned for every portrait (a small model: ~20 parts).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NpcLooks = require(Shared.NpcLooks)
local Cast = require(Shared.Cast)

local Portrait = {}

export type Options = { dim: boolean?, key: string? }

local FACE = "rbxasset://textures/face.png" -- Roblox's own smile (the NPCs' default face)
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder standing up
local HEAD = 1.2 -- the head's size (the R15 default head is about this every way)
local TORSO = Vector3.new(2, 1.7, 1)
local ROLE_EMOJI: { [string]: string } = {
	clerk = "📋", doctor = "🩺", grocer = "🛒", mover = "📦", firefighter = "🚒", officer = "🎖", foreman = "👷",
	worker = "👷", rancher = "🤠", banker = "💼", nurse = "💉", farmer = "🌾", soldier = "🪖", guard = "🛡",
	cook = "🍳", teacher = "📚", rider = "🐴", shopkeeper = "🏪", icecream = "🍦", attendant = "⛽",
}

local cache: { [string]: Model } = {}

local function rgb(c: { number }?, fallback: Color3): Color3
	return if c then Color3.fromRGB(c[1], c[2], c[3]) else fallback
end

-- One piece of the bust: a part at `cframe` (in the bust's space: it looks down -Z, its feet at y = 0 under the torso).
local function piece(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, mesh: Enum.MeshType?, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	if shape then
		part.Shape = shape
	end
	if mesh then
		local special = Instance.new("SpecialMesh")
		special.MeshType = mesh
		special.Parent = part
	end
	part.Parent = model
	return part
end

-- The bust of one look (server/Npcs.luau dress, head and shoulders only), centred on x = 0.
local function bust(look: NpcLooks.Look): Model
	local model = Instance.new("Model")
	model.Name = look.name
	local skin = rgb(look.skin, Color3.fromRGB(241, 194, 160))
	local shirt = rgb(look.shirt, Color3.fromRGB(90, 110, 140))
	local sleeve = if look.coat then rgb(look.coat, shirt) else shirt
	local s = TORSO
	local torsoAt = CFrame.new(0, s.Y / 2, 0)
	piece(model, "UpperTorso", s, torsoAt, shirt, Enum.Material.Fabric)
	for _, side in { -1, 1 } do
		piece(model, "UpperArm", Vector3.new(0.95, s.Y, 0.95), CFrame.new(side * (s.X / 2 + 0.49), s.Y / 2, 0), sleeve, Enum.Material.Fabric)
	end
	if look.vest then
		local vest = piece(model, "Vest", Vector3.new(s.X * 1.04, s.Y * 0.92, s.Z * 1.12), torsoAt * CFrame.new(0, -s.Y * 0.03, 0), rgb(look.vest, shirt), Enum.Material.Fabric)
		if look.vest[1] > 190 and look.vest[2] > 190 then
			-- Hi-vis: a reflective stripe.
			vest.Material = Enum.Material.SmoothPlastic
			piece(model, "Stripe", Vector3.new(s.X * 1.06, s.Y * 0.08, s.Z * 1.14), torsoAt * CFrame.new(0, -s.Y * 0.2, 0), Color3.fromRGB(220, 220, 220), Enum.Material.Neon)
		end
	end
	if look.apron then
		piece(model, "Apron", Vector3.new(s.X * 0.7, s.Y * 0.8, 0.06), torsoAt * CFrame.new(0, -s.Y * 0.08, -s.Z * 0.53), rgb(look.apron, shirt), Enum.Material.Fabric)
	end
	if look.tie then
		piece(model, "Tie", Vector3.new(s.X * 0.12, s.Y * 0.72, 0.05), torsoAt * CFrame.new(0, s.Y * 0.06, -s.Z * 0.54), rgb(look.tie, shirt))
	end
	if look.coat then
		local coat = rgb(look.coat, shirt)
		for _, side in { -1, 1 } do
			piece(model, "CoatFront", Vector3.new(s.X * 0.36, s.Y * 1.02, s.Z * 1.16), torsoAt * CFrame.new(side * s.X * 0.36, -s.Y * 0.02, 0), coat, Enum.Material.Fabric)
		end
		piece(model, "Pocket", Vector3.new(s.X * 0.18, s.Y * 0.16, 0.04), torsoAt * CFrame.new(-s.X * 0.32, s.Y * 0.16, -s.Z * 0.6), Color3.fromRGB(60, 120, 200))
	end
	piece(model, "Collar", Vector3.new(s.X * 0.42, s.Y * 0.08, s.Z * 0.9), torsoAt * CFrame.new(0, s.Y * 0.48, 0), shirt:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Fabric)
	piece(model, "Neck", Vector3.new(0.5, 0.3, 0.5), CFrame.new(0, s.Y + 0.12, 0), skin)
	-- The head and its face.
	local h = HEAD
	local headAt = CFrame.new(0, s.Y + 0.25 + h / 2, 0)
	local head = piece(model, "Head", Vector3.one * h, headAt, skin)
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Face = Enum.NormalId.Front
	face.Texture = FACE
	face.Parent = head
	local hat = look.hat or "none"
	local hatColor = rgb(look.hatColor, Color3.fromRGB(60, 60, 66))
	if look.hair and hat ~= "helmet" and hat ~= "beanie" then
		piece(model, "Hair", Vector3.new(h * 1.04, h * 0.62, h * 1.06), headAt * CFrame.new(0, h * 0.24, h * 0.06), rgb(look.hair, Color3.new(0, 0, 0)), Enum.Material.SmoothPlastic, Enum.MeshType.Sphere)
	end
	if look.bandage then
		piece(model, "Bandage", Vector3.new(h * 0.24, h * 1.08, h * 1.1), headAt * CFrame.new(0, h * 0.2, 0) * UPRIGHT, Color3.fromRGB(246, 244, 238), Enum.Material.Fabric, nil, Enum.PartType.Cylinder)
	end
	if hat == "cowboy" then
		piece(model, "HatBrim", Vector3.new(0.08, h * 1.9, h * 1.9), headAt * CFrame.new(0, h * 0.36, 0) * UPRIGHT, hatColor, Enum.Material.Leather, nil, Enum.PartType.Cylinder)
		piece(model, "HatCrown", Vector3.new(h * 0.5, h * 0.95, h * 0.95), headAt * CFrame.new(0, h * 0.6, 0) * UPRIGHT, hatColor, Enum.Material.Leather, nil, Enum.PartType.Cylinder)
		piece(model, "HatBand", Vector3.new(h * 0.1, h * 0.97, h * 0.97), headAt * CFrame.new(0, h * 0.44, 0) * UPRIGHT, hatColor:Lerp(Color3.new(0, 0, 0), 0.6), Enum.Material.Leather, nil, Enum.PartType.Cylinder)
	elseif hat == "cap" then
		piece(model, "Cap", Vector3.new(h * 1.06, h * 0.5, h * 1.06), headAt * CFrame.new(0, h * 0.32, 0), hatColor, Enum.Material.Fabric, Enum.MeshType.Sphere)
		piece(model, "Visor", Vector3.new(h * 0.8, 0.06, h * 0.5), headAt * CFrame.new(0, h * 0.3, -h * 0.62) * CFrame.Angles(math.rad(8), 0, 0), hatColor:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Fabric)
	elseif hat == "hardhat" then
		piece(model, "Hardhat", Vector3.new(h * 1.14, h * 0.62, h * 1.16), headAt * CFrame.new(0, h * 0.36, 0), hatColor, Enum.Material.SmoothPlastic, Enum.MeshType.Sphere)
		piece(model, "HardhatBrim", Vector3.new(0.06, h * 1.3, h * 1.34), headAt * CFrame.new(0, h * 0.2, -0.04) * UPRIGHT, hatColor, Enum.Material.SmoothPlastic, nil, Enum.PartType.Cylinder)
	elseif hat == "beanie" then
		piece(model, "Beanie", Vector3.new(h * 1.08, h * 0.7, h * 1.08), headAt * CFrame.new(0, h * 0.28, 0.02), hatColor, Enum.Material.Fabric, Enum.MeshType.Sphere)
	elseif hat == "helmet" then
		piece(model, "Helmet", Vector3.new(h * 1.18, h * 0.72, h * 1.22), headAt * CFrame.new(0, h * 0.3, 0.03), hatColor, Enum.Material.SmoothPlastic, Enum.MeshType.Sphere)
	elseif hat == "chef" then
		piece(model, "ChefHat", Vector3.new(h * 0.8, h * 0.92, h * 0.92), headAt * CFrame.new(0, h * 0.8, 0) * UPRIGHT, hatColor, Enum.Material.Fabric, nil, Enum.PartType.Cylinder)
		piece(model, "ChefPuff", Vector3.new(h * 1.1, h * 0.5, h * 1.1), headAt * CFrame.new(0, h * 1.2, 0), hatColor, Enum.Material.Fabric, Enum.MeshType.Sphere)
	end
	return model
end

-- The bust of a Cast person (built once, cloned after). `twin`: somebody whose skin and hair they share (the DUO
-- twins, dressed alike).
local function bustOf(person: Cast.Person, twin: Cast.Person?): Model
	local key = if twin then `{person.id}+{twin.id}` else person.id
	local cached = cache[key]
	if not cached then
		local look = NpcLooks.look(person.look, person.name, person.job)
		if twin then
			local other = NpcLooks.look(twin.look, twin.name, twin.job)
			look.skin, look.hair = other.skin, other.hair
		end
		cached = bust(look)
		cache[key] = cached
	end
	return (cached :: Model):Clone()
end

-- The soft background: the colour at the top fading to a dark step of it at the bottom.
local function backdrop(holder: GuiObject, color: Color3, dim: boolean): Frame
	local back = Instance.new("Frame")
	back.Name = "PortraitBack"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(1, 1, 1)
	back.BorderSizePixel = 0
	local top = if dim then color:Lerp(Color3.fromRGB(52, 57, 64), 0.75) else color:Lerp(Color3.new(1, 1, 1), 0.08)
	local bottom = if dim then Color3.fromRGB(20, 23, 28) else color:Lerp(Color3.fromRGB(20, 23, 28), 0.72)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Parent = back
	back.Parent = holder
	return back
end

-- A flat stand-in (no 3D): a silhouette (a round head over round shoulders) in a step of the colour, the role's emoji.
function Portrait.flat(holder: GuiObject, color: Color3, role: string?, dim: boolean?)
	for _, child in holder:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local back = backdrop(holder, color, dim == true)
	local shade = color:Lerp(Color3.fromRGB(20, 23, 28), 0.45)
	local shoulders = Instance.new("Frame")
	shoulders.Size = UDim2.fromScale(0.78, 0.42)
	shoulders.Position = UDim2.fromScale(0.5, 1.06)
	shoulders.AnchorPoint = Vector2.new(0.5, 1)
	shoulders.BackgroundColor3 = shade
	shoulders.BorderSizePixel = 0
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.45, 0)
	round.Parent = shoulders
	shoulders.Parent = back
	local head = Instance.new("Frame")
	head.Size = UDim2.fromScale(0.4, 0.4)
	head.Position = UDim2.fromScale(0.5, 0.2)
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.BackgroundColor3 = shade
	head.BorderSizePixel = 0
	local ball = Instance.new("UICorner")
	ball.CornerRadius = UDim.new(0.5, 0)
	ball.Parent = head
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.Parent = head
	head.Parent = back
	local emoji = Instance.new("TextLabel")
	emoji.Size = UDim2.fromScale(0.34, 0.34)
	emoji.Position = UDim2.fromScale(0.96, 0.96)
	emoji.AnchorPoint = Vector2.new(1, 1)
	emoji.BackgroundTransparency = 1
	emoji.TextScaled = true
	emoji.Text = ROLE_EMOJI[role or ""] or "🙂"
	emoji.TextTransparency = if dim then 0.5 else 0
	emoji.Parent = back
end

-- The portrait of `people` (one or two Cast persons) in `holder` over `color`. See the header.
function Portrait.mount(holder: GuiObject, people: { Cast.Person }, color: Color3, options: Options?): boolean
	local o: Options = options or {}
	local dim = o.dim == true
	local key = o.key or `{#people}:{people[1] and people[1].id or "-"}:{color:ToHex()}:{dim}`
	local current = holder:FindFirstChild("PortraitBack")
	if current and current:GetAttribute("PortraitKey") == key then
		return true
	end
	local ok, err = pcall(function()
		for _, child in holder:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local back = backdrop(holder, color, dim)
		back:SetAttribute("PortraitKey", key)
		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "Portrait"
		viewport.Size = UDim2.fromScale(1, 1)
		viewport.BackgroundTransparency = 1
		viewport.Ambient = Color3.fromRGB(150, 152, 160)
		viewport.LightColor = Color3.fromRGB(255, 244, 228)
		viewport.LightDirection = Vector3.new(-0.45, -0.6, 1)
		viewport.ImageTransparency = if dim then 0.45 else 0
		viewport.Parent = back
		local world = Instance.new("Model")
		world.Name = "Busts"
		local count = math.max(1, #people)
		local spread = if count > 1 then 1.32 else 0
		for index, person in people do
			local first = people[1]
			local model = bustOf(person, if index > 1 and first and first.look == person.look then first else nil)
			-- Two side by side, the second a step back.
			local x = (index - (count + 1) / 2) * 2 * spread
			model:PivotTo(CFrame.new(x, 0, if index > 1 then 0.35 else 0) * CFrame.Angles(0, math.rad(if index > 1 then -8 else (if count > 1 then 8 else 0)), 0))
			model.Parent = world
		end
		world.Parent = viewport
		local camera = Instance.new("Camera")
		camera.FieldOfView = if count > 1 then 34 else 30
		local headY = TORSO.Y + 0.25 + HEAD / 2
		local distance = if count > 1 then 8.6 else 6.2
		camera.CFrame = CFrame.lookAt(Vector3.new(0.35, headY - 0.05, -distance), Vector3.new(0, headY - 0.62, 0))
		camera.Parent = viewport
		viewport.CurrentCamera = camera
	end)
	if not ok then
		warn(`[Portrait] a flat stand-in for {key}: {err}`)
		Portrait.flat(holder, color, if people[1] then people[1].look else nil, dim)
	end
	return ok
end

-- The portrait of a chapter's client (and the twins' partner).
function Portrait.people(clientId: string, partnerId: string?): { Cast.Person }
	local list: { Cast.Person } = {}
	local main = Cast.find(clientId)
	if main then
		table.insert(list, main)
	end
	local partner = if partnerId then Cast.find(partnerId) else nil
	if partner then
		table.insert(list, partner)
	end
	return list
end

return Portrait
