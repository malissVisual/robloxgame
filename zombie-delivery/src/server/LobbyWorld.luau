--!strict
-- 9.7 RUNS, the lobby (design/lobby/plan.py; shared/SandboxMap.luau Lobby; the owner: "shrink the map and put things
-- quite close together, so that it's one little lobby"; 10.4 smaller still, one PLAY circle): builds the lobby's own dress into workspace.Sandbox (server/
-- SandboxWorld.luau calls it once, after its ground: the meadow under the lobby, the plots' concrete pads; the
-- warehouses are server/Warehouse.luau's, the TOP MOVERS board server/SandboxLeaders.luau's, the Auction House
-- SandboxWorld's own while Config.Auction.On). Everything anchored, in the Persistent model "Lobby" (small: every client
-- always has it, so coming back from a run never shows it streaming in):
--   Plaza      the paved square in the middle (SandboxMap.Lobby.plaza: its top flush with the meadow, the meadow's hole)
--              and the fountain on it (a basin, its water, the spout)
--   Hedge      the hedge round the lobby, Lobby.hedge in from its bounds (solid; 10.8 low: HEDGE_TALL, the other
--              islands seen over it), and the invisible walls on the bounds (10.8 its island's grass goes on past them
--              to its edge: server/SandboxWorld.luau, design/islands/plan.py)
--   Lamps      the plaza's lamps (decoration: a fixed afternoon, their heads dim)
--   Trees      the lobby's trees (VillageLooks' trees, server/VillageWorld.luau's parts)
--   Dispatch   the Deliveros dispatch kiosk (server/MoveSites.luau's kiosk art at Lobby.dispatch, its corkboard "Board"
--              with the attribute RunDispatch: server/Runs.luau hangs its "How runs work" prompt there)
--   PlayCircle 10.4 (the owner: "on the map just one circle where you'd stand, like PLAY"; it replaces the six portals)
--              the Model "PlayCircle" at Lobby.play (attribute PlayCircle = true; Config.Runs.Party.Attribute: the open
--              lobbies and the runs for the map, server/Parties.luau writes it): a dark rim, the glowing ring
--              ("PlayRing", Neon, its colour Parties' by the lobbies' state), its floor and a soft glow ("PlayGlow"), PLAY
--              on the ground in white light, four lit posts at its corners, and the floating sign over it ("PlaySign":
--              a BillboardGui "Words", Title ▶ PLAY, Status: Parties' line). Nothing on the ground collides.
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
local PL = R.Play
local CREAM = Color3.fromRGB(250, 244, 228)
local DARK = Color3.fromRGB(40, 30, 24)
local PLAZA = Color3.fromRGB(196, 188, 172)
local STONE = Color3.fromRGB(150, 146, 140)
local WATER = Color3.fromRGB(76, 140, 190)
local POLE = Color3.fromRGB(50, 50, 54)
local HEDGE = Color3.fromRGB(52, 96, 44)
local HEDGE_TALL = Config.Islands.LobbyHedge -- 10.8: a low hedge (9.7 – 10.5: 4.5): the other islands seen over it

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
	gui.MaxDistance = PL.Sign.Range
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
	local tall, wide = HEDGE_TALL, 2.6
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

-- ── 10.4 The PLAY circle ───────────────────────────────────────────────────

-- PLAY on the ground in the circle, read from the south (the spawn's side): each letter's bars on a 3 × 5 grid (x
-- across, y down from its top), a bar { x0, y0, x1, y1 } in grid units.
local LETTERS: { { { number } } } = {
	{ { 0, 0, 1, 5 }, { 1, 0, 3, 1 }, { 1, 2, 3, 3 }, { 2, 1, 3, 2 } }, -- P
	{ { 0, 0, 1, 5 }, { 1, 4, 3, 5 } }, -- L
	{ { 0, 0, 3, 1 }, { 0, 1, 1, 5 }, { 2, 1, 3, 5 }, { 1, 2, 2, 3 } }, -- A
	{ { 0, 0, 1, 2 }, { 2, 0, 3, 2 }, { 0, 2, 3, 3 }, { 1, 3, 2, 5 } }, -- Y
}

-- The circle (Lobby.play): a dark rim, the glowing ring (Neon, the colour server/Parties.luau keeps), its floor and a
-- soft glow over it (client/PlayUi.luau breathes it), PLAY on the ground, four lit posts round it at its corners (the
-- only solid parts: the way in is open on every side), and the floating sign over it (a BillboardGui "Words": Title
-- PLAY, Status: Parties' line). Nothing on the ground collides: you walk in on the plaza.
local function playCircle(parent: Instance): Model
	local p = L.play
	local top = SandboxMap.GroundTop
	local model = Instance.new("Model")
	model.Name = "PlayCircle"
	model:SetAttribute("PlayCircle", true)
	model:SetAttribute(R.Party.Attribute, "[]")
	local flat = CFrame.Angles(0, 0, math.rad(90)) -- (a cylinder lies along its X: stood up, a disc)
	local function disc(name: string, diameter: number, y: number, high: number, color: Color3, material: Enum.Material): Part
		local d = cylinder(model, name, high, diameter, CFrame.new(p.x, top + y, p.z) * flat, color, material)
		d.CastShadow = false
		return d
	end
	disc("PlayRim", 2 * p.r + 1.6, 0.08, 0.16, Color3.fromRGB(34, 40, 48), Enum.Material.Metal)
	local ring = disc("PlayRing", 2 * p.r, 0.12, 0.2, rgb(PL.Free), Enum.Material.Neon)
	ring.Transparency = 0.05
	disc("PlayFloor", 2 * p.r - 2 * PL.Ring, 0.14, 0.24, Color3.fromRGB(44, 66, 86), Enum.Material.SmoothPlastic)
	local glow = disc("PlayGlow", 2 * p.r - 2 * PL.Ring - 0.6, 0.27, 0.02, rgb(PL.Free), Enum.Material.Neon)
	glow.Transparency = 0.8
	-- PLAY: four letters, Letters studs high, a grid unit between them
	local u = PL.Letters / 5
	local x0 = p.x - 7.5 * u
	local z0 = p.z - 2.5 * u
	for n, bars in LETTERS do
		local lx = x0 + (n - 1) * 4 * u
		for _, b in bars do
			local w, d = (b[3] - b[1]) * u, (b[4] - b[2]) * u
			local letter = block(model, "PlayLetter", Vector3.new(w, 0.06, d), CFrame.new(lx + (b[1] + b[3]) / 2 * u, top + 0.3, z0 + (b[2] + b[4]) / 2 * u),
				Color3.fromRGB(240, 248, 255), Enum.Material.Neon)
			letter.CastShadow = false
		end
	end
	-- four lit posts at its corners (45° off the four ways in)
	for k = 0, 3 do
		local a = math.rad(45 + 90 * k)
		local px, pz = p.x + math.cos(a) * (p.r + 2.2), p.z + math.sin(a) * (p.r + 2.2)
		cylinder(model, "PlayPost", 3, 0.9, CFrame.new(px, top + 1.5, pz) * flat, POLE, Enum.Material.Metal, true)
		local lamp = cylinder(model, "PlayLamp", 0.5, 1.2, CFrame.new(px, top + 3.25, pz) * flat, rgb(PL.Free), Enum.Material.Neon)
		lamp.CastShadow = false
	end
	-- the floating sign
	local anchor = block(model, "PlaySign", Vector3.new(1, 1, 1), CFrame.new(p.x, top + PL.Sign.Height, p.z), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	anchor.Transparency = 1
	anchor.CastShadow = false
	local gui = Instance.new("BillboardGui")
	gui.Name = "Words"
	gui.Size = UDim2.fromScale(PL.Sign.Size[1], PL.Sign.Size[2])
	gui.LightInfluence = 0
	gui.MaxDistance = PL.Sign.Range
	gui.AlwaysOnTop = false
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.62)
	title.Text = "▶ PLAY"
	title.TextScaled = true
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = CREAM
	title.TextStrokeColor3 = DARK
	title.TextStrokeTransparency = 0.2
	title.Parent = gui
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromScale(0.05, 0.64)
	status.Size = UDim2.fromScale(0.9, 0.3)
	status.Text = "STEP IN TO PLAY"
	status.TextScaled = true
	status.Font = Enum.Font.GothamBold
	status.TextColor3 = rgb(PL.Free)
	status.TextStrokeColor3 = DARK
	status.TextStrokeTransparency = 0.3
	status.Parent = gui
	gui.Parent = anchor
	model.PrimaryPart = ring
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
	playCircle(model) -- (10.4: the one PLAY circle in place of the six portals)
	paintShop(model)
	-- the Deliveros dispatch kiosk (MoveSites' kiosk art; server/Runs.luau puts its prompt on the corkboard)
	local _, board = MoveSites.kiosk(model, L.dispatch, "ZdcDispatch")
	board:SetAttribute("RunDispatch", true)
	model.Parent = world
	return model
end

return LobbyWorld
