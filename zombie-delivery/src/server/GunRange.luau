--!strict
-- 6.12.14, Lead & Co.'s shooting range (the owner: "move the gun store out of the safe zone, to a shooting range: a
-- different, smaller shop; keep the props, but make the shop smaller, like the shop at a shooting range"): a fenced
-- compound on Downtown block (-2, 1), south-west of the park just outside the safe zone (Map.GunRange; the layout is
-- Config.GunRange, in the range's own frame: -Z the front with the gate, east to 4th Ave and the park). In it:
--   the range shop  a small timber cabin by the gate, its door to the street: the counter with the "guns" shop prompt
--                   (World's ShopPrompts: Ray stands behind it and the prompt moves onto him, server/ShopClerks.luau;
--                   Map.Shops.guns is its front), a gun rack on the back wall, a glass case of pistols, ammo boxes,
--                   the name board LEAD & CO. · RANGE on the roof's front edge and, behind it, the GUN STORE marquee and
--                   the giant cartridge from the old shop's roof at a smaller scale (server/ShopProps.luau, ShopArt
--                   "guns", Art.Mounts.guns: this cabin's frame)
--   the lanes       four lanes beside it: the shooting benches under a pavilion roof at the firing line, partitions
--                   between them, painted lane lines, a target on a stand in every lane at 25, 50 and 75 studs, the sand
--                   berm behind the farthest ones, a concrete wall between the lanes and the yard (NO ENTRY DOWNRANGE),
--                   the distance boards on it, two floodlight masts and the pavilion's strip light for the night, the
--                   red range flag
--   round it        a chain-link fence 10 studs in from the curb (the walk lines stay clear), the gate toward 4th Ave
--                   (its leaves open, wide enough for a car) with SHOOTING RANGE over it and its lamps, DANGER · LIVE
--                   FIRE signs on the outside, a gravel yard (a picnic table, two drums, the target store: a container
--                   in the back corner, sandbags by the pavilion)
-- The targets react (server-authoritative): server/Gun.luau hands every part a round hits to GunRange.shot; a target's
-- plate tips back on its hinge, stays down Config.GunRange.Down seconds and springs back up. Nothing else changes: no
-- money, no XP, the zombies' rules as everywhere outside the safe zone.
--
-- server/World.luau calls GunRange.build with its own helpers (no new top-level locals there: the -O0 register limit),
-- as it does for server/GearStall.luau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)

local GunRange = {}

export type Tools = {
	part: (parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?) -> Part,
	deco: (p: Part) -> Part,
	sign: (parent: Instance, text: string, size: Vector3, cframe: CFrame, color: Color3, background: Color3?, art: string?, artHeight: number?) -> (),
	prompt: (parent: BasePart, shop: string, action: string, object: string) -> (),
	nightLight: (item: Instance, lit: Color3?, dim: Color3?, dimMaterial: string?) -> (),
	sidewalk: (parent: Instance, cx: number, cz: number, color: Color3?) -> (),
}

local CHARCOAL = Color3.fromRGB(38, 43, 47)
local TIMBER = Color3.fromRGB(128, 100, 72)
local WOOD = Color3.fromRGB(120, 90, 60)
local STEEL = Color3.fromRGB(166, 172, 174)
local GUNMETAL = Color3.fromRGB(46, 49, 54)
local OLIVE = Color3.fromRGB(78, 92, 58)
local STENCIL = Color3.fromRGB(226, 196, 74)
local RED = Color3.fromRGB(176, 40, 34)
local CREAM = Color3.fromRGB(236, 230, 214)
local WIRE = Color3.fromRGB(110, 114, 118)
local WARM = Color3.fromRGB(255, 220, 150)
local LAMP = Color3.fromRGB(156, 146, 122)
local SAND = Color3.fromRGB(194, 166, 116)

-- The targets (their plates) and how each one stands and lies.
type Target = { up: CFrame, flat: CFrame, down: boolean }
local targets: { [Instance]: Target } = {}

-- A light inside a part (it goes on and off with the part's night glow).
local function lamp(item: Part, kind: string, range: number, brightness: number, color: Color3, angle: number?)
	if kind == "spot" then
		local spot = Instance.new("SpotLight")
		spot.Range = range
		spot.Brightness = brightness
		spot.Color = color
		spot.Shadows = false
		spot.Angle = angle or 60
		spot.Face = Enum.NormalId.Front
		spot.Parent = item
		return
	end
	local point = Instance.new("PointLight")
	point.Range = range
	point.Brightness = brightness
	point.Color = color
	point.Shadows = false
	point.Parent = item
end

-- A circle on a target's face (a Frame with a round corner), `size` of the plate's width, in the middle.
local function ring(parent: Instance, size: number, color: Color3, order: number)
	local disc = Instance.new("Frame")
	disc.Name = "Ring"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.42)
	disc.Size = UDim2.fromScale(size, size)
	disc.BackgroundColor3 = color
	disc.BorderSizePixel = 0
	disc.ZIndex = order
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = disc
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = disc
	disc.Parent = parent
end

-- A chain-link fence run from a to b on the walk (the frame's x, z): its posts but the one at its start (the run
-- before ends there) and, `open`, the one at its end (the gate's pillar stands there); the mesh is solid but lets the
-- rounds through (CanQuery off: you can shoot through it, as through real chain-link).
local function fence(folder: Instance, tools: Tools, f: CFrame, a: Vector3, b: Vector3, open: boolean?)
	local height = Config.GunRange.FenceHeight
	local length = (b - a).Magnitude
	local mesh = tools.part(folder, "ChainLink", Vector3.new(0.2, height, length), f * CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, height / 2, 0), WIRE, Enum.Material.Metal)
	mesh.Transparency = 0.65
	mesh.CanQuery = false
	local posts = math.max(1, math.ceil(length / 15))
	for n = 1, if open then posts - 1 else posts do
		local p = a + (b - a) * (n / posts)
		tools.part(folder, "FencePost", Vector3.new(0.4, height + 0.6, 0.4), f * CFrame.new(p.X, (height + 0.6) / 2, p.Z), WIRE, Enum.Material.Metal)
	end
	tools.deco(tools.part(folder, "FenceRail", Vector3.new(0.25, 0.25, length), f * CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, height, 0), WIRE, Enum.Material.Metal))
end

-- A warning board (white on red) on the fence's outside, its face toward `out` (a unit direction of the frame).
local function warning(folder: Instance, tools: Tools, f: CFrame, x: number, z: number, out: Vector3, text: string)
	local at = Vector3.new(x, 4, z) + out * 0.25
	tools.sign(folder, text, Vector3.new(9, 2, 0.2), f * CFrame.lookAt(at, at + out), Color3.fromRGB(255, 255, 255), RED)
end

-- The range shop: the cabin in its own frame `c` (its middle on the walk, -Z out of its door).
local function cabin(folder: Instance, tools: Tools, c: CFrame)
	local part, deco = tools.part, tools.deco
	local spec = Config.GunRange.Cabin
	local W, D, H = spec.Width, spec.Depth, spec.Height
	local front = -D / 2 + 0.3 -- the front wall's middle
	part(folder, "CabinFloor", Vector3.new(W, 0.3, D), c * CFrame.new(0, 0.15, 0), Color3.fromRGB(104, 84, 62), Enum.Material.WoodPlanks)
	part(folder, "CabinBack", Vector3.new(W, H, 0.6), c * CFrame.new(0, H / 2, D / 2 - 0.3), TIMBER, Enum.Material.WoodPlanks)
	for _, side in { -1, 1 } do
		part(folder, "CabinSide", Vector3.new(0.6, H, D - 1.2), c * CFrame.new(side * (W / 2 - 0.3), H / 2, 0), TIMBER, Enum.Material.WoodPlanks)
		-- The front either side of the door: under and over the window, a jamb each side of it.
		local wing = W / 2 - 2.5 -- from the door's edge to the corner
		local mid = side * (2.5 + wing / 2)
		part(folder, "CabinFront", Vector3.new(wing, 3.2, 0.6), c * CFrame.new(mid, 1.6, front), TIMBER, Enum.Material.WoodPlanks)
		part(folder, "CabinFront", Vector3.new(wing, H - 6.8, 0.6), c * CFrame.new(mid, (H + 6.8) / 2, front), TIMBER, Enum.Material.WoodPlanks)
		for _, edge in { -1, 1 } do
			part(folder, "CabinJamb", Vector3.new((wing - 5) / 2, 3.6, 0.6), c * CFrame.new(mid + edge * (2.5 + (wing - 5) / 4), 5, front), TIMBER, Enum.Material.WoodPlanks)
		end
		-- The window (it glows warm at night) behind three bars.
		local glass = deco(part(folder, "CabinWindow", Vector3.new(5, 3.6, 0.2), c * CFrame.new(mid, 5, front), Color3.fromRGB(40, 52, 60), Enum.Material.Glass))
		glass.Transparency = 0.35
		tools.nightLight(glass, WARM, glass.Color, "Glass")
		for n = -1, 1 do
			deco(part(folder, "WindowBar", Vector3.new(0.12, 3.6, 0.15), c * CFrame.new(mid + n * 1.6, 5, front - 0.4), STEEL, Enum.Material.Metal))
		end
		-- The corner posts (charcoal trim).
		for _, z in { -D / 2 + 0.4, D / 2 - 0.4 } do
			part(folder, "CabinCorner", Vector3.new(0.8, H, 0.8), c * CFrame.new(side * (W / 2 - 0.4), H / 2, z), CHARCOAL, Enum.Material.Metal)
		end
	end
	part(folder, "CabinLintel", Vector3.new(5, H - 7.5, 0.6), c * CFrame.new(0, (H + 7.5) / 2, front), TIMBER, Enum.Material.WoodPlanks)
	deco(part(folder, "CabinStripe", Vector3.new(W + 0.1, 0.35, 0.12), c * CFrame.new(0, 7.7, -D / 2 - 0.02), RED, Enum.Material.Metal))
	part(folder, "CabinRoof", Vector3.new(W + 1, 0.5, D + 1), c * CFrame.new(0, H + 0.25, 0), CHARCOAL, Enum.Material.Metal)
	part(folder, "RoofUnit", Vector3.new(3, 1.6, 3), c * CFrame.new(7.5, H + 0.5 + 0.8, 3.5), Color3.fromRGB(150, 152, 150), Enum.Material.Metal)
	-- The awning over the door and its lamp (warm at night).
	deco(part(folder, "DoorAwning", Vector3.new(7, 0.25, 2.2), c * CFrame.new(0, 8.1, -D / 2 - 1.1), RED, Enum.Material.Metal))
	local doorLamp = deco(part(folder, "DoorLamp", Vector3.new(1.4, 0.2, 0.6), c * CFrame.new(0, 7.9, -D / 2 - 0.8), LAMP, Enum.Material.Glass))
	lamp(doorLamp, "point", 16, 1.2, WARM)
	tools.nightLight(doorLamp, WARM, LAMP, "Glass")
	-- The name board on the roof's front edge (the contract look of every shop's board).
	tools.sign(folder, Config.GunRange.Board, Vector3.new(18, 2.6, 0.4), c * CFrame.new(0, H + 0.5 + 1.3, -D / 2 + 0.3), Color3.fromRGB(255, 200, 80), nil, "guns")
	-- Behind it, the GUN STORE marquee and the giant cartridge, smaller (ShopArt "guns", Art.Mounts.guns: this frame).
	local props = require(script.Parent.ShopProps)
	props.place(folder, "guns", c * props.mount("guns"))

	-- Inside: the counter across the cabin (the shop's prompt on it: Ray stands behind it, server/ShopClerks.luau).
	local counter = Config.GunRange.Counter
	local floor = 0.3
	local desk = part(folder, "Counter", Vector3.new(counter.Width, 3.2, counter.Deep), c * CFrame.new(0, floor + 1.6, counter.Z), WOOD, Enum.Material.Wood)
	tools.prompt(desk, "guns", "Shop", Map.Shops.guns.name)
	local face = counter.Z - counter.Deep / 2
	deco(part(folder, "CounterTop", Vector3.new(counter.Width + 0.4, 0.2, counter.Deep + 0.4), c * CFrame.new(0, floor + 3.3, counter.Z), STEEL, Enum.Material.Metal))
	deco(part(folder, "CounterFront", Vector3.new(counter.Width - 0.4, 2.4, 0.1), c * CFrame.new(0, floor + 1.6, face - 0.05), Color3.fromRGB(153, 49, 43), Enum.Material.Metal))
	deco(part(folder, "CounterStripe", Vector3.new(counter.Width - 0.4, 0.3, 0.12), c * CFrame.new(0, floor + 2.5, face - 0.1), CREAM, Enum.Material.Metal))
	-- On the counter: a glass case with two pistols, two boxes of rounds.
	local top = floor + 3.4
	local case = deco(part(folder, "DisplayCase", Vector3.new(4.6, 1.1, 1.8), c * CFrame.new(-4, top + 0.55, counter.Z), Color3.fromRGB(190, 214, 220), Enum.Material.Glass))
	case.Transparency = 0.55
	deco(part(folder, "CasePistol", Vector3.new(1.1, 0.3, 0.6), c * CFrame.new(-5, top + 0.2, counter.Z) * CFrame.Angles(0, math.rad(12), 0), GUNMETAL, Enum.Material.Metal))
	deco(part(folder, "CaseRevolver", Vector3.new(1.1, 0.3, 0.55), c * CFrame.new(-3, top + 0.2, counter.Z) * CFrame.Angles(0, math.rad(-10), 0), Color3.fromRGB(86, 90, 96), Enum.Material.Metal))
	for n = 0, 1 do
		local box = c * CFrame.new(3.4 + n * 1.2, top + 0.28, counter.Z + 0.1) * CFrame.Angles(0, math.rad(n * 15), 0)
		deco(part(folder, "AmmoBox", Vector3.new(1, 0.55, 0.65), box, OLIVE, Enum.Material.Metal))
		deco(part(folder, "AmmoBand", Vector3.new(1.04, 0.14, 0.69), box, STENCIL, Enum.Material.SmoothPlastic))
	end
	-- The gun rack on the back wall behind Ray: five long guns on a dark board, the lanes' price board over it.
	local wall = D / 2 - 0.6 -- the back wall's inside face
	deco(part(folder, "GunRack", Vector3.new(15, 4.4, 0.25), c * CFrame.new(0, 6.2, wall - 0.125), Color3.fromRGB(70, 52, 38), Enum.Material.WoodPlanks))
	for n = -2, 2 do
		local x = n * 2.8
		deco(part(folder, "RackGun", Vector3.new(0.32, 3.4, 0.32), c * CFrame.new(x, 6.6, wall - 0.45), GUNMETAL, Enum.Material.Metal))
		deco(part(folder, "RackStock", Vector3.new(0.5, 1.3, 0.3), c * CFrame.new(x, 4.65, wall - 0.45), Color3.fromRGB(122, 82, 48), Enum.Material.Wood))
	end
	tools.sign(folder, "THE LANES ARE FREE · ASK RAY", Vector3.new(10, 1.3, 0.2), c * CFrame.new(0, 9.1, wall - 0.1), Color3.fromRGB(255, 220, 120), CHARCOAL)
	-- Crates of ammunition stacked in the corner by the door.
	for n, at in { { W / 2 - 1.6, 0, -D / 2 + 1.6 }, { W / 2 - 1.6, 1, -D / 2 + 1.6 }, { W / 2 - 1.6, 0, -D / 2 + 3.1 } } do
		local crate = c * CFrame.new(at[1], floor + 0.55 + at[2] * 1.1, at[3]) * CFrame.Angles(0, math.rad(n * 7 - 7), 0)
		part(folder, "AmmoCrate", Vector3.new(2, 1.1, 1.3), crate, OLIVE, Enum.Material.Metal)
		deco(part(folder, "CrateStencil", Vector3.new(1.2, 0.3, 1.34), crate * CFrame.new(0, 0.1, 0), STENCIL, Enum.Material.SmoothPlastic))
	end
	-- The ceiling light (warm at night).
	local ceiling = deco(part(folder, "CeilingLight", Vector3.new(6, 0.2, 1), c * CFrame.new(0, H - 0.3, -1), LAMP, Enum.Material.Glass))
	lamp(ceiling, "point", 18, 1.2, WARM)
	tools.nightLight(ceiling, WARM, LAMP, "Glass")
end

-- One target in a lane: the stand (two legs and the hinge bar) and the plate on the hinge, its rings toward the
-- firing line; the plate is what a round hits (CanQuery on, not solid), registered for GunRange.shot.
local function target(folder: Instance, tools: Tools, f: CFrame, x: number, z: number, plate: { number })
	local part, deco = tools.part, tools.deco
	local w, h = plate[1], plate[2]
	for _, side in { -1, 1 } do
		deco(part(folder, "TargetLeg", Vector3.new(0.3, 2.4, 0.3), f * CFrame.new(x + side * (w / 2 - 0.3), 1.2, z + 0.2), Color3.fromRGB(110, 84, 58), Enum.Material.Wood))
	end
	deco(part(folder, "TargetHinge", Vector3.new(w + 0.4, 0.3, 0.3), f * CFrame.new(x, 2.4, z + 0.2), GUNMETAL, Enum.Material.Metal))
	local hinge = f * CFrame.new(x, 2.55, z)
	local up = hinge * CFrame.new(0, h / 2, 0)
	local p = part(folder, "RangeTarget", Vector3.new(w, h, 0.15), up, Color3.fromRGB(236, 232, 220), Enum.Material.SmoothPlastic)
	p.CanCollide = false
	p:SetAttribute("RangeTarget", true)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Rings"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.6
	gui.Parent = p
	ring(gui, 0.86, Color3.fromRGB(26, 26, 28), 1)
	ring(gui, 0.64, Color3.fromRGB(236, 232, 220), 2)
	ring(gui, 0.42, Color3.fromRGB(26, 26, 28), 3)
	ring(gui, 0.18, Color3.fromRGB(206, 40, 34), 4)
	-- Down: tipped back 82° on its hinge, away from the shooters (+Z).
	targets[p] = { up = up, flat = hinge * CFrame.Angles(math.rad(82), 0, 0) * CFrame.new(0, h / 2, 0), down = false }
end

-- Builds the range under `parent` (the district's folder) on Map.GunRange's block.
function GunRange.build(parent: Instance, tools: Tools)
	local R = Config.GunRange
	local part, deco = tools.part, tools.deco
	local folder = Instance.new("Folder")
	folder.Name = "LeadAndCoRange"
	folder.Parent = parent
	local block = Map.GunRange
	tools.sidewalk(folder, block.x, block.z, Color3.fromRGB(146, 144, 138))
	local origin = Vector3.new(block.x, Map.WalkTop, block.z)
	-- The range's frame: -Z out of the gate (east, to 4th Ave), +X to the right of someone looking out (south).
	local f = CFrame.lookAt(origin, origin + Vector3.new(block.fx, 0, block.fz))
	local half = R.Fence
	local lanes = R.Lanes
	local x0 = lanes.X[1] - lanes.Width / 2 -- the lanes' north edge (the wall to the yard)
	local x1 = lanes.X[#lanes.X] + lanes.Width / 2 -- their south edge
	local line = lanes.Line
	local roofFront = line + 2.6 -- the pavilion's roof ends over the lanes here
	local berm = R.Berm

	-- The ground: gravel in the yard, the pavilion's concrete pad, grass down the lanes, painted lines on it.
	deco(part(folder, "YardGravel", Vector3.new(x0 - 0.5 + half, 0.1, 2 * half), f * CFrame.new((x0 - 0.5 - half) / 2, 0.05, 0), Color3.fromRGB(132, 126, 114), Enum.Material.Pebble))
	deco(part(folder, "PavilionPad", Vector3.new(half - x0 + 0.5, 0.12, roofFront + half), f * CFrame.new((x0 - 0.5 + half) / 2, 0.06, (roofFront - half) / 2), Color3.fromRGB(150, 148, 142), Enum.Material.Concrete))
	deco(part(folder, "LaneGrass", Vector3.new(half - x0 + 0.5, 0.1, half - roofFront), f * CFrame.new((x0 - 0.5 + half) / 2, 0.05, (roofFront + half) / 2), Color3.fromRGB(88, 104, 62), Enum.Material.Grass))
	deco(part(folder, "FiringLine", Vector3.new(x1 - x0, 0.14, 0.4), f * CFrame.new((x0 + x1) / 2, 0.07, line + 0.2), Color3.fromRGB(226, 60, 50), Enum.Material.SmoothPlastic))
	for n = 2, #lanes.X do
		local x = (lanes.X[n - 1] + lanes.X[n]) / 2
		deco(part(folder, "LaneLine", Vector3.new(0.3, 0.13, berm.Z - roofFront), f * CFrame.new(x, 0.065, (berm.Z + roofFront) / 2), Color3.fromRGB(232, 232, 222), Enum.Material.SmoothPlastic))
	end

	-- The fence round it, the gate in its front.
	local gate = R.Gate
	local g0, g1 = gate.X - gate.Width / 2, gate.X + gate.Width / 2
	fence(folder, tools, f, Vector3.new(-half, 0, -half), Vector3.new(g0 - 1.4, 0, -half), true)
	fence(folder, tools, f, Vector3.new(g1 + 1.4, 0, -half), Vector3.new(half, 0, -half))
	fence(folder, tools, f, Vector3.new(half, 0, -half), Vector3.new(half, 0, half))
	fence(folder, tools, f, Vector3.new(half, 0, half), Vector3.new(-half, 0, half))
	fence(folder, tools, f, Vector3.new(-half, 0, half), Vector3.new(-half, 0, -half))
	for n, x in { g0 - 0.7, g1 + 0.7 } do
		part(folder, "GatePillar", Vector3.new(1.4, 9.5, 1.4), f * CFrame.new(x, 4.75, -half), Color3.fromRGB(150, 148, 142), Enum.Material.Concrete)
		-- the leaves, swung open into the yard along the gate's edges (decoration: nothing to bump)
		local side = if n == 1 then 1 else -1
		deco(part(folder, "GateLeaf", Vector3.new(0.15, 6.4, gate.Width / 2 - 0.4), f * CFrame.new(x + side * 0.9, 3.4, -half + gate.Width / 4 + 0.4), WIRE, Enum.Material.Metal)).Transparency = 0.5
		deco(part(folder, "GateLeafFrame", Vector3.new(0.3, 0.3, gate.Width / 2 - 0.4), f * CFrame.new(x + side * 0.9, 6.6, -half + gate.Width / 4 + 0.4), GUNMETAL, Enum.Material.Metal))
		local head = deco(part(folder, "GateLamp", Vector3.new(0.9, 0.5, 0.4), f * CFrame.new(x, 8.6, -half - 0.9), LAMP, Enum.Material.Glass))
		if n == 1 then
			lamp(head, "point", 20, 1.2, WARM)
		end
		tools.nightLight(head, WARM, LAMP, "Glass")
	end
	part(folder, "GateBeam", Vector3.new(gate.Width + 2.8, 1.2, 1), f * CFrame.new(gate.X, 10.1, -half), CHARCOAL, Enum.Material.Metal)
	tools.sign(folder, "SHOOTING RANGE · LIVE FIRE", Vector3.new(gate.Width - 1, 2, 0.3), f * CFrame.new(gate.X, 11.7, -half - 0.1), Color3.fromRGB(255, 210, 80), CHARCOAL)
	-- DANGER · LIVE FIRE on the outside: behind the berm, beside the lanes, on the street side of the pavilion.
	warning(folder, tools, f, (x0 + x1) / 2, half, Vector3.new(0, 0, 1), "DANGER · LIVE FIRE · KEEP OUT")
	warning(folder, tools, f, -22, half, Vector3.new(0, 0, 1), "DANGER · LIVE FIRE · KEEP OUT")
	warning(folder, tools, f, half, 0, Vector3.new(1, 0, 0), "DANGER · LIVE FIRE · KEEP OUT")
	warning(folder, tools, f, (x0 + x1) / 2, -half, Vector3.new(0, 0, -1), "DANGER · LIVE FIRE · KEEP OUT")
	warning(folder, tools, f, -half, 8, Vector3.new(-1, 0, 0), "RANGE ENTRANCE ON 4TH AVE")

	-- The range shop.
	cabin(folder, tools, f * CFrame.new(R.Cabin.X, 0, R.Cabin.Z))

	-- The pavilion over the firing line: posts on the lanes' edges, the roof, a red fascia toward the lanes.
	local back = -half + 0.6
	for _, x in { x0, (lanes.X[1] + lanes.X[2]) / 2, (lanes.X[2] + lanes.X[3]) / 2, (lanes.X[3] + lanes.X[4]) / 2, x1 } do
		for _, z in { back, roofFront - 0.4 } do
			part(folder, "PavilionPost", Vector3.new(0.5, 9, 0.5), f * CFrame.new(x, 4.5, z), CHARCOAL, Enum.Material.Metal)
		end
	end
	part(folder, "PavilionRoof", Vector3.new(x1 - x0 + 2, 0.5, roofFront - back + 1), f * CFrame.new((x0 + x1) / 2, 9.25, (roofFront + back) / 2), Color3.fromRGB(62, 74, 58), Enum.Material.Metal)
	deco(part(folder, "PavilionFascia", Vector3.new(x1 - x0 + 2, 0.8, 0.15), f * CFrame.new((x0 + x1) / 2, 8.8, roofFront + 0.6), RED, Enum.Material.Metal))
	local strip = deco(part(folder, "PavilionLight", Vector3.new(x1 - x0 - 4, 0.2, 0.5), f * CFrame.new((x0 + x1) / 2, 8.85, (roofFront + back) / 2), LAMP, Enum.Material.Glass))
	lamp(strip, "point", 26, 1.2, WARM)
	tools.nightLight(strip, WARM, LAMP, "Glass")
	tools.sign(folder, "EYE & EAR PROTECTION · CEASE FIRE ON THE RED LIGHT", Vector3.new(16, 1.1, 0.2), f * CFrame.new((x0 + x1) / 2, 8.05, roofFront + 0.3), Color3.fromRGB(255, 255, 255), Color3.fromRGB(40, 70, 130))
	-- A bench in every lane (its front edge on the firing line), a box of rounds on it, a partition between the lanes.
	for n, x in lanes.X do
		local bench = f * CFrame.new(x, 0, line - 1.2)
		part(folder, "ShootingBench", Vector3.new(5, 0.3, 2.4), bench * CFrame.new(0, 3, 0), WOOD, Enum.Material.WoodPlanks)
		for _, side in { -1, 1 } do
			part(folder, "BenchLeg", Vector3.new(0.3, 2.85, 2.2), bench * CFrame.new(side * 2.1, 1.425, 0), CHARCOAL, Enum.Material.Metal)
		end
		deco(part(folder, "BenchAmmo", Vector3.new(0.9, 0.5, 0.6), bench * CFrame.new(-1.5, 3.4, -0.2), OLIVE, Enum.Material.Metal))
		local divider = if n < #lanes.X then (x + lanes.X[n + 1]) / 2 else x1
		part(folder, "LaneDivider", Vector3.new(0.3, 6.5, roofFront - back - 1), f * CFrame.new(divider, 3.25, (roofFront + back) / 2 - 0.5), Color3.fromRGB(150, 146, 136), Enum.Material.Concrete)
		-- The targets at their distances (bigger farther out).
		for k, d in lanes.Targets do
			target(folder, tools, f, x, line + d, R.Plates[k])
		end
	end

	-- The wall between the yard and the lanes (bullets stop there), its boards both sides.
	part(folder, "RangeWall", Vector3.new(0.5, 4, berm.Z - roofFront), f * CFrame.new(x0 - 0.25, 2, (berm.Z + roofFront) / 2), Color3.fromRGB(150, 146, 136), Enum.Material.Concrete)
	for _, z in { -12, 22 } do
		tools.sign(folder, "NO ENTRY · DOWNRANGE", Vector3.new(7, 1.6, 0.2), f * CFrame.new(x0 - 0.6, 2.6, z) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(255, 210, 80), CHARCOAL)
	end
	for _, d in lanes.Targets do
		tools.sign(folder, tostring(d), Vector3.new(2.4, 1.6, 0.2), f * CFrame.new(x0 + 0.1, 2.8, line + d) * CFrame.Angles(0, -math.pi / 2, 0), Color3.fromRGB(30, 30, 32), CREAM)
	end

	-- The sand berm behind the farthest targets (its slope toward the shooters), sleepers along its top, red beacons.
	local bermWidth = x1 - x0 + 4
	local bank = Instance.new("WedgePart")
	bank.Name = "Berm"
	bank.Anchored = true
	bank.Size = Vector3.new(bermWidth, berm.Height, berm.Depth)
	bank.CFrame = f * CFrame.new((x0 + x1) / 2, berm.Height / 2, berm.Z + berm.Depth / 2)
	bank.Color = SAND
	bank.Material = Enum.Material.Sand
	bank.CanTouch = false
	bank.Parent = folder
	part(folder, "BermSleepers", Vector3.new(bermWidth, 1.2, 1.4), f * CFrame.new((x0 + x1) / 2, berm.Height + 0.6, berm.Z + berm.Depth - 0.7), Color3.fromRGB(72, 56, 42), Enum.Material.Wood)
	for _, x in { x0 - 1, x1 + 1 } do
		local beacon = deco(part(folder, "RedBeacon", Vector3.new(0.8, 0.8, 0.8), f * CFrame.new(x, berm.Height + 1.6, berm.Z + berm.Depth - 0.7), Color3.fromRGB(120, 40, 36), Enum.Material.Glass))
		beacon.Shape = Enum.PartType.Ball
		tools.nightLight(beacon, Color3.fromRGB(255, 60, 50), beacon.Color, "Glass")
	end

	-- The floodlight masts at the firing line's ends, their lamps down the lanes (a spotlight each at night).
	local aim = f * Vector3.new((x0 + x1) / 2, 0, line + 45)
	for _, x in { x0 - 1.6, x1 + 1.6 } do
		part(folder, "MastPole", Vector3.new(0.7, 16, 0.7), f * CFrame.new(x, 8, roofFront + 0.8), GUNMETAL, Enum.Material.Metal)
		local at = f * Vector3.new(x, 16.3, roofFront + 0.8)
		local head = deco(part(folder, "Floodlight", Vector3.new(2.2, 1.2, 0.8), CFrame.lookAt(at, aim), LAMP, Enum.Material.Glass))
		lamp(head, "spot", 90, 2.4, Color3.fromRGB(255, 244, 220), 55)
		tools.nightLight(head, Color3.fromRGB(255, 244, 220), LAMP, "Glass")
		deco(part(folder, "FloodlightHood", Vector3.new(2.4, 0.3, 1.2), CFrame.lookAt(at, aim) * CFrame.new(0, 0.7, 0.1), GUNMETAL, Enum.Material.Metal))
	end
	-- The red range flag on its pole by the pavilion (the range is hot), and its red light on the post.
	part(folder, "FlagPole", Vector3.new(0.3, 12, 0.3), f * CFrame.new(x0 - 4, 6, roofFront + 4), STEEL, Enum.Material.Metal)
	deco(part(folder, "RangeFlag", Vector3.new(0.1, 2.2, 3.4), f * CFrame.new(x0 - 4, 10.8, roofFront + 5.75), Color3.fromRGB(210, 36, 30), Enum.Material.Fabric))
	local redLight = deco(part(folder, "RedLight", Vector3.new(0.6, 0.6, 0.6), f * CFrame.new(x0 - 4, 12.3, roofFront + 4), Color3.fromRGB(120, 40, 36), Enum.Material.Glass))
	redLight.Shape = Enum.PartType.Ball
	tools.nightLight(redLight, Color3.fromRGB(255, 60, 50), redLight.Color, "Glass")

	-- The yard: a picnic table, two drums by the cabin, the target store (a container) in the back corner, sandbags
	-- along the wall's foot by the pavilion.
	local table0 = f * CFrame.new(-2, 0, 4)
	part(folder, "PicnicTable", Vector3.new(6, 0.3, 2.6), table0 * CFrame.new(0, 2.6, 0), WOOD, Enum.Material.WoodPlanks)
	for _, side in { -1, 1 } do
		part(folder, "PicnicSeat", Vector3.new(6, 0.25, 0.9), table0 * CFrame.new(0, 1.5, side * 2.2), WOOD, Enum.Material.WoodPlanks)
		part(folder, "PicnicLeg", Vector3.new(0.3, 2.45, 4.8), table0 * CFrame.new(side * 2.4, 1.225, 0), CHARCOAL, Enum.Material.Metal)
	end
	for n, z in { -14, -11.6 } do
		local drum = part(folder, "Drum", Vector3.new(3.4, 2.2, 2.2), f * CFrame.new(R.Cabin.X + R.Cabin.Width / 2 + 1.8, 1.7, z) * CFrame.Angles(0, 0, math.rad(90)), if n == 1 then Color3.fromRGB(60, 90, 150) else Color3.fromRGB(170, 50, 40), Enum.Material.Metal)
		drum.Shape = Enum.PartType.Cylinder
	end
	local store = f * CFrame.new(-half + 6, 0, half - 14)
	part(folder, "TargetStore", Vector3.new(8, 8.5, 18), store * CFrame.new(0, 4.25, 0), OLIVE, Enum.Material.CorrodedMetal)
	for n = -1, 1, 2 do
		deco(part(folder, "StoreRib", Vector3.new(0.2, 8.3, 0.4), store * CFrame.new(4.05, 4.25, n * 5), Color3.fromRGB(64, 76, 48), Enum.Material.Metal))
	end
	tools.sign(folder, "TARGETS · LEAD & CO.", Vector3.new(9, 1.4, 0.2), store * CFrame.new(4.15, 6.4, 0) * CFrame.Angles(0, -math.pi / 2, 0), STENCIL, OLIVE)
	for n = 0, 3 do
		deco(part(folder, "Sandbags", Vector3.new(1.6, 1, 3), f * CFrame.new(x0 - 1.4, 0.5 + (n % 2) * 0.9, roofFront + 8 + math.floor(n / 2) * 3.2) * CFrame.Angles(0, math.rad(n * 9 - 12), 0), Color3.fromRGB(150, 132, 92), Enum.Material.Fabric))
	end
end

-- 6.12.14: a round hit `part` (server/Gun.luau, the server's own ray): a range target tips back on its hinge, stays
-- down Config.GunRange.Down seconds (not hit again meanwhile) and springs back up. Anything else: nothing.
function GunRange.shot(part: Instance)
	local t = targets[part]
	if not t or t.down or not part:IsA("BasePart") then
		return
	end
	t.down = true
	local plate = part :: BasePart
	plate.CanQuery = false -- (lying down it lets the rounds through to the targets behind it)
	local TweenService = game:GetService("TweenService")
	TweenService:Create(plate, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = t.flat }):Play()
	task.delay(Config.GunRange.Down, function()
		if not plate.Parent then
			return
		end
		TweenService:Create(plate, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = t.up }):Play()
		task.wait(0.35)
		plate.CanQuery = true
		t.down = false
	end)
end

-- 6.12.14: how many targets stand on the lanes (tests, the admin's checks).
function GunRange.count(): number
	local n = 0
	for _ in targets do
		n += 1
	end
	return n
end

return GunRange
