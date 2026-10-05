--!strict
-- What a character holds: the WEAPON (right hand) and the OFFHAND item (left hand), built as separate models
-- "Weapon" / "Offhand" inside the character, fixed to the hand by a Motor6D grip (like Roblox tools), so
--   · the hand's animations move the item with it (the staff swings when the mage casts),
--   · the item can be swapped later (Weapons.equip with other parts) without touching the body,
--   · a design's grip is kept exactly: the parts come with their CFrame relative to the hand.
-- A part entry has the evolution data shape: { limb, relativeCFrame, size, color, material, extra? } with
-- extra = { shape, wedge, t, r, light = { r, g, b, range, brightness } }.

local Weapons = {}

local MATERIAL: { [number]: Enum.Material } = {}
for _, item in Enum.Material:GetEnumItems() do
	MATERIAL[item.Value] = item
end
local PART_TYPE: { [number]: Enum.PartType } = {}
for _, item in Enum.PartType:GetEnumItems() do
	PART_TYPE[item.Value] = item
end

local LIGHT_RANGE = 0.6 -- lights are kept soft (see SoldierRig's AURA_*)
local LIGHT_BRIGHTNESS = 0.45

local function scaledCF(cf: CFrame, k: number): CFrame
	return CFrame.new(cf.Position * k) * cf.Rotation
end

local function makePart(entry: { any }, k: number, static: boolean): BasePart
	local extra = entry[6]
	local p: BasePart
	if extra and extra.wedge then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		part.Shape = (extra and extra.shape and PART_TYPE[extra.shape]) or Enum.PartType.Block
		p = part
	end
	p.Size = entry[3] * k
	p.Color = entry[4]
	p.Material = MATERIAL[entry[5]] or Enum.Material.SmoothPlastic
	p.Transparency = (extra and extra.t) or 0
	p.Reflectance = (extra and extra.r) or 0
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.Anchored = static
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra and extra.light and not static then
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(extra.light[1], extra.light[2], extra.light[3])
		l.Range = extra.light[4] * k * LIGHT_RANGE
		l.Brightness = extra.light[5] * LIGHT_BRIGHTNESS
		l.Shadows = false
		l.Parent = p
	end
	return p
end

-- The slot name of a hand: "Weapon" for the right hand, "Offhand" for the left.
local function slotName(handName: string): string
	return if handName == "LeftHand" then "Offhand" else "Weapon"
end

-- Removes what the hand holds.
function Weapons.strip(character: Model, handName: string)
	local old = character:FindFirstChild(slotName(handName))
	if old then
		old:Destroy()
	end
end

-- Gives the character the item made of `parts` (relative to the hand, at scale 1) in `handName`, at scale `k`.
-- `static` = a statue (UI previews): the parts are anchored where they are, no grip. Returns the item model
-- (nil when there is nothing to hold or no such hand).
function Weapons.equip(character: Model, handName: string, parts: { { any } }?, k: number, static: boolean): Model?
	Weapons.strip(character, handName)
	local hand = character:FindFirstChild(handName)
	if not parts or #parts == 0 or not hand or not hand:IsA("BasePart") then
		return nil
	end
	local item = Instance.new("Model")
	item.Name = slotName(handName)

	-- The handle: an invisible part at the hand itself; every piece is welded to it and it is gripped by the hand.
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.CastShadow = false
	handle.Anchored = static
	handle.CFrame = hand.CFrame
	handle.Parent = item
	item.PrimaryPart = handle

	for _, entry in parts do
		local p = makePart(entry, k, static)
		p.Name = "Piece"
		p.CFrame = hand.CFrame * scaledCF(entry[2], k)
		p.Parent = item
		if not static then
			local w = Instance.new("WeldConstraint")
			w.Part0 = handle
			w.Part1 = p
			w.Parent = p
		end
	end
	if not static then
		-- The grip (a Motor6D, as Roblox tools use): the item follows the hand through every animation.
		local grip = Instance.new("Motor6D")
		grip.Name = if handName == "LeftHand" then "LeftGrip" else "RightGrip"
		grip.Part0 = hand
		grip.Part1 = handle
		grip.C0 = CFrame.new()
		grip.C1 = CFrame.new()
		grip.Parent = hand
	end
	item.Parent = character
	return item
end

return Weapons
