--!strict
-- 6.12: the STYLE app's live 3D preview (client/StyleApp.luau): a ViewportFrame with a local, still copy of your courier
-- or of the vehicle you have out, the item you look at put on it by the very builder the server uses
-- (shared/StyleBuild.luau), so what you try is what everybody will see.
--   * COURIER: your character cloned (its own head, face, clothes and accessories, KitWear's vest and bag, the STYLE
--     looks it wears); the hat or the jacket tried goes on in place of the worn one (a hat hides your own hats and
--     hair), a vest or bag colour recolours the Courier Vest's cloth or the bag's body. No character yet: the classic
--     R15 block body in the courier's workwear (shared/AvatarLook.luau) stands in.
--   * VEHICLE: your car or bike out in the world (workspace.Cars, its OwnerId) cloned: a wrap over its painted panels
--     (the StylePaint mark the server puts on them), a bike's frame, a decal laid round its parts as on the server.
--     None out, or one the item does not fit (a wrap on a bike): nothing shown, and why.
--   StylePreview.show(holder, tab, def?) -> (kind, note)   fills `holder` (its children replaced): kind "courier",
--       "mannequin" or "vehicle", or "" (nothing to show; `note` says why)
--   StylePreview.clear(holder)
-- The copy is anchored and inert: no scripts, joints, prompts, lights, sounds or name tags inside.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local AvatarLook = require(Shared.AvatarLook)
local Economy = require(Shared.Economy)
local Style = require(Shared.Style)
local StyleBuild = require(Shared.StyleBuild)
local StyleLooks = require(Shared.StyleLooks)

local StylePreview = {}

local NAME = "StylePreview"

-- The classic R15 block body (server/CharacterArt "walker"'s parts with the 1.2 head), standing, for the mannequin.
local BODY: { { any } } = {
	{ "LowerTorso", { 2, 0.4, 1 }, { 0, -0.75, 0 }, "TorsoColor" },
	{ "UpperTorso", { 2, 1.6, 1 }, { 0, 0.25, 0 }, "TorsoColor" },
	{ "Head", { 1.2, 1.2, 1.2 }, { 0, 1.65, 0 }, "HeadColor" },
	{ "LeftUpperArm", { 1, 1.17, 1 }, { -1.5, 0.465, 0 }, "TorsoColor" },
	{ "RightUpperArm", { 1, 1.17, 1 }, { 1.5, 0.465, 0 }, "TorsoColor" },
	{ "LeftLowerArm", { 1, 0.53, 1 }, { -1.5, -0.385, 0 }, "LeftArmColor" },
	{ "RightLowerArm", { 1, 0.53, 1 }, { 1.5, -0.385, 0 }, "RightArmColor" },
	{ "LeftHand", { 1, 0.3, 1 }, { -1.5, -0.8, 0 }, "LeftArmColor" },
	{ "RightHand", { 1, 0.3, 1 }, { 1.5, -0.8, 0 }, "RightArmColor" },
	{ "LeftUpperLeg", { 1, 0.95, 1 }, { -0.5, -1.425, 0 }, "LeftLegColor" },
	{ "RightUpperLeg", { 1, 0.95, 1 }, { 0.5, -1.425, 0 }, "RightLegColor" },
	{ "LeftLowerLeg", { 1, 0.77, 1 }, { -0.5, -2.285, 0 }, "LeftLegColor" },
	{ "RightLowerLeg", { 1, 0.77, 1 }, { 0.5, -2.285, 0 }, "RightLegColor" },
	{ "LeftFoot", { 1, 0.3, 1.2 }, { -0.5, -2.82, -0.1 }, "LeftLegColor" },
	{ "RightFoot", { 1, 0.3, 1.2 }, { 0.5, -2.82, -0.1 }, "RightLegColor" },
}

local INERT: { string } = { "JointInstance", "WeldConstraint", "Constraint", "LuaSourceContainer", "ProximityPrompt", "ParticleEmitter", "Sound", "Light", "BillboardGui" }

-- A still copy: every part anchored and out of the physics, nothing alive inside.
local function still(model: Instance)
	for _, obj in model:GetDescendants() do
		if obj:IsA("BasePart") then
			obj.Anchored = true
			obj.CanCollide = false
			obj.CanTouch = false
			obj.CanQuery = false
		else
			for _, class in INERT do
				if obj:IsA(class) then
					obj:Destroy()
					break
				end
			end
		end
	end
end

-- The mannequin: the classic R15 block body in the workwear, facing -Z.
function StylePreview.mannequin(): Model
	local model = Instance.new("Model")
	model.Name = "Mannequin"
	for _, b in BODY do
		local p = Instance.new("Part")
		p.Name = b[1]
		p.Size = Vector3.new(b[2][1], b[2][2], b[2][3])
		p.CFrame = CFrame.new(b[3][1], b[3][2], b[3][3])
		local c = AvatarLook.Workwear[b[4]] or { 120, 120, 120 }
		p.Color = Color3.fromRGB(c[1], c[2], c[3])
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Parent = model
	end
	model.PrimaryPart = model:FindFirstChild("UpperTorso") :: BasePart
	return model
end

-- Your character, copied (Characters are not Archivable: allowed for the copy only).
local function copyCharacter(): Model?
	local player = Players.LocalPlayer
	local character = player and player.Character
	if not character or typeof(character) ~= "Instance" or not character:FindFirstChild("UpperTorso") then
		return nil
	end
	local was = character.Archivable
	character.Archivable = true
	local ok, copy = pcall(function()
		return character:Clone()
	end)
	character.Archivable = was
	if not ok or not copy then
		return nil
	end
	local model = (copy :: any) :: Model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	return model
end

-- The item tried on the courier's copy (the worn one in its slot goes first).
function StylePreview.dress(copy: Model, def: Config.CosmeticDef)
	if def.slot == "hat" or def.slot == "jacket" then
		local old = copy:FindFirstChild(StyleBuild.Names[def.slot])
		if old then
			old:Destroy()
		end
		StyleBuild.courier(copy, def, true)
		if def.slot == "hat" then
			StyleBuild.hideOwn(copy, true)
		end
	elseif def.slot == "vest" then
		local vest = copy:FindFirstChild("KitVestArt")
		if vest and vest:FindFirstChild("VestL") then -- (the Courier Vest's own piece: an armoured vest takes no dye)
			StyleBuild.tint(vest:GetChildren(), StyleLooks.Vest, def)
		end
	elseif def.slot == "bag" then
		local bag = copy:FindFirstChild("KitBagArt")
		local pivot = copy:FindFirstChild("KitBagPivot")
		local id = if pivot then pivot:GetAttribute("Bag") else nil
		local shares = StyleLooks.Bags[if type(id) == "string" then id else "bag"]
		if bag and shares then
			StyleBuild.tint(bag:GetChildren(), shares, def)
		end
	end
end

-- Your vehicle out in the world (workspace.Cars: the model whose OwnerId is yours), or nil.
local function liveVehicle(): Model?
	local cars = workspace:FindFirstChild("Cars")
	local me = Players.LocalPlayer
	if not cars or not me then
		return nil
	end
	for _, child in cars:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("OwnerId") == me.UserId and child:GetAttribute("Rental") ~= true then
			return child
		end
	end
	return nil
end

-- The item on the vehicle's copy; false when it does not fit this vehicle.
function StylePreview.paint(copy: Model, def: Config.CosmeticDef, carId: string?): boolean
	local car = if carId then Economy.findCar(carId) else nil
	if not Style.forVehicle(def.slot, car) then
		return false
	end
	if def.slot == "wrap" then
		local parts: { BasePart } = {}
		for _, d in copy:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("StylePaint") == true then
				table.insert(parts, d)
			end
		end
		StyleBuild.wrap(parts, def)
	elseif def.slot == "bikepaint" then
		StyleBuild.paintBike(copy, def)
	elseif def.slot == "decal" then
		local chassis = copy.PrimaryPart
		if not chassis or copy:GetAttribute("FleetArt") ~= true then
			return false
		end
		StyleBuild.decals(copy, chassis, def, true)
	end
	return true
end

-- The camera on `model` from its front-left, a little above: the whole of it, or (`head`) its head and shoulders.
local function frame(viewport: ViewportFrame, model: Model, facing: CFrame, focus: BasePart?)
	local cf, size = model:GetBoundingBox()
	local centre = cf.Position
	local radius = size.Magnitude / 2
	if focus then
		centre = focus.Position - Vector3.new(0, focus.Size.Y * 0.1, 0)
		radius = math.max(focus.Size.X, focus.Size.Y) * 1.55
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local direction = (facing.LookVector * 1.4 - facing.RightVector * 0.6 + Vector3.new(0, 0.45, 0)).Unit
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	camera.CFrame = CFrame.lookAt(centre + direction * distance, centre)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

function StylePreview.clear(holder: Instance)
	local old = holder:FindFirstChild(NAME)
	if old then
		old:Destroy()
	end
end

function StylePreview.show(holder: Instance, tab: string, def: Config.CosmeticDef?): (string, string?)
	StylePreview.clear(holder)
	local model: Model? = nil
	local kind = ""
	local note: string? = nil
	local facing = CFrame.new()
	local focus: BasePart? = nil
	if tab == "courier" then
		model = copyCharacter()
		kind = if model then "courier" else "mannequin"
		if not model then
			model = StylePreview.mannequin()
			if def and (def.slot == "vest" or def.slot == "bag") then
				note = "Your vest and bag show once you are in the world."
			end
		elseif def and def.slot == "bag" and not model:FindFirstChild("KitBagArt") then
			-- 6.23: no bag on you this game (bags are bought for each game): the colour shows on the bag you buy
			note = `No bag this game: the colour shows on the bag you buy at {Config.BagShop.Name}.`
		end
		local m = model :: Model
		still(m)
		if def then
			StylePreview.dress(m, def)
		end
		local torso = m:FindFirstChild("UpperTorso")
		if torso and torso:IsA("BasePart") then
			facing = torso.CFrame
		end
		local head = m:FindFirstChild("Head")
		if def and def.slot == "hat" and head and head:IsA("BasePart") then
			focus = head
		end
		local vestArt = m:FindFirstChild("KitVestArt")
		if def and def.slot == "vest" and (vestArt == nil or vestArt:FindFirstChild("VestL") == nil) then
			note = "The colour shows on the Courier Vest (Last Stop Supplies)."
		end
	else
		local live = liveVehicle()
		if not live then
			return "", "Bring your car or bike out (GARAGE) to see it on it."
		end
		local copy = live:Clone()
		if not copy then
			return "", "No preview here."
		end
		still(copy)
		local carId = live:GetAttribute("CarId")
		if def and not StylePreview.paint(copy, def, if type(carId) == "string" then carId else nil) then
			copy:Destroy()
			local car = if type(carId) == "string" then Economy.findCar(carId) else nil
			local bike = car ~= nil and car.bike == true
			return "", if def.slot == "bikepaint" then "For a bike or the E-Scooter: ride yours out to see it."
				elseif bike then "For a car, a van or a truck: bring yours out to see it." else "This one does not fit your vehicle."
		end
		copy:PivotTo(CFrame.new())
		model = copy
		kind = "vehicle"
	end
	local shownModel = model :: Model
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = NAME
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(160, 170, 180)
	viewport.LightColor = Color3.fromRGB(255, 242, 224)
	viewport.LightDirection = Vector3.new(-1, -1, -0.5)
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	shownModel.Parent = world
	frame(viewport, shownModel, facing, focus) -- (a vehicle's copy stands at the origin, its front to -Z)
	viewport.Parent = holder
	return kind, note
end

return StylePreview
