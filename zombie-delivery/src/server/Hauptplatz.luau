--!strict
-- 7.1, the Hauptplatz (Map.Square; the Alps, step 1): an Austrian town square on Downtown block (0, -1), north of the
-- Central Park across Bone St, where 6.12.15's garden stood (and Last Stop Supplies' old building before it). The timber
-- footbridge over the street joins the two (server/Footbridge.luau); its ramp comes down along the square's south and
-- west edges over a green strip. server/World.luau builds it as a piece of the world (Hauptplatz.build, with World's
-- helpers handed over: no new top-level locals there, the -O0 register limit). Everything is placed from Map.Square's
-- layout (u east, v south from the block's middle) and the square's own dice (Map.Square.seed).
--
--   the ground    the sidewalk band (concrete, as every block's) round a slab of cobbles (footsteps sound like stone),
--                 the kerb all round (server/Curbs.luau); grass on the green strip under the footbridge's ramp, light
--                 granite bands across the square and a granite ring round the fountain
--   the fountain  a round stone basin with a solid rim (the water just under its top: nobody swims or sinks), four
--                 bronze spouts from its pedestal, a stone column with a gilded figure on top
--   the maypole   white with red bands, on a stone foot between two iron clamps, a green wreath with red and white
--                 ribbons, painted guild boards up the pole, a fir crown on top
--   the Gasthof   the Gasthof Edelweiss on the north side, its front to the square: white render on a stone plinth,
--                 painted corners, green shutters, red geraniums in the window boxes, an arched door between two lamps,
--                 its name board over the door, a hanging iron sign, a steep shingle roof with wide eaves and a chimney;
--                 the café tables under their umbrellas in front of it (the Schanigarten)
--   the rest      wooden benches round the fountain and by the maypole, gas-style street lamps (they glow at night,
--                 the lit ones light the square), long planters with geraniums, linden trees and a HAUPTPLATZ · SAFE
--                 ZONE board on posts by every sidewalk
-- About 220 parts, four lights. Solid: the ground, the fountain's rim, pedestal and column, the maypole's foot and pole,
-- the Gasthof, the tables and chairs, the benches, the lamp posts, the planters, the trunks and the signs' posts; the
-- rest is decoration (no collision, no ray hits). Nothing of it on the sidewalk band (the people's walk line).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Map)

local Hauptplatz = {}

export type Tools = {
	part: (parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?) -> Part,
	deco: (p: Part) -> Part,
	sign: (parent: Instance, text: string, size: Vector3, cframe: CFrame, color: Color3, background: Color3?, art: string?, artHeight: number?) -> (),
	nightLight: (item: Instance, lit: Color3?, dim: Color3?, dimMaterial: string?) -> (),
}

local WALK = Map.WalkTop
local HALF = Map.BlockSize / 2
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder standing up

-- The shades (the sidewalk's grey is every block's).
local WALK_GREY = Color3.fromRGB(150, 150, 146)
local COBBLES = Color3.fromRGB(150, 142, 130)
local GRANITE = Color3.fromRGB(186, 180, 168)
local GRASS = Color3.fromRGB(84, 118, 58)
local STONE = Color3.fromRGB(200, 194, 180)
local STONE_DARK = Color3.fromRGB(132, 128, 120)
local GILT = Color3.fromRGB(214, 176, 82)
local BRONZE = Color3.fromRGB(96, 116, 92)
local WATER = Color3.fromRGB(116, 176, 196)
local RENDER = Color3.fromRGB(240, 234, 218)
local CORNER = Color3.fromRGB(206, 178, 128)
local SHUTTER = Color3.fromRGB(56, 98, 64)
local DARK_WOOD = Color3.fromRGB(74, 50, 34)
local WOOD = Color3.fromRGB(132, 94, 60)
local SHINGLES = Color3.fromRGB(70, 56, 46)
local IRON = Color3.fromRGB(40, 40, 42)
local WINDOW = Color3.fromRGB(46, 56, 64)
local GERANIUM = Color3.fromRGB(212, 40, 48)
local LEAVES = Color3.fromRGB(58, 104, 52)
local RED = Color3.fromRGB(196, 40, 44)
local WHITE = Color3.fromRGB(244, 242, 236)
local LAMP_LIT = Color3.fromRGB(255, 214, 150)
local LAMP_DIM = Color3.fromRGB(218, 210, 186)
local WINDOW_LIT = Color3.fromRGB(255, 210, 120)

local function cylinder(tools: Tools, parent: Instance, name: string, length: number, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = tools.part(parent, name, Vector3.new(length, diameter, diameter), cframe, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- (a ball is round in Roblox whatever its size says: one diameter)
local function ball(tools: Tools, parent: Instance, name: string, diameter: number, at: Vector3, color: Color3, material: Enum.Material?): Part
	local p = tools.deco(tools.part(parent, name, Vector3.new(diameter, diameter, diameter), CFrame.new(at), color, material))
	p.Shape = Enum.PartType.Ball
	return p
end

local function pointLight(parent: Instance, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = Color3.fromRGB(255, 200, 140)
	l.Shadows = false
	l.Parent = parent
end

-- A box of geraniums on a frame's front: the trough (dark wood) and the flowers over it, red on green.
local function flowerBox(tools: Tools, parent: Instance, frame: CFrame, width: number)
	tools.deco(tools.part(parent, "FlowerBox", Vector3.new(width, 0.6, 0.7), frame, DARK_WOOD, Enum.Material.Wood))
	tools.deco(tools.part(parent, "Geraniums", Vector3.new(width - 0.2, 0.55, 0.8), frame * CFrame.new(0, 0.5, -0.05), GERANIUM, Enum.Material.Grass))
end

-- A window on a wall (frame: its middle on the wall's face, -Z out): the dark glass (warm at night) in front of the open
-- green shutters (one panel wider than the window, showing on both sides).
local function window(tools: Tools, parent: Instance, frame: CFrame, w: number, h: number)
	tools.deco(tools.part(parent, "Shutters", Vector3.new(w + 2.6, h + 0.2, 0.12), frame * CFrame.new(0, 0, -0.06), SHUTTER, Enum.Material.Wood))
	local glass = tools.deco(tools.part(parent, "Window", Vector3.new(w, h, 0.2), frame * CFrame.new(0, 0, -0.16), WINDOW, Enum.Material.Glass))
	tools.nightLight(glass, WINDOW_LIT, WINDOW, "Glass")
end

-- A gas-style street lamp at `at` (its foot on the ground): an iron foot and post, a glass lantern under a cap that
-- glows at night; `lit`: a real light over the square too.
local function gasLamp(tools: Tools, parent: Instance, at: Vector3, lit: boolean)
	cylinder(tools, parent, "LampFoot", 1.1, 1, CFrame.new(at + Vector3.new(0, 0.55, 0)) * UPRIGHT, IRON, Enum.Material.Metal)
	cylinder(tools, parent, "LampPost", 8.4, 0.4, CFrame.new(at + Vector3.new(0, 4.6, 0)) * UPRIGHT, IRON, Enum.Material.Metal)
	local head = tools.deco(tools.part(parent, "Lantern", Vector3.new(1.2, 1.7, 1.2), CFrame.new(at + Vector3.new(0, 9.55, 0)) * CFrame.Angles(0, math.rad(45), 0), LAMP_DIM, Enum.Material.Glass))
	tools.deco(tools.part(parent, "LanternCap", Vector3.new(1.7, 0.35, 1.7), CFrame.new(at + Vector3.new(0, 10.55, 0)) * CFrame.Angles(0, math.rad(45), 0), IRON, Enum.Material.Metal))
	if lit then
		pointLight(head, 28, 1.3)
	end
	tools.nightLight(head, LAMP_LIT, LAMP_DIM, "Glass")
end

-- A wooden bench at `at` (the middle of its seat's front edge on the ground), facing `look` (flat).
local function bench(tools: Tools, parent: Instance, at: Vector3, look: Vector3)
	local frame = CFrame.lookAt(at, at + look)
	tools.part(parent, "Bench", Vector3.new(5.6, 0.35, 1.7), frame * CFrame.new(0, 1.75, 0.6), WOOD, Enum.Material.WoodPlanks)
	tools.part(parent, "BenchBack", Vector3.new(5.6, 1.5, 0.25), frame * CFrame.new(0, 2.85, 1.45) * CFrame.Angles(math.rad(10), 0, 0), WOOD, Enum.Material.WoodPlanks)
	for _, x in { -2.3, 2.3 } do
		tools.deco(tools.part(parent, "BenchLeg", Vector3.new(0.3, 1.6, 1.6), frame * CFrame.new(x, 0.8, 0.7), IRON, Enum.Material.Metal))
	end
end

-- Builds the square on its block (Map.Square) into `parent` (World's Downtown folder).
function Hauptplatz.build(parent: Instance, tools: Tools)
	local S = Map.Square
	local part, deco = tools.part, tools.deco
	local folder = Instance.new("Folder")
	folder.Name = "Hauptplatz"
	folder.Parent = parent
	local cx, cz = S.x, S.z
	local rng = Random.new(S.seed)
	local lawn = HALF - S.walk
	local function at(u: number, y: number, v: number): Vector3
		return Vector3.new(cx + u, y, cz + v)
	end

	-- ── The ground ──────────────────────────────────────────────────────────
	-- The sidewalk band in four pieces round the cobbles, the kerb all round; the grass strip under the footbridge's
	-- ramp (a hair over the cobbles), the granite bands across the square.
	for _, box in { { -HALF, HALF, -HALF, -lawn }, { -HALF, HALF, lawn, HALF }, { -HALF, -lawn, -lawn, lawn }, { lawn, HALF, -lawn, lawn } } do
		local u0, u1, v0, v1 = box[1], box[2], box[3], box[4]
		part(folder, "Sidewalk", Vector3.new(u1 - u0, WALK, v1 - v0), CFrame.new(at((u0 + u1) / 2, WALK / 2, (v0 + v1) / 2)), WALK_GREY, Enum.Material.Concrete)
	end
	part(folder, "Cobbles", Vector3.new(2 * lawn, WALK, 2 * lawn), CFrame.new(at(0, WALK / 2, 0)), COBBLES, Enum.Material.Cobblestone)
	require(script.Parent.Curbs).ring(folder, cx, cz)
	for n, box in S.greens do
		local thick = 0.1 + n * 0.002
		deco(part(folder, "Grass", Vector3.new(box.u1 - box.u0, thick, box.v1 - box.v0), CFrame.new(at((box.u0 + box.u1) / 2, WALK + thick / 2, (box.v0 + box.v1) / 2)), GRASS, Enum.Material.Grass))
	end
	local F = S.fountain
	local square = S.paths[1]
	local gasthof = S.gasthof
	deco(part(folder, "GraniteBand", Vector3.new(square.u1 - square.u0, 0.06, 1.4), CFrame.new(at((square.u0 + square.u1) / 2, WALK + 0.03, F.v)), GRANITE, Enum.Material.Slate))
	deco(part(folder, "GraniteBand", Vector3.new(1.4, 0.07, square.v1 - gasthof.v1), CFrame.new(at(F.u, WALK + 0.035, (square.v1 + gasthof.v1) / 2)), GRANITE, Enum.Material.Slate))
	deco(cylinder(tools, folder, "GraniteRing", 0.08, 2 * F.r + 6, CFrame.new(at(F.u, WALK + 0.04, F.v)) * UPRIGHT, GRANITE, Enum.Material.Slate))

	-- ── The fountain ────────────────────────────────────────────────────────
	-- The basin (a step round it, the solid rim, the water just under its top), the pedestal with a bronze spout to
	-- each side and its water arcing into the basin, the column, its capital and the gilded figure in a ring of light.
	do
		local base = at(F.u, WALK, F.v)
		deco(cylinder(tools, folder, "FountainStep", 0.35, 2 * F.r + 1.6, CFrame.new(base + Vector3.new(0, 0.175, 0)) * UPRIGHT, STONE_DARK, Enum.Material.Slate))
		cylinder(tools, folder, "FountainRim", F.rim, 2 * F.r, CFrame.new(base + Vector3.new(0, F.rim / 2, 0)) * UPRIGHT, STONE, Enum.Material.Limestone)
		local water = deco(cylinder(tools, folder, "FountainWater", 0.12, 2 * F.r - 1.3, CFrame.new(base + Vector3.new(0, F.rim + 0.02, 0)) * UPRIGHT, WATER, Enum.Material.Glass))
		water.Transparency = 0.2
		local pedestal = F.rim + 3
		part(folder, "Pedestal", Vector3.new(3.2, 3, 3.2), CFrame.new(base + Vector3.new(0, F.rim + 1.5, 0)), STONE, Enum.Material.Limestone)
		for k = 0, 3 do
			local turn = CFrame.new(base) * CFrame.Angles(0, k * math.pi / 2, 0)
			deco(cylinder(tools, folder, "Spout", 1.2, 0.3, turn * CFrame.new(2.1, F.rim + 2.2, 0), BRONZE, Enum.Material.Metal))
			local a = (turn * CFrame.new(2.7, F.rim + 2.15, 0)).Position
			local b = (turn * CFrame.new(4.3, F.rim - 0.05, 0)).Position
			local jet = deco(cylinder(tools, folder, "Jet", (b - a).Magnitude, 0.28, CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(200, 230, 240), Enum.Material.Glass))
			jet.Transparency = 0.35
		end
		local figure = F.column - 3.6 -- (the capital's top: the figure stands on it)
		cylinder(tools, folder, "Column", figure - 0.8 - pedestal, 1.3, CFrame.new(base + Vector3.new(0, (pedestal + figure - 0.8) / 2, 0)) * UPRIGHT, STONE, Enum.Material.Limestone)
		part(folder, "Capital", Vector3.new(2, 0.8, 2), CFrame.new(base + Vector3.new(0, figure - 0.4, 0)), STONE, Enum.Material.Limestone)
		deco(cylinder(tools, folder, "Figure", 2.6, 1, CFrame.new(base + Vector3.new(0, figure + 1.3, 0)) * UPRIGHT, GILT, Enum.Material.Metal))
		ball(tools, folder, "FigureHead", 0.8, base + Vector3.new(0, figure + 3, 0), GILT, Enum.Material.Metal)
		deco(cylinder(tools, folder, "Halo", 0.1, 1.7, CFrame.new(base + Vector3.new(0, figure + 3.1, -0.35)) * CFrame.Angles(0, math.rad(90), 0), GILT, Enum.Material.Metal))
	end

	-- ── The maypole ─────────────────────────────────────────────────────────
	do
		local M = S.maypole
		local base = at(M.u, WALK, M.v)
		local H = M.height
		part(folder, "MaypoleFoot", Vector3.new(2.6, 1.4, 2.6), CFrame.new(base + Vector3.new(0, 0.7, 0)), STONE_DARK, Enum.Material.Slate)
		for _, side in { -1, 1 } do
			deco(part(folder, "MaypoleClamp", Vector3.new(0.4, 4, 1.8), CFrame.new(base + Vector3.new(side * 0.75, 3.4, 0)), IRON, Enum.Material.Metal))
		end
		local top = H - 4.2 -- (the pole's top, under the crown)
		cylinder(tools, folder, "Maypole", top - 1.4, 1, CFrame.new(base + Vector3.new(0, (top + 1.4) / 2, 0)) * UPRIGHT, WHITE, Enum.Material.Wood)
		-- the red bands up to the wreath
		local wreath = H * 0.66
		local count = 7
		for n = 1, count do
			local y = 6 + (wreath - 8) * (n - 0.5) / count
			deco(cylinder(tools, folder, "MaypoleBand", 1.5, 1.08, CFrame.new(base + Vector3.new(0, y, 0)) * UPRIGHT, RED, Enum.Material.SmoothPlastic))
		end
		deco(cylinder(tools, folder, "MaypoleWreath", 1, 3.8, CFrame.new(base + Vector3.new(0, wreath, 0)) * UPRIGHT, Color3.fromRGB(52, 98, 50), Enum.Material.Grass))
		for k = 0, 3 do
			local angle = k * math.pi / 2 + math.pi / 4
			local ribbon = Vector3.new(math.cos(angle) * 1.9, wreath - 1.9, math.sin(angle) * 1.9)
			deco(part(folder, "MaypoleRibbon", Vector3.new(0.5, 3.2, 0.1), CFrame.lookAt(base + ribbon, base + ribbon + Vector3.new(math.cos(angle), 0, math.sin(angle))), if k % 2 == 0 then RED else WHITE, Enum.Material.Fabric))
		end
		-- the guild boards up the pole, the sides taking turns (the trades' colours)
		local boards = { Color3.fromRGB(64, 104, 168), Color3.fromRGB(70, 128, 70), Color3.fromRGB(196, 150, 64) }
		for n, shade in boards do
			local angle = n * 2.1
			local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local y = wreath + 1.6 + (n - 1) * 2.9
			local arm = base + Vector3.new(0, y, 0) + out * 0.9
			deco(part(folder, "GuildArm", Vector3.new(0.15, 0.15, 1.8), CFrame.lookAt(arm, arm + out), IRON, Enum.Material.Metal))
			deco(part(folder, "GuildBoard", Vector3.new(1.6, 1.6, 0.15), CFrame.lookAt(base + Vector3.new(0, y - 0.95, 0) + out * 1.7, base + Vector3.new(0, y - 0.95, 0) + out * 2.7), shade, Enum.Material.Wood))
		end
		local crown = Color3.fromRGB(44, 86, 50)
		ball(tools, folder, "MaypoleCrown", 3.6, base + Vector3.new(0, H - 2.6, 0), crown, Enum.Material.Grass)
		ball(tools, folder, "MaypoleCrown", 2.4, base + Vector3.new(0, H - 0.9, 0), crown, Enum.Material.Grass)
	end

	-- ── The Gasthof ─────────────────────────────────────────────────────────
	-- Its frame on the ground at the middle of its front wall, -Z out to the square (south).
	do
		local G = S.gasthof
		local W, D, H = G.u1 - G.u0, G.v1 - G.v0, G.height
		local origin = at((G.u0 + G.u1) / 2, WALK, G.v1)
		local f = CFrame.lookAt(origin, origin + Vector3.new(0, 0, 1))
		part(folder, "Gasthof", Vector3.new(W, H, D), f * CFrame.new(0, H / 2, D / 2), RENDER, Enum.Material.Plaster)
		deco(part(folder, "Plinth", Vector3.new(W + 0.3, 1.4, D + 0.3), f * CFrame.new(0, 0.7, D / 2), STONE_DARK, Enum.Material.Slate))
		for _, side in { -1, 1 } do
			deco(part(folder, "PaintedCorner", Vector3.new(1.5, H - 1.4, 0.12), f * CFrame.new(side * (W / 2 - 0.75), 1.4 + (H - 1.4) / 2, -0.06), CORNER, Enum.Material.Plaster))
		end
		-- The arched door in its stone surround, the step, a lamp on each side (one a real light).
		deco(part(folder, "DoorSurround", Vector3.new(5.4, 6, 0.16), f * CFrame.new(0, 3, -0.08), STONE, Enum.Material.Limestone))
		deco(cylinder(tools, folder, "DoorArch", 0.16, 5.4, f * CFrame.new(0, 6, -0.08) * CFrame.Angles(0, math.rad(90), 0), STONE, Enum.Material.Limestone))
		deco(part(folder, "Door", Vector3.new(4, 6, 0.2), f * CFrame.new(0, 3, -0.2), DARK_WOOD, Enum.Material.Wood))
		deco(cylinder(tools, folder, "DoorTop", 0.2, 4, f * CFrame.new(0, 6, -0.2) * CFrame.Angles(0, math.rad(90), 0), DARK_WOOD, Enum.Material.Wood))
		deco(part(folder, "DoorStep", Vector3.new(6.4, 0.3, 1.8), f * CFrame.new(0, 0.15, -0.9), STONE_DARK, Enum.Material.Slate))
		for _, side in { -1, 1 } do
			local lamp = deco(part(folder, "DoorLamp", Vector3.new(0.9, 1.3, 0.9), f * CFrame.new(side * 3.3, 6.4, -0.75), LAMP_DIM, Enum.Material.Glass))
			deco(part(folder, "DoorLampCap", Vector3.new(1.2, 0.3, 1.2), f * CFrame.new(side * 3.3, 7.2, -0.75), IRON, Enum.Material.Metal))
			tools.nightLight(lamp, LAMP_LIT, LAMP_DIM, "Glass")
			if side == 1 then
				pointLight(lamp, 22, 1.1)
			end
		end
		-- The windows: four downstairs (a box of geraniums under each), five upstairs over one long box.
		for _, x in { -12.5, -6.5, 6.5, 12.5 } do
			window(tools, folder, f * CFrame.new(x, 4.1, 0), 2.8, 3.4)
			flowerBox(tools, folder, f * CFrame.new(x, 2.1, -0.5), 3.4)
		end
		for _, x in { -12.5, -6.5, 0, 6.5, 12.5 } do
			window(tools, folder, f * CFrame.new(x, 13.1, 0), 2.8, 3)
		end
		flowerBox(tools, folder, f * CFrame.new(0, 11.1, -0.5), W - 6)
		-- The name over the door, the hanging iron sign by the east corner.
		tools.sign(folder, string.upper(G.name), Vector3.new(15, 1.4, 0.3), f * CFrame.new(0, 9.7, -0.2), Color3.new(1, 1, 1), nil, S.id, 1.4)
		local arm = f * CFrame.new(-(W / 2 - 3), 9.6, -1.2)
		deco(part(folder, "SignArm", Vector3.new(0.15, 0.15, 2.4), arm, IRON, Enum.Material.Metal))
		deco(cylinder(tools, folder, "HangingSign", 0.12, 1.9, arm * CFrame.new(0, -1.1, -0.4) * CFrame.Angles(0, math.rad(90), 0), GILT, Enum.Material.Metal))
		-- The roof: steep, its ridge along the front, wide eaves (two shingle slabs over the solid gable), a chimney.
		local R = 6
		local half = D / 2
		for _, s in { -1, 1 } do
			local wedge = part(folder, "Roof", Vector3.new(W, R, half), f * CFrame.new(0, H + R / 2, D / 2 + s * half / 2) * CFrame.Angles(0, if s < 0 then 0 else math.pi, 0), RENDER, Enum.Material.Plaster)
			wedge.Shape = Enum.PartType.Wedge
		end
		local pitch = math.atan(R / half)
		local eave = 1.8
		local length = (half + eave) / math.cos(pitch)
		for _, s in { -1, 1 } do
			-- (from the ridge down to the front (s -1) or the back (s 1), its top a hair over the gable's slope)
			local mid = f * CFrame.new(0, H + R - (length / 2) * math.sin(pitch), D / 2 + s * (length / 2) * math.cos(pitch))
			deco(part(folder, "RoofShingles", Vector3.new(W + 2.4, 0.45, length), mid * CFrame.Angles(s * pitch, 0, 0) * CFrame.new(0, 0.24, 0), SHINGLES, Enum.Material.Slate))
		end
		deco(part(folder, "RoofRidge", Vector3.new(W + 2.6, 0.5, 0.8), f * CFrame.new(0, H + R + 0.2, D / 2), DARK_WOOD, Enum.Material.Wood))
		part(folder, "Chimney", Vector3.new(2, 5.5, 2), f * CFrame.new(W / 2 - 7, H + R + 0.2, D / 2 + 2), RENDER, Enum.Material.Plaster)
	end

	-- ── The Schanigarten: the café tables in front of the Gasthof ──────────
	for n, t in S.tables do
		local base = at(t.u, WALK, t.v)
		cylinder(tools, folder, "CafeTable", 0.2, 2.6, CFrame.new(base + Vector3.new(0, 2.6, 0)) * UPRIGHT, WHITE, Enum.Material.SmoothPlastic)
		cylinder(tools, folder, "TableLeg", 2.5, 0.3, CFrame.new(base + Vector3.new(0, 1.25, 0)) * UPRIGHT, IRON, Enum.Material.Metal)
		deco(cylinder(tools, folder, "UmbrellaPole", 5.2, 0.18, CFrame.new(base + Vector3.new(0, 5.2, 0)) * UPRIGHT, WOOD, Enum.Material.Wood))
		deco(part(folder, "Umbrella", Vector3.new(6.2, 0.3, 6.2), CFrame.new(base + Vector3.new(0, 7.75, 0)), if n % 2 == 0 then Color3.fromRGB(236, 228, 210) else Color3.fromRGB(176, 44, 42), Enum.Material.Fabric))
		for _, side in { -1, 1 } do
			local turn = CFrame.new(base) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3) + (if side > 0 then 0 else math.pi), 0)
			part(folder, "Chair", Vector3.new(1.3, 0.25, 1.3), turn * CFrame.new(2.2, 1.8, 0), WOOD, Enum.Material.Wood)
			deco(part(folder, "ChairBack", Vector3.new(0.2, 1.6, 1.3), turn * CFrame.new(2.8, 2.7, 0), WOOD, Enum.Material.Wood))
		end
	end

	-- ── Benches, lamps, planters, trees, the signs ──────────────────────────
	for _, b in S.benches do
		bench(tools, folder, at(b.u, WALK, b.v), Vector3.new(b.du, 0, b.dv))
	end
	for _, lamp in S.lamps do
		gasLamp(tools, folder, at(lamp.u, WALK, lamp.v), lamp.lit)
	end
	for _, planter in S.planters do
		local size = if planter.alongU then Vector3.new(planter.length, 1.6, 1.6) else Vector3.new(1.6, 1.6, planter.length)
		local middle = at(planter.u, WALK, planter.v)
		part(folder, "Planter", size, CFrame.new(middle + Vector3.new(0, 0.8, 0)), WOOD, Enum.Material.WoodPlanks)
		local bloom = if planter.alongU then Vector3.new(planter.length - 0.4, 0.8, 1.3) else Vector3.new(1.3, 0.8, planter.length - 0.4)
		deco(part(folder, "PlanterLeaves", bloom + Vector3.new(0.2, -0.3, 0.2), CFrame.new(middle + Vector3.new(0, 1.7, 0)), LEAVES, Enum.Material.Grass))
		deco(part(folder, "PlanterGeraniums", bloom, CFrame.new(middle + Vector3.new(0, 1.95, 0)), GERANIUM, Enum.Material.Grass))
	end
	for _, tree in S.trees do
		local foot = at(tree.u, WALK, tree.v)
		local size = tree.size or 8
		local height = rng:NextNumber(6.5, 8)
		cylinder(tools, folder, "Trunk", height, 1.2, CFrame.new(foot + Vector3.new(0, height / 2, 0)) * UPRIGHT, Color3.fromRGB(86, 66, 48), Enum.Material.Wood)
		local green = Color3.fromRGB(70 + rng:NextInteger(0, 16), 112 + rng:NextInteger(0, 18), 54)
		ball(tools, folder, "Linden", size, foot + Vector3.new(0, height + size * 0.35, 0), green, Enum.Material.Grass)
		ball(tools, folder, "Linden", size * 0.72, foot + Vector3.new(rng:NextNumber(-1, 1), height + size * 0.85, rng:NextNumber(-1, 1)), green:Lerp(Color3.new(1, 1, 0.6), 0.08), Enum.Material.Grass)
	end
	for _, s in S.signs do
		local base = at(s.u, WALK, s.v)
		local frame = CFrame.lookAt(base, base + Vector3.new(s.nu, 0, s.nv)) -- (-Z: out to the street)
		for _, x in { -3.2, 3.2 } do
			part(folder, "SignPost", Vector3.new(0.4, 5.4, 0.4), frame * CFrame.new(x, 2.7, 0), DARK_WOOD, Enum.Material.Wood)
		end
		tools.sign(folder, `{string.upper(S.name)}  SAFE ZONE`, Vector3.new(6.4, 1.4, 0.25), frame * CFrame.new(0, 4.4, -0.3), Color3.new(1, 1, 1), nil, S.id, 1.4)
	end
end

return Hauptplatz
