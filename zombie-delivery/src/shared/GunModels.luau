--!strict
-- The guns you see in the hands: the players' (server/Main.server.luau) and the bandits' (server/Zombies.luau).
-- Every gun is built from a few parts in "gun space": X right, Y up, -Z forward (where the barrel points), the hand
-- at the origin around the grip. A gun's "Muzzle" attachment sits at the end of its barrel (the flash and the
-- tracers start there). The parts never collide, are never hit by bullets and weigh nothing.

local GunModels = {}

type Piece = {
	size: Vector3,
	at: Vector3,
	color: Color3,
	material: Enum.Material,
	tube: boolean?, -- a cylinder along the barrel (Z)
	ball: boolean?,
	tilt: number?, -- degrees about X (a grip raked back, a stock dropping)
}

local BLACK = Color3.fromRGB(28, 28, 32)
local GUNMETAL = Color3.fromRGB(58, 60, 66)
local STEEL = Color3.fromRGB(120, 122, 128)
local WOOD = Color3.fromRGB(112, 72, 42)
local DARK_WOOD = Color3.fromRGB(78, 50, 32)
local OLIVE = Color3.fromRGB(72, 88, 52)
local POLYMER = Color3.fromRGB(40, 40, 44)
local METAL = Enum.Material.Metal
local PLASTIC = Enum.Material.SmoothPlastic

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local LOOKS: { [string]: { pieces: { Piece }, muzzle: Vector3 } } = {
	pistol = {
		muzzle = v(0, 0.24, -1.12),
		pieces = {
			{ size = v(0.26, 0.24, 1.3), at = v(0, 0.24, -0.45), color = GUNMETAL, material = METAL }, -- slide
			{ size = v(0.22, 0.16, 1.05), at = v(0, 0.06, -0.38), color = POLYMER, material = PLASTIC }, -- frame
			{ size = v(0.24, 0.62, 0.34), at = v(0, -0.22, 0.08), color = POLYMER, material = PLASTIC, tilt = 14 }, -- grip
			{ size = v(0.06, 0.16, 0.34), at = v(0, -0.06, -0.18), color = BLACK, material = PLASTIC }, -- trigger guard
			{ size = v(0.1, 0.1, 0.12), at = v(0, 0.24, -1.08), color = BLACK, material = METAL, tube = true }, -- muzzle
			{ size = v(0.05, 0.06, 0.06), at = v(0, 0.39, -1.0), color = STEEL, material = METAL }, -- front sight
			{ size = v(0.16, 0.06, 0.06), at = v(0, 0.39, 0.12), color = BLACK, material = METAL }, -- rear sight
		},
	},
	smg = {
		muzzle = v(0, 0.24, -1.95),
		pieces = {
			{ size = v(0.3, 0.34, 1.5), at = v(0, 0.22, -0.45), color = POLYMER, material = PLASTIC }, -- receiver
			{ size = v(0.14, 0.14, 0.75), at = v(0, 0.24, -1.55), color = GUNMETAL, material = METAL, tube = true }, -- barrel
			{ size = v(0.2, 0.2, 0.3), at = v(0, 0.24, -1.8), color = BLACK, material = METAL, tube = true }, -- muzzle
			{ size = v(0.22, 0.55, 0.28), at = v(0, -0.2, 0.08), color = POLYMER, material = PLASTIC, tilt = 12 }, -- grip
			{ size = v(0.18, 0.8, 0.26), at = v(0, -0.35, -0.62), color = BLACK, material = METAL, tilt = -8 }, -- magazine
			{ size = v(0.1, 0.22, 0.8), at = v(0, 0.12, 0.72), color = BLACK, material = METAL }, -- folding stock
			{ size = v(0.12, 0.14, 0.32), at = v(0, 0.44, -0.3), color = BLACK, material = METAL }, -- sight
			{ size = v(0.16, 0.16, 0.24), at = v(0, 0.44, -0.3), color = Color3.fromRGB(200, 40, 40), material = Enum.Material.Neon, tube = true }, -- red dot
		},
	},
	shotgun = {
		muzzle = v(0, 0.32, -2.55),
		pieces = {
			{ size = v(0.2, 0.2, 2.5), at = v(0, 0.32, -1.3), color = GUNMETAL, material = METAL, tube = true }, -- barrel
			{ size = v(0.17, 0.17, 1.9), at = v(0, 0.13, -1.05), color = BLACK, material = METAL, tube = true }, -- magazine tube
			{ size = v(0.3, 0.28, 0.75), at = v(0, 0.13, -1.1), color = WOOD, material = Enum.Material.Wood }, -- pump
			{ size = v(0.3, 0.42, 0.9), at = v(0, 0.24, -0.05), color = GUNMETAL, material = METAL }, -- receiver
			{ size = v(0.24, 0.5, 0.28), at = v(0, -0.16, 0.2), color = WOOD, material = Enum.Material.Wood, tilt = 18 }, -- grip
			{ size = v(0.28, 0.42, 1.2), at = v(0, 0.02, 0.95), color = WOOD, material = Enum.Material.Wood, tilt = -6 }, -- stock
			{ size = v(0.06, 0.06, 0.08), at = v(0, 0.45, -2.45), color = STEEL, material = METAL }, -- bead sight
		},
	},
	rifle = {
		muzzle = v(0, 0.32, -2.75),
		pieces = {
			{ size = v(0.14, 0.14, 2.1), at = v(0, 0.32, -1.65), color = GUNMETAL, material = METAL, tube = true }, -- barrel
			{ size = v(0.28, 0.3, 1.9), at = v(0, 0.14, -0.7), color = DARK_WOOD, material = Enum.Material.Wood }, -- forend
			{ size = v(0.24, 0.26, 0.8), at = v(0, 0.33, -0.05), color = GUNMETAL, material = METAL }, -- receiver
			{ size = v(0.3, 0.06, 0.06), at = v(0.19, 0.33, 0.2), color = STEEL, material = METAL }, -- bolt handle
			{ size = v(0.22, 0.22, 1.2), at = v(0, 0.66, -0.15), color = BLACK, material = METAL, tube = true }, -- scope
			{ size = v(0.3, 0.3, 0.2), at = v(0, 0.66, -0.78), color = BLACK, material = METAL, tube = true }, -- scope front
			{ size = v(0.1, 0.18, 0.1), at = v(0, 0.48, -0.45), color = BLACK, material = METAL }, -- mount
			{ size = v(0.1, 0.18, 0.1), at = v(0, 0.48, 0.15), color = BLACK, material = METAL }, -- mount
			{ size = v(0.24, 0.45, 0.28), at = v(0, -0.12, 0.3), color = DARK_WOOD, material = Enum.Material.Wood, tilt = 16 }, -- grip
			{ size = v(0.28, 0.46, 1.3), at = v(0, 0.05, 1.05), color = DARK_WOOD, material = Enum.Material.Wood, tilt = -5 }, -- stock
		},
	},
	minigun = {
		muzzle = v(0, 0.3, -2.95),
		pieces = {
			{ size = v(0.66, 0.66, 0.95), at = v(0, 0.3, 0.05), color = GUNMETAL, material = Enum.Material.DiamondPlate, tube = true }, -- motor
			{ size = v(0.62, 0.62, 0.14), at = v(0, 0.3, -1.4), color = BLACK, material = METAL, tube = true }, -- clamp
			{ size = v(0.62, 0.62, 0.14), at = v(0, 0.3, -2.6), color = BLACK, material = METAL, tube = true }, -- front clamp
			{ size = v(0.12, 0.12, 0.85), at = v(0, 0.76, 0.05), color = BLACK, material = METAL }, -- carry handle
			{ size = v(0.12, 0.3, 0.12), at = v(0, 0.62, -0.3), color = BLACK, material = METAL }, -- handle post
			{ size = v(0.12, 0.3, 0.12), at = v(0, 0.62, 0.4), color = BLACK, material = METAL }, -- handle post
			{ size = v(0.24, 0.55, 0.3), at = v(0, -0.18, 0.3), color = POLYMER, material = PLASTIC, tilt = 10 }, -- grip
			{ size = v(0.5, 0.6, 0.62), at = v(-0.5, -0.02, 0.1), color = OLIVE, material = METAL }, -- ammo box
			{ size = v(0.14, 0.2, 0.5), at = v(-0.26, 0.2, 0.0), color = Color3.fromRGB(190, 150, 60), material = METAL }, -- belt
		},
	},
	launcher = {
		muzzle = v(0, 0.36, -2.45),
		pieces = {
			{ size = v(0.55, 0.55, 3.3), at = v(0, 0.36, -0.7), color = OLIVE, material = METAL, tube = true }, -- tube
			{ size = v(0.68, 0.68, 0.32), at = v(0, 0.36, -2.25), color = BLACK, material = METAL, tube = true }, -- front bell
			{ size = v(0.64, 0.64, 0.28), at = v(0, 0.36, 0.95), color = BLACK, material = METAL, tube = true }, -- rear bell
			{ size = v(0.36, 0.36, 0.3), at = v(0, 0.36, -2.48), color = Color3.fromRGB(90, 70, 40), material = METAL, tube = true }, -- warhead
			{ size = v(0.36, 0.36, 0.36), at = v(0, 0.36, -2.64), color = Color3.fromRGB(90, 70, 40), material = METAL, ball = true }, -- warhead tip
			{ size = v(0.22, 0.55, 0.28), at = v(0, -0.12, 0.05), color = BLACK, material = PLASTIC, tilt = 10 }, -- grip
			{ size = v(0.2, 0.45, 0.25), at = v(0, -0.06, -1.0), color = BLACK, material = PLASTIC }, -- front grip
			{ size = v(0.08, 0.36, 0.3), at = v(-0.34, 0.62, -0.5), color = BLACK, material = METAL }, -- sight
		},
	},
}

function GunModels.has(weapon: string): boolean
	return LOOKS[weapon] ~= nil
end

-- A gun model welded to `hand`, its grip at `grip` (a CFrame in gun space: -Z forward, Y up), `scale` × the size.
function GunModels.build(weapon: string, hand: BasePart, grip: CFrame, scale: number?): Model
	local look = LOOKS[weapon] or LOOKS.pistol
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "HandGun"
	model:SetAttribute("Weapon", weapon)
	local first: Part? = nil
	for _, piece in look.pieces do
		local p = Instance.new("Part")
		p.Name = "GunPart"
		p.Color = piece.color
		p.Material = piece.material
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		local offset = CFrame.new(piece.at * s) * CFrame.Angles(math.rad(piece.tilt or 0), 0, 0)
		if piece.tube then
			-- A cylinder's axis is its X: turned to lie along Z.
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(piece.size.Z, piece.size.Y, piece.size.X) * s
			offset *= CFrame.Angles(0, math.rad(90), 0)
		elseif piece.ball then
			p.Shape = Enum.PartType.Ball
			p.Size = piece.size * s
		else
			p.Size = piece.size * s
		end
		p.CFrame = grip * offset
		local w = Instance.new("WeldConstraint")
		w.Part0 = hand
		w.Part1 = p
		w.Parent = p
		p.Parent = model
		if not first then
			first = p
		end
	end
	if first then
		local muzzle = Instance.new("Attachment")
		muzzle.Name = "Muzzle"
		muzzle.WorldCFrame = grip * CFrame.new(look.muzzle * s)
		muzzle.Parent = first
	end
	return model
end

-- Where the grip goes on a hand: an R15 hand is small (the grip is just under it), an R6 arm is 2 studs long (the
-- grip is at its end). The gun points along the arm: down at your side, forward when the arm comes up to aim.
function GunModels.gripOn(hand: BasePart): CFrame
	local below = if hand.Name == "Right Arm" then hand.Size.Y / 2 + 0.1 else hand.Size.Y / 2 + 0.15
	return hand.CFrame * CFrame.new(0, -below, 0) * CFrame.Angles(math.rad(-90), 0, 0)
end

return GunModels
