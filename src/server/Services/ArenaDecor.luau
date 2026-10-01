--!strict
-- The look of an arena: its entrance arch, fences, torches, banners, training props and the ring
-- marks on the fight platform. Every map with a designed look has a data module in DecorData/
-- (generated from the design's .rbxmx by tools/decor_from_rbxmx.py) and a placement list here, which
-- says where the copies of every prop stand. All coordinates are relative to the plot (`origin` is the
-- top of the plot's floor, +z points from your squad toward the enemies).
--
-- The decor never blocks the game: it has no click / query collision (soldiers behind it can still
-- be picked) and stays at the sides of the fight area (x beyond +-22) and at the gate.

local Data: { [string]: any } = {
	TrainingArena1 = require(script.Parent.DecorData.TrainingArena1),
}

type Placement = { name: string, x: number, z: number, rotation: number? } -- rotation in degrees around Y

-- Where the props of each design stand.
local PLACEMENTS: { [string]: { Placement } } = {
	TrainingArena1 = {
		-- The gate: the arch over the road, a wall of fences on both sides of it, torches and banners.
		{ name = "EntranceArch", x = 0, z = 30 },
		{ name = "WoodenFence", x = -15, z = 30.4 },
		{ name = "WoodenFence", x = 15, z = 30.4 },
		{ name = "WoodenFence", x = -26, z = 30.4 },
		{ name = "WoodenFence", x = 26, z = 30.4 },
		{ name = "Torch", x = -10, z = 27 },
		{ name = "Torch", x = 10, z = 27 },
		{ name = "BannerFlag", x = -19, z = 33 },
		{ name = "BannerFlag", x = 19, z = 33 },
		-- Left side: the weapon rack near the squad, torches along the platform, the corner with supplies.
		{ name = "WeaponRack", x = -27, z = 44 },
		{ name = "Torch", x = -28, z = 78 },
		{ name = "TrainingDummy", x = -26, z = 128 },
		{ name = "TrainingDummy", x = -21, z = 128 },
		{ name = "TrainingDummy", x = -16, z = 128 },
		{ name = "Barrel", x = -27, z = 134 },
		{ name = "Barrel", x = -24.5, z = 135 },
		{ name = "Crate", x = -27, z = 137 },
		{ name = "Crate", x = -23.5, z = 137 },
		-- Right side: sandbag cover, torches, hay and the archery targets at the back.
		{ name = "SandbagWall", x = 28.6, z = 66 },
		{ name = "SandbagWall", x = 30, z = 76 },
		{ name = "Torch", x = 28, z = 78 },
		{ name = "HayBale", x = 27.5, z = 128 },
		{ name = "HayBale", x = 22, z = 132 },
		{ name = "ArcheryTarget", x = 14, z = 137 },
		{ name = "ArcheryTarget", x = 19, z = 137 },
		{ name = "ArcheryTarget", x = 24, z = 137 },
	},
}

local ArenaDecor = {}

local RING_SCALE = 2.0 -- the big arena gets bigger ring marks than the design's

-- The placements above were laid out for the original arena (a plot 64 wide, the arena z = 30 … 140). The
-- plot is 84 wide and 160 long now: x is stretched to the new width, the things along the fight platform
-- (z 34 … 117) are spread over the longer platform and the far end (the dummies, hay, targets) moves back.
local OLD_HALF, NEW_HALF = 32, 42
local OLD_FAR, NEW_FAR = 118, 136 -- where the far end (the enemy area) began / begins
local function stretched(placement: Placement): (number, number)
	local x = placement.x * NEW_HALF / OLD_HALF
	local z = placement.z
	if z >= OLD_FAR then
		z += NEW_FAR - OLD_FAR
	elseif z > 34 then
		z = 34 + (z - 34) * (NEW_FAR - 1 - 34) / (OLD_FAR - 1 - 34)
	end
	return x, z
end

local function buildPart(parent: Instance, data: any, base: CFrame): Part
	local p = Instance.new("Part")
	p.Name = data.name
	p.Anchored = true
	p.CanQuery = false -- never in the way of picking soldiers
	p.CanCollide = data.collide ~= false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = data.size
	p.CFrame = base * data.cf
	p.Color = data.color
	p.Material = Enum.Material:FromValue(data.material) or Enum.Material.SmoothPlastic
	if data.shape then
		p.Shape = Enum.PartType:FromValue(data.shape) or Enum.PartType.Block
	end
	if data.transparency then
		p.Transparency = data.transparency
	end
	if data.reflectance then
		p.Reflectance = data.reflectance
	end
	p.Parent = parent

	if data.light then
		local light = Instance.new("PointLight")
		light.Color = data.light.color
		light.Brightness = data.light.brightness
		light.Range = data.light.range
		light.Parent = p
	end
	if data.guis then
		for _, gui in data.guis do
			local surface = Instance.new("SurfaceGui")
			surface.Face = Enum.NormalId:FromValue(gui.face) or Enum.NormalId.Front
			surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			surface.PixelsPerStud = 50
			surface.Parent = p
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.TextScaled = true
			text.Text = gui.text
			text.TextColor3 = gui.color
			text.TextStrokeColor3 = gui.stroke
			text.TextStrokeTransparency = 0
			text.FontFace = Font.new(gui.font)
			text.Parent = surface
		end
	end
	return p
end

-- Builds the decor of the design `designId` into `folder`. `ring` = where the ring marks go: the
-- middle of the fight platform's top (world position).
function ArenaDecor.build(designId: string, folder: Instance, origin: Vector3, ring: Vector3?)
	local data = Data[designId]
	local placements = PLACEMENTS[designId]
	if not data or not placements then
		return
	end

	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = folder

	for i, placement in placements do
		local parts = data.models[placement.name]
		if parts then
			local model = Instance.new("Model")
			model.Name = string.format("%s%d", placement.name, i)
			local px, pz = stretched(placement)
			local base = CFrame.new(origin + Vector3.new(px, 0, pz)) * CFrame.Angles(0, math.rad(placement.rotation or 0), 0)
			for _, part in parts do
				buildPart(model, part, base)
			end
			model.Parent = decor
		end
	end

	-- The round marks in the middle of the fight platform.
	if ring then
		for i, mark in data.rings do
			local disc = Instance.new("Part")
			disc.Name = "Ring" .. i
			disc.Shape = Enum.PartType.Cylinder
			disc.Anchored = true
			disc.CanCollide = false
			disc.CanQuery = false
			disc.CanTouch = false
			disc.CastShadow = false
			disc.Size = Vector3.new(mark.thickness, mark.diameter * RING_SCALE, mark.diameter * RING_SCALE)
			disc.CFrame = CFrame.new(ring + Vector3.new(0, mark.thickness / 2 + 0.01 * i, 0)) * CFrame.Angles(0, 0, math.rad(90))
			disc.Color = mark.color
			disc.Material = Enum.Material:FromValue(mark.material) or Enum.Material.Sand
			disc.Parent = decor
		end
	end
end

return ArenaDecor
