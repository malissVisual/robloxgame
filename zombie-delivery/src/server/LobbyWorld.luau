--!strict
-- 9.7 RUNS, the lobby (design/lobby/plan.py; shared/SandboxMap.luau Lobby; the owner: "shrink the map and put things
-- quite close together, so that it's one little lobby"): builds the lobby's own dress into workspace.Sandbox (server/
-- SandboxWorld.luau calls it once, after its ground: the meadow under the lobby, the plots' concrete pads; the
-- warehouses are server/Warehouse.luau's, the TOP MOVERS board server/SandboxLeaders.luau's, the Auction House
-- SandboxWorld's own while Config.Auction.On). Everything anchored, in the Persistent model "Lobby" (small: every client
-- always has it, so coming back from a run never shows it streaming in):
--   Plaza      the paved square in the middle (SandboxMap.Lobby.plaza: its top flush with the meadow, the meadow's hole)
--              and the fountain on it (a basin, its water, the spout)
--   Hedge      the hedge round the lobby, Lobby.hedge in from its bounds (solid), and the invisible walls on the bounds
--   Lamps      the plaza's lamps (decoration: a fixed afternoon, their heads dim)
--   Trees      the lobby's trees (VillageLooks' trees, server/VillageWorld.luau's parts)
--   Dispatch   the ZDC dispatch kiosk (server/MoveSites.luau's kiosk art at Lobby.dispatch, its corkboard "Board" with
--              the attribute RunDispatch: server/Runs.luau hangs its "How runs work" prompt there)
--   Portals    a Model "Portal_<house>" per place to empty (Lobby.portals; attribute RunPortal = its house's id): two
--              gate posts and a lintel in its house's colours (Config.Runs.Portal.Styles), a small facade behind the
--              gate in the house's look (its walls, a dark door, two windows, a gable and a detail of its own: hay
--              bales, a boat, a mailbox, antlers and a log pile, a mill wheel, an apple tree and a beehive), the sign
--              over the gate (SurfaceGui "Words": Title, its name; Status, server/Runs.luau's line: free, a countdown,
--              IN USE) and the glowing pad in front of it ("RunPad": attribute RunPad = its house's id, Neon, no
--              collision, its colour server/Runs.luau's by the pad's state) on a dark rim
--   PaintShop  9.7 the PAINT shop's booth (Lobby.shops.paint: its counter's prompt "Paint your truck", attribute
--              PaintShop: server/VanPaint.luau opens its window there, no van needed) and its sign
--
--   LobbyWorld.build(world)    builds it into workspace.Sandbox's folder `world` (before it is parented); returns
--                              the Lobby model

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SandboxMap = require(Shared.SandboxMap)
local SandboxScenery = require(Shared.SandboxScenery)
local VillageLooks = require(Shared.VillageLooks)

local MoveSites = require(script.Parent.MoveSites)
local VillageWorld = require(script.Parent.VillageWorld)

local LobbyWorld = {}

local L = SandboxMap.Lobby
local R = Config.Runs
local P = R.Portal
local CREAM = Color3.fromRGB(250, 244, 228)
local DARK = Color3.fromRGB(40, 30, 24)
local PLAZA = Color3.fromRGB(196, 188, 172)
local STONE = Color3.fromRGB(150, 146, 140)
local WATER = Color3.fromRGB(76, 140, 190)
local POLE = Color3.fromRGB(50, 50, 54)
local HEDGE = Color3.fromRGB(52, 96, 44)

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, solid: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	-- (a shadow only from a bigger part: SandboxScenery.Shadow's rule)
	local long = math.max(size.X, size.Y, size.Z)
	local wide = size.X + size.Y + size.Z - long - math.min(size.X, size.Y, size.Z)
	p.CastShadow = solid == true and long >= SandboxScenery.Shadow.Long and wide >= SandboxScenery.Shadow.Wide
	if not solid then
		p.CanCollide = false
		p.CanQuery = false
	end
	p.Parent = parent
	return p
end

local function cylinder(parent: Instance, name: string, length: number, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material, solid: boolean?): Part
	-- (a cylinder lies along its X: `cframe` turns it)
	local p = block(parent, name, Vector3.new(length, diameter, diameter), cframe, color, material, solid)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Words on a part's face: a SurfaceGui "Words" with one label per line (name, its box as scales, its colour, its size).
local function words(part: BasePart, face: Enum.NormalId, lines: { { name: string, text: string, box: { number }, color: Color3, bold: boolean? } })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Words"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.3
	gui.MaxDistance = P.SignRange
	for _, line in lines do
		local label = Instance.new("TextLabel")
		label.Name = line.name
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(line.box[1], line.box[2])
		label.Size = UDim2.fromScale(line.box[3], line.box[4])
		label.Text = line.text
		label.TextScaled = true
		label.Font = if line.bold then Enum.Font.GothamBlack else Enum.Font.GothamBold
		label.TextColor3 = line.color
		label.Parent = gui
	end
	gui.Parent = part
end

-- ── The plaza, the hedge, the fountain, the lamps, the trees ───────────────

local function plaza(model: Model)
	local r = L.plaza
	local top = SandboxMap.GroundTop
	local slab = block(model, "Plaza", Vector3.new(r.x1 - r.x0, 2, r.z1 - r.z0), CFrame.new((r.x0 + r.x1) / 2, top - 1, (r.z0 + r.z1) / 2), PLAZA, Enum.Material.Cobblestone, true)
	slab.CastShadow = false
	-- its kerb: a pale band round it
	local band = 1.2
	for _, e in { { r.x0, r.x1, r.z0, r.z0 + band }, { r.x0, r.x1, r.z1 - band, r.z1 }, { r.x0, r.x0 + band, r.z0, r.z1 }, { r.x1 - band, r.x1, r.z0, r.z1 } } do
		block(model, "PlazaKerb", Vector3.new(e[2] - e[1], 0.1, e[4] - e[3]), CFrame.new((e[1] + e[2]) / 2, top + 0.05, (e[3] + e[4]) / 2), Color3.fromRGB(226, 220, 206), Enum.Material.Concrete)
	end
	local f = L.fountain
	cylinder(model, "FountainBasin", 1.6, 2 * f.r, CFrame.new(f.x, top + 0.8, f.z) * CFrame.Angles(0, 0, math.rad(90)), STONE, Enum.Material.Concrete, true)
	cylinder(model, "FountainWater", 0.2, 2 * f.r - 2, CFrame.new(f.x, top + 1.55, f.z) * CFrame.Angles(0, 0, math.rad(90)), WATER, Enum.Material.Glass).Transparency = 0.15
	cylinder(model, "FountainSpout", 5, 1.6, CFrame.new(f.x, top + 2.5, f.z) * CFrame.Angles(0, 0, math.rad(90)), STONE, Enum.Material.Concrete, true)
	cylinder(model, "FountainBowl", 0.6, 4.4, CFrame.new(f.x, top + 5, f.z) * CFrame.Angles(0, 0, math.rad(90)), STONE, Enum.Material.Concrete)
end

local function hedge(model: Model)
	local b, h = L.bounds, L.hedge
	local tall, wide = 4.5, 2.6
	local x0, x1, z0, z1 = b.x0 + h, b.x1 - h, b.z0 + h, b.z1 - h
	for _, e in { { x0, x1, z0, z0 }, { x0, x1, z1, z1 }, { x0, x0, z0, z1 }, { x1, x1, z0, z1 } } do
		local along = e[2] - e[1] + e[4] - e[3] + wide
		local size = if e[3] == e[4] then Vector3.new(along, tall, wide) else Vector3.new(wide, tall, along)
		block(model, "LobbyHedge", size, CFrame.new((e[1] + e[2]) / 2, SandboxMap.GroundTop + tall / 2, (e[3] + e[4]) / 2), HEDGE, Enum.Material.LeafyGrass, true)
	end
	-- the invisible walls on the bounds (a jump over the hedge goes nowhere)
	local high = R.Zone.Wall
	for _, e in { { b.x0, b.x1, b.z0, b.z0 + 1 }, { b.x0, b.x1, b.z1 - 1, b.z1 }, { b.x0, b.x0 + 1, b.z0, b.z1 }, { b.x1 - 1, b.x1, b.z0, b.z1 } } do
		local wall = block(model, "LobbyWall", Vector3.new(e[2] - e[1], high, e[4] - e[3]), CFrame.new((e[1] + e[2]) / 2, high / 2, (e[3] + e[4]) / 2), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, true)
		wall.Transparency = 1
		wall.CanQuery = false
		wall.CastShadow = false
	end
end

local function lamps(model: Model)
	local top = SandboxMap.GroundTop
	for _, l in L.lamps do
		block(model, "LampPole", Vector3.new(0.6, 14, 0.6), CFrame.new(l.x, top + 7, l.z), POLE, Enum.Material.Metal, true)
		block(model, "LampHead", Vector3.new(1.6, 1.4, 1.6), CFrame.new(l.x, top + 14.6, l.z), Color3.fromRGB(240, 232, 200), Enum.Material.Glass)
		block(model, "LampCap", Vector3.new(2.2, 0.4, 2.2), CFrame.new(l.x, top + 15.5, l.z), POLE, Enum.Material.Metal)
	end
end

local function trees(model: Model)
	for n, t in L.trees do
		local made = VillageWorld.model(`Tree{n}`, VillageLooks.tree(t.kind, t.x, t.z, 4000 + n * 37))
		made.Parent = model
	end
end

-- ── The portals ────────────────────────────────────────────────────────────

-- One house's gate, facade, sign and pad, in the portal's frame (its gate's middle on the ground, -Z out toward the
-- plaza: SandboxMap.cframe of the portal).
local function portal(parent: Instance, p: SandboxMap.Portal): Model
	local model = Instance.new("Model")
	model.Name = `Portal_{p.house}`
	model:SetAttribute("RunPortal", p.house)
	local style = P.Styles[p.house] or P.Styles.sandbox_house
	local wall, trim, roof, accent = rgb(style.wall), rgb(style.trim), rgb(style.roof), rgb(style.accent)
	local frame = CFrame.new(p.x, SandboxMap.GroundTop, p.z) * CFrame.Angles(0, math.rad(p.yaw), 0)
	local W, H = P.Gate[1], P.Gate[2]
	local stony = p.house == "old_mill"
	local woody = p.house == "forest_lodge" or p.house == "pond_cabin"
	local postLook = if stony then Enum.Material.Cobblestone elseif woody then Enum.Material.Wood else Enum.Material.WoodPlanks
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	-- the gate
	for _, side in { -1, 1 } do
		block(model, "GatePost", Vector3.new(1.6, H, 1.6), at(side * W / 2, H / 2, 0), trim, postLook, true)
	end
	block(model, "GateLintel", Vector3.new(W + 2.4, 1.6, 2), at(0, H + 0.8, 0), trim, postLook, true)
	local sign = block(model, "GateSign", Vector3.new(W - 2, 3.4, 0.4), at(0, H - 1.9, -0.7), DARK, Enum.Material.WoodPlanks)
	words(sign, Enum.NormalId.Front, {
		{ name = "Title", text = string.upper(p.name), box = { 0.04, 0.06, 0.92, 0.5 }, color = CREAM, bold = true },
		{ name = "Status", text = "WALK ONTO THE PAD", box = { 0.06, 0.6, 0.88, 0.32 }, color = rgb(P.Free) },
	})
	-- the facade behind it: its walls, a dark door, two windows, a gable, a band
	local wallLook = if stony then Enum.Material.Cobblestone elseif woody then Enum.Material.WoodPlanks else Enum.Material.SmoothPlastic
	local fw, fh, fz = W + 4, 10, 9
	block(model, "Facade", Vector3.new(fw, fh, 1.2), at(0, fh / 2, fz), wall, wallLook, true)
	block(model, "FacadeBand", Vector3.new(fw + 0.4, 0.6, 1.5), at(0, fh - 0.3, fz), trim, Enum.Material.WoodPlanks)
	block(model, "FacadeDoor", Vector3.new(4.6, 7.4, 0.4), at(0, 3.7, fz - 0.7), DARK, Enum.Material.WoodPlanks)
	for _, side in { -1, 1 } do
		block(model, "FacadeWindow", Vector3.new(3, 3, 0.3), at(side * 6.4, 5.6, fz - 0.7), Color3.fromRGB(150, 180, 196), Enum.Material.Glass)
		local half = fw / 2
		local gable = Instance.new("WedgePart")
		gable.Name = "FacadeGable"
		gable.Anchored = true
		gable.Size = Vector3.new(1.2, 5, half)
		-- (a wedge's high side is its +Z: turned a quarter so it faces the facade's middle)
		gable.CFrame = at(side * half / 2, fh + 2.5, fz) * CFrame.Angles(0, math.rad(if side < 0 then 90 else -90), 0)
		gable.Color = roof
		gable.Material = Enum.Material.Slate
		gable.TopSurface = Enum.SurfaceType.Smooth
		gable.BottomSurface = Enum.SurfaceType.Smooth
		gable.CanTouch = false
		gable.Parent = model
	end
	block(model, "FacadeRidge", Vector3.new(1.8, 0.8, 1.8), at(0, fh + 5.1, fz), trim, Enum.Material.WoodPlanks)
	-- its house's own detail
	if p.house == "sandbox_house" then -- (the farm: round bales)
		for _, side in { -1, 1 } do
			cylinder(model, "Bale", 3, 3.6, at(side * (fw / 2 + 2.2), 1.8, fz - 1), accent, Enum.Material.Grass, true)
		end
	elseif p.house == "pond_cabin" then -- (the pond: a rowing boat leaning on the wall, an oar)
		block(model, "Boat", Vector3.new(2.4, 7, 0.9), at(fw / 2 + 1.8, 3.4, fz - 1) * CFrame.Angles(math.rad(-12), 0, 0), accent, Enum.Material.WoodPlanks, true)
		block(model, "Oar", Vector3.new(0.3, 6, 0.3), at(-fw / 2 - 1.2, 3, fz - 1) * CFrame.Angles(0, 0, math.rad(10)), trim, Enum.Material.Wood)
	elseif p.house == "lone_house" then -- (the lone house: its mailbox)
		block(model, "MailboxPost", Vector3.new(0.35, 3.4, 0.35), at(W / 2 + 2.6, 1.7, -0.5), DARK, Enum.Material.Wood)
		block(model, "Mailbox", Vector3.new(1.5, 1.1, 1.9), at(W / 2 + 2.6, 3.9, -0.5), accent, Enum.Material.Metal)
	elseif p.house == "forest_lodge" then -- (the lodge: antlers over its door, a log pile)
		for _, side in { -1, 1 } do
			block(model, "Antler", Vector3.new(0.3, 2.4, 0.3), at(side * 0.9, 9, fz - 0.8) * CFrame.Angles(0, 0, math.rad(side * -30)), accent, Enum.Material.SmoothPlastic)
		end
		for n = 0, 2 do
			cylinder(model, "Log", 4, 1.3, at(-fw / 2 - 2.2, 0.65 + n * 1.1, fz - 1 - (n % 2) * 0.4) * CFrame.Angles(0, math.rad(90), 0), trim, Enum.Material.Wood)
		end
	elseif p.house == "old_mill" then -- (the mill: its wheel on the side)
		cylinder(model, "MillWheel", 1.4, 9, at(fw / 2 + 0.9, 4.6, fz), accent, Enum.Material.WoodPlanks, true)
		cylinder(model, "MillHub", 2, 1.4, at(fw / 2 + 0.9, 4.6, fz), DARK, Enum.Material.Metal)
	elseif p.house == "orchard_cottage" then -- (the orchard: an apple tree, a beehive)
		block(model, "AppleTrunk", Vector3.new(0.7, 4.5, 0.7), at(-fw / 2 - 2.6, 2.25, fz - 2), Color3.fromRGB(110, 80, 56), Enum.Material.Wood, true)
		local crown = block(model, "AppleCrown", Vector3.new(5, 4.4, 5), at(-fw / 2 - 2.6, 6, fz - 2), Color3.fromRGB(86, 140, 60), Enum.Material.LeafyGrass)
		crown.Shape = Enum.PartType.Ball
		block(model, "Beehive", Vector3.new(1.8, 2, 1.8), at(fw / 2 + 2, 1, fz - 1.5), Color3.fromRGB(236, 196, 60), Enum.Material.WoodPlanks, true)
	end
	-- the pad: a dark rim, the glow on it (no collision: you stand on the plaza through it)
	local pad = p.pad
	local px, pz = (pad.x0 + pad.x1) / 2, (pad.z0 + pad.z1) / 2
	local rim = block(model, "RunPadRim", Vector3.new(pad.x1 - pad.x0 + 1.6, 0.16, pad.z1 - pad.z0 + 1.6), CFrame.new(px, SandboxMap.GroundTop + 0.08, pz), Color3.fromRGB(34, 40, 48), Enum.Material.Metal)
	rim.CastShadow = false
	local glow = block(model, "RunPad", Vector3.new(pad.x1 - pad.x0, 0.2, pad.z1 - pad.z0), CFrame.new(px, SandboxMap.GroundTop + 0.12, pz), rgb(P.Free), Enum.Material.Neon)
	glow.Transparency = 0.25
	glow.CastShadow = false
	glow:SetAttribute("RunPad", p.house)
	model.PrimaryPart = glow
	model.Parent = parent
	return model
end

-- ── The PAINT shop ─────────────────────────────────────────────────────────

local function paintShop(model: Model)
	local shop = L.shops.paint
	local s = shop.spot
	local frame = CFrame.new(s.x, SandboxMap.GroundTop, s.z) * CFrame.Angles(0, math.rad(s.yaw), 0) -- (-Z: its front, to the plaza)
	local pink, white = Color3.fromRGB(214, 72, 120), Color3.fromRGB(244, 240, 232)
	local r = shop.rect
	local w = math.max(r.x1 - r.x0, r.z1 - r.z0)
	local d = math.min(r.x1 - r.x0, r.z1 - r.z0)
	local booth = Instance.new("Model")
	booth.Name = "PaintShop"
	block(booth, "PaintBack", Vector3.new(w, 10, 1), frame * CFrame.new(0, 5, d - 0.5), white, Enum.Material.SmoothPlastic, true)
	for _, side in { -1, 1 } do
		block(booth, "PaintSide", Vector3.new(1, 10, d - 1), frame * CFrame.new(side * (w / 2 - 0.5), 5, d / 2), white, Enum.Material.SmoothPlastic, true)
	end
	block(booth, "PaintRoof", Vector3.new(w + 1, 0.8, d + 1.5), frame * CFrame.new(0, 10.4, d / 2 - 0.75), pink, Enum.Material.SmoothPlastic, true)
	local counter = block(booth, "PaintCounter", Vector3.new(w - 4, 3.4, 2.4), frame * CFrame.new(0, 1.7, 2.2), pink, Enum.Material.SmoothPlastic, true)
	local sign = block(booth, "PaintSign", Vector3.new(w - 2, 2.6, 0.3), frame * CFrame.new(0, 8.6, -0.3), DARK, Enum.Material.SmoothPlastic)
	words(sign, Enum.NormalId.Front, { { name = "Title", text = "🎨 PAINT SHOP · YOUR TRUCK", box = { 0.03, 0.12, 0.94, 0.76 }, color = CREAM, bold = true } })
	local cans = { Color3.fromRGB(210, 40, 46), Color3.fromRGB(40, 110, 200), Color3.fromRGB(246, 196, 52), Color3.fromRGB(60, 160, 80) }
	for n, c in cans do
		cylinder(booth, "PaintCan", 1.2, 1, frame * CFrame.new(-w / 2 + 3 + n * 1.6, 4, 2.2) * CFrame.Angles(0, 0, math.rad(90)), c, Enum.Material.Metal)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PaintShopPrompt"
	prompt.ActionText = "Paint your truck"
	prompt.ObjectText = "PAINT SHOP"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("PaintShop", true)
	prompt.Parent = counter
	booth.Parent = model
end

-- ── The build ──────────────────────────────────────────────────────────────

function LobbyWorld.build(world: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Lobby"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	plaza(model)
	hedge(model)
	lamps(model)
	trees(model)
	local portals = Instance.new("Folder")
	portals.Name = "Portals"
	for _, p in L.portals do
		portal(portals, p)
	end
	portals.Parent = model
	paintShop(model)
	-- the ZDC dispatch kiosk (MoveSites' kiosk art; server/Runs.luau puts its prompt on the corkboard)
	local _, board = MoveSites.kiosk(model, L.dispatch, "ZdcDispatch")
	board:SetAttribute("RunDispatch", true)
	model.Parent = world
	return model
end

return LobbyWorld
