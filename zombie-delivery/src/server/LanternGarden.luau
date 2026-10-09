--!strict
-- 6.12.15, the Lantern Garden (Map.Garden): a Japanese-style garden on Downtown block (0, -1), north of the Central Park
-- across Bone St, where Last Stop Supplies' old building stood. The footbridge over the street joins the two
-- (server/Footbridge.luau); its ramp comes down along the garden's south and west edges. server/World.luau builds it as a
-- piece of the world (LanternGarden.build, with World's helpers handed over: no new top-level locals there, the -O0
-- register limit). Everything is placed from Map.Garden's layout (u east, v south from the block's middle) and the
-- garden's own dice (Map.Garden.seed).
--
--   the ground    the sidewalk band (concrete, as every block's) round a moss lawn (a grass slab: footsteps sound like
--                 grass), the kerb all round (server/Curbs.luau); a clipped hedge along the lawn's edge, not under the
--                 footbridge's ramp, with a roofed wooden gate on each side (LANTERN GARDEN · SAFE ZONE over it)
--   the pond      shallow (a hand deep on the slab: you wade, nobody swims or sinks), its water in discs that run into
--                 each other, rocks round the shore, koi under the surface, lotus pads; stepping stones across it and a
--                 zig-zag plank bridge over its east lobe; a waterfall over a pile of rocks on its north shore
--   the rest      the tea pavilion (an open floor, four posts, a roof with flared, upturned eaves, a lantern hanging in
--                 it), raked gravel with three stones in their rings, stone lanterns (tall and low ones: they glow at
--                 night, four of them light the paths), cherry trees in blossom (petals on the ground and falling),
--                 bamboo, clipped azaleas, stone benches, a wash basin, gravel paths
-- About 450 parts, five lights. Solid: the ground, the hedge, the gates' posts, the rocks, the stepping stones and the
-- planks, the pavilion's floor and posts, the lanterns' feet, the trunks, the bamboo, the benches and the basin; the
-- rest is decoration (no collision, no ray hits). Nothing of it on the sidewalk band (the people's walk line).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Map)

local LanternGarden = {}

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
local MOSS = Color3.fromRGB(70, 96, 58)
local HEDGE = Color3.fromRGB(46, 78, 46)
local GRAVEL = Color3.fromRGB(184, 182, 172)
local RAKED = Color3.fromRGB(224, 222, 214)
local RAKE_LINE = Color3.fromRGB(178, 174, 164)
local STONE = Color3.fromRGB(152, 150, 142)
local STONE_DARK = Color3.fromRGB(104, 102, 96)
local MOSSY = Color3.fromRGB(126, 134, 114)
local DARK_WOOD = Color3.fromRGB(74, 50, 36)
local WOOD = Color3.fromRGB(134, 98, 64)
local TILES = Color3.fromRGB(62, 68, 78)
local WATER = Color3.fromRGB(70, 128, 132)
local POND_BED = Color3.fromRGB(44, 54, 48)
local LANTERN_LIT = Color3.fromRGB(255, 190, 110)
local LANTERN_DIM = Color3.fromRGB(226, 214, 182)
local BLOSSOMS = { Color3.fromRGB(250, 186, 206), Color3.fromRGB(244, 170, 196), Color3.fromRGB(252, 206, 222) }
local AZALEAS = { Color3.fromRGB(214, 86, 136), Color3.fromRGB(232, 132, 170), Color3.fromRGB(64, 104, 56), Color3.fromRGB(240, 226, 232) }
local KOI = { Color3.fromRGB(240, 118, 38), Color3.fromRGB(242, 240, 232), Color3.fromRGB(240, 196, 70), Color3.fromRGB(214, 58, 40) }

local function cylinder(tools: Tools, parent: Instance, name: string, length: number, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = tools.part(parent, name, Vector3.new(length, diameter, diameter), cframe, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(tools: Tools, parent: Instance, name: string, diameter: number, at: Vector3, color: Color3, material: Enum.Material?): Part
	local p = tools.deco(tools.part(parent, name, Vector3.new(diameter, diameter, diameter), CFrame.new(at), color, material))
	p.Shape = Enum.PartType.Ball
	return p
end

local function pointLight(parent: Instance, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = Color3.fromRGB(255, 196, 130)
	l.Shadows = false
	l.Parent = parent
end

-- A rough rock: a block turned any way round the vertical (or about `yaw`) and tipped a little, its foot sunk a hair
-- into the ground.
local function rock(tools: Tools, parent: Instance, at: Vector3, size: Vector3, rng: Random, color: Color3?, yaw: number?): Part
	local frame = CFrame.new(at + Vector3.new(0, size.Y / 2 - 0.1, 0))
		* CFrame.Angles(0, if yaw then yaw + rng:NextNumber(-0.15, 0.15) else rng:NextNumber(0, math.pi), 0)
		* CFrame.Angles(rng:NextNumber(-0.12, 0.12), 0, rng:NextNumber(-0.12, 0.12))
	local shade = rng:NextInteger(-12, 10)
	local base = color or STONE_DARK
	return tools.part(parent, "Rock", size, frame, Color3.fromRGB(math.clamp(base.R * 255 + shade, 0, 255), math.clamp(base.G * 255 + shade, 0, 255), math.clamp(base.B * 255 + shade, 0, 255)), Enum.Material.Slate)
end

-- A stone lantern at `at` (its foot on the ground): "tall" (a post, a platform, the light box, a square roof and a
-- jewel on top) or "low" (the snow-viewing kind: three legs under a wide round roof). The light box glows at night;
-- `lit`: a real light too. Its foot is solid.
local function stoneLantern(tools: Tools, parent: Instance, at: Vector3, kind: string, lit: boolean, turn: number)
	local frame = CFrame.new(at) * CFrame.Angles(0, turn, 0)
	local box: Part
	if kind == "low" then
		for n = 0, 2 do
			local angle = n * 2 * math.pi / 3
			local foot = Vector3.new(math.cos(angle) * 1.05, 0, math.sin(angle) * 1.05)
			local top = Vector3.new(math.cos(angle) * 0.55, 1.35, math.sin(angle) * 0.55)
			local a, b = (frame * CFrame.new(foot)).Position, (frame * CFrame.new(top)).Position
			cylinder(tools, parent, "LanternLeg", (b - a).Magnitude, 0.38, CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0), STONE, Enum.Material.Slate)
		end
		tools.deco(cylinder(tools, parent, "LanternShelf", 0.25, 1.6, frame * CFrame.new(0, 1.35, 0) * UPRIGHT, STONE, Enum.Material.Slate))
		box = tools.deco(tools.part(parent, "LanternLight", Vector3.new(1, 0.9, 1), frame * CFrame.new(0, 1.92, 0), LANTERN_DIM, Enum.Material.Glass))
		tools.deco(cylinder(tools, parent, "LanternRoof", 0.35, 3.3, frame * CFrame.new(0, 2.55, 0) * UPRIGHT, MOSSY, Enum.Material.Slate))
		tools.deco(cylinder(tools, parent, "LanternRoof", 0.4, 1.3, frame * CFrame.new(0, 2.9, 0) * UPRIGHT, MOSSY, Enum.Material.Slate))
		ball(tools, parent, "LanternJewel", 0.55, (frame * CFrame.new(0, 3.3, 0)).Position, STONE, Enum.Material.Slate)
	else
		cylinder(tools, parent, "LanternBase", 0.5, 2, frame * CFrame.new(0, 0.25, 0) * UPRIGHT, STONE, Enum.Material.Slate)
		cylinder(tools, parent, "LanternPost", 2.2, 0.75, frame * CFrame.new(0, 1.6, 0) * UPRIGHT, STONE, Enum.Material.Slate)
		tools.deco(tools.part(parent, "LanternShelf", Vector3.new(1.6, 0.4, 1.6), frame * CFrame.new(0, 2.9, 0), STONE, Enum.Material.Slate))
		box = tools.deco(tools.part(parent, "LanternLight", Vector3.new(1.05, 1, 1.05), frame * CFrame.new(0, 3.6, 0), LANTERN_DIM, Enum.Material.Glass))
		tools.deco(tools.part(parent, "LanternRoof", Vector3.new(2.3, 0.3, 2.3), frame * CFrame.new(0, 4.25, 0), MOSSY, Enum.Material.Slate))
		tools.deco(tools.part(parent, "LanternRoof", Vector3.new(1.3, 0.35, 1.3), frame * CFrame.new(0, 4.55, 0) * CFrame.Angles(0, math.rad(45), 0), MOSSY, Enum.Material.Slate))
		ball(tools, parent, "LanternJewel", 0.55, (frame * CFrame.new(0, 4.95, 0)).Position, STONE, Enum.Material.Slate)
	end
	tools.nightLight(box, LANTERN_LIT, LANTERN_DIM, "Glass")
	if lit then
		pointLight(box, 20, 1.1)
	end
end

-- A cherry tree in blossom at `at`: a leaning trunk (solid), three branches, a wide pink crown of four balls, its petals
-- on the ground under it; `falling`: petals drift down from it.
local function cherry(tools: Tools, parent: Instance, at: Vector3, rng: Random, falling: boolean)
	local lean = rng:NextNumber(0, 2 * math.pi)
	local trunkTop = at + Vector3.new(math.cos(lean) * 0.5, 3.4, math.sin(lean) * 0.5)
	cylinder(tools, parent, "Trunk", 3.5, 1.05, CFrame.lookAt((at + trunkTop) / 2, trunkTop) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(78, 58, 52), Enum.Material.Wood)
	local shade = BLOSSOMS[rng:NextInteger(1, #BLOSSOMS)]
	local first = rng:NextNumber(0, 2 * math.pi)
	for n = 0, 2 do
		local angle = first + n * 2 * math.pi / 3 + rng:NextNumber(-0.3, 0.3)
		local reach = rng:NextNumber(2.6, 3.4)
		local tip = trunkTop + Vector3.new(math.cos(angle) * reach, rng:NextNumber(2, 2.8), math.sin(angle) * reach)
		tools.deco(cylinder(tools, parent, "Branch", (tip - trunkTop).Magnitude, 0.55, CFrame.lookAt((trunkTop + tip) / 2, tip) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(84, 62, 56), Enum.Material.Wood))
		ball(tools, parent, "Blossom", rng:NextNumber(4.4, 5.4), tip + Vector3.new(0, 0.9, 0), shade:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.12)), Enum.Material.Grass)
	end
	local crown = ball(tools, parent, "Blossom", rng:NextNumber(5, 6), trunkTop + Vector3.new(0, 3.4, 0), shade, Enum.Material.Grass)
	local petals = tools.deco(cylinder(tools, parent, "Petals", 0.04, rng:NextNumber(8, 9.5), CFrame.new(at.X, WALK + 0.02, at.Z) * UPRIGHT, Color3.fromRGB(244, 186, 206), Enum.Material.SmoothPlastic))
	petals.Transparency = 0.3
	if falling then
		local drift = Instance.new("ParticleEmitter")
		drift.Name = "Petals"
		drift.Color = ColorSequence.new(Color3.fromRGB(252, 200, 216))
		drift.Size = NumberSequence.new(0.22)
		drift.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.85, 0.2), NumberSequenceKeypoint.new(1, 1) })
		drift.Lifetime = NumberRange.new(5, 7)
		drift.Rate = 3
		drift.Speed = NumberRange.new(0.3, 0.8)
		drift.SpreadAngle = Vector2.new(180, 180)
		drift.Acceleration = Vector3.new(0.4, -0.9, 0.25)
		drift.Rotation = NumberRange.new(0, 360)
		drift.RotSpeed = NumberRange.new(-60, 60)
		drift.Parent = crown
	end
end

-- A clump of bamboo at `at`: seven culms (solid), leaves high up.
local function bamboo(tools: Tools, parent: Instance, at: Vector3, rng: Random)
	local tops: { Vector3 } = {}
	for _ = 1, 7 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local out = rng:NextNumber(0.2, 1.4)
		local foot = at + Vector3.new(math.cos(angle) * out, 0, math.sin(angle) * out)
		local height = rng:NextNumber(13, 17.5)
		local tilt = rng:NextNumber(0.03, 0.09)
		local top = foot + Vector3.new(math.cos(angle) * height * tilt, height, math.sin(angle) * height * tilt)
		local green = Color3.fromRGB(rng:NextInteger(104, 132), rng:NextInteger(138, 160), rng:NextInteger(62, 80))
		cylinder(tools, parent, "Bamboo", height, rng:NextNumber(0.32, 0.46), CFrame.lookAt((foot + top) / 2, top) * CFrame.Angles(0, math.rad(90), 0), green, Enum.Material.SmoothPlastic)
		table.insert(tops, top)
	end
	for n = 1, 3 do
		local top = tops[n * 2]
		ball(tools, parent, "BambooLeaves", rng:NextNumber(3.2, 4.4), top - Vector3.new(0, rng:NextNumber(1, 2.4), 0), Color3.fromRGB(96, 140, 70), Enum.Material.Grass)
	end
end

-- A stone bench at `at` (its middle on the ground), along the way across (du, dv) it faces: a wooden seat on two stones.
local function bench(tools: Tools, parent: Instance, at: Vector3, du: number, dv: number)
	local frame = CFrame.lookAt(at, at + Vector3.new(du, 0, dv))
	for _, x in { -1.8, 1.8 } do
		tools.part(parent, "BenchStone", Vector3.new(1.2, 1.4, 1.5), frame * CFrame.new(x, 0.7, 0), STONE, Enum.Material.Slate)
	end
	tools.part(parent, "Bench", Vector3.new(5.4, 0.4, 1.8), frame * CFrame.new(0, 1.6, 0), WOOD, Enum.Material.WoodPlanks)
end

-- Builds the garden on its block (Map.Garden) into `parent` (World's Downtown folder).
function LanternGarden.build(parent: Instance, tools: Tools)
	local G = Map.Garden
	local part, deco = tools.part, tools.deco
	local folder = Instance.new("Folder")
	folder.Name = "LanternGarden"
	folder.Parent = parent
	local cx, cz = G.x, G.z
	local rng = Random.new(G.seed)
	local lawn = HALF - G.walk
	local function at(u: number, y: number, v: number): Vector3
		return Vector3.new(cx + u, y, cz + v)
	end

	-- ── The ground ──────────────────────────────────────────────────────────
	-- The sidewalk band in four pieces round a moss slab, the kerb all round.
	for _, box in { { -HALF, HALF, -HALF, -lawn }, { -HALF, HALF, lawn, HALF }, { -HALF, -lawn, -lawn, lawn }, { lawn, HALF, -lawn, lawn } } do
		local u0, u1, v0, v1 = box[1], box[2], box[3], box[4]
		part(folder, "Sidewalk", Vector3.new(u1 - u0, WALK, v1 - v0), CFrame.new(at((u0 + u1) / 2, WALK / 2, (v0 + v1) / 2)), WALK_GREY, Enum.Material.Concrete)
	end
	part(folder, "Lawn", Vector3.new(2 * lawn, WALK, 2 * lawn), CFrame.new(at(0, WALK / 2, 0)), MOSS, Enum.Material.Grass)
	require(script.Parent.Curbs).ring(folder, cx, cz)

	-- ── The paths ───────────────────────────────────────────────────────────
	-- (each a hair over the one before: no flicker where two meet; the last one under the footbridge's ramp's foot)
	local paths = table.clone(G.paths)
	local foot = Map.Footbridge.ramps.garden[#Map.Footbridge.ramps.garden]
	do
		local footU, footV = foot.bx - cx, foot.bz - cz
		local down = if foot.bz > foot.az then 1 else -1 -- (the way down its last flight, along v)
		local a, b = footV - down, footV + down * 2.5
		table.insert(paths, { u0 = footU - foot.width / 2, v0 = math.min(a, b), u1 = footU + foot.width / 2, v1 = math.max(a, b) })
	end
	for n, box in paths do
		local thick = 0.1 + n * 0.002
		deco(part(folder, "Path", Vector3.new(box.u1 - box.u0, thick, box.v1 - box.v0), CFrame.new(at((box.u0 + box.u1) / 2, WALK + thick / 2, (box.v0 + box.v1) / 2)), GRAVEL, Enum.Material.Pebble))
	end

	-- ── The hedge and the gates ─────────────────────────────────────────────
	-- Along the lawn's edge, `hedge` in from it: open at the gates and wherever the footbridge's ramp runs above.
	local line = lawn - G.hedge
	local GATE = 3.9 -- (half a gate's opening and its posts)
	for _, side in { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } } do
		local nu, nv = side[1], side[2]
		local runStart: number? = nil
		local step = 0.5
		local t = -line
		while t <= line + 1e-6 do
			local u, v = if nv ~= 0 then t else nu * line, if nv ~= 0 then nv * line else t
			local open = Map.footbridgeGap(cx + u, cz + v) < 1.4
			for _, gate in G.gates do
				if gate.nu == nu and gate.nv == nv and math.abs((if nv ~= 0 then gate.u else gate.v) - t) < GATE then
					open = true
				end
			end
			if not open and not runStart then
				runStart = t
			end
			if runStart and (open or t + step > line + 1e-6) then
				local finish = if open then t - step else t
				if finish - runStart > 0.4 then
					local mid, length = (runStart + finish) / 2, finish - runStart + 1.2
					local size = if nv ~= 0 then Vector3.new(length, 1.6, 1.2) else Vector3.new(1.2, 1.6, length)
					local where = if nv ~= 0 then at(mid, WALK + 0.8, nv * line) else at(nu * line, WALK + 0.8, mid)
					part(folder, "Hedge", size, CFrame.new(where), HEDGE, Enum.Material.Grass)
				end
				runStart = nil
			end
			t += step
		end
	end
	for _, gate in G.gates do
		-- (its frame a little in from the hedge's line: its roof's eaves stay over the lawn, not the sidewalk)
		local base = at(gate.u - gate.nu * 0.6, WALK, gate.v - gate.nv * 0.6)
		local frame = CFrame.lookAt(base, base + Vector3.new(gate.nu, 0, gate.nv)) -- (-Z: out to the street)
		for _, x in { -3.6, 3.6 } do
			part(folder, "GatePost", Vector3.new(0.8, 7.4, 0.8), frame * CFrame.new(x, 3.7, 0), DARK_WOOD, Enum.Material.Wood)
		end
		deco(part(folder, "GateTie", Vector3.new(8.4, 0.45, 0.5), frame * CFrame.new(0, 5.4, 0), DARK_WOOD, Enum.Material.Wood))
		deco(part(folder, "GateBeam", Vector3.new(10.2, 0.55, 0.9), frame * CFrame.new(0, 7.65, 0), DARK_WOOD, Enum.Material.Wood))
		for _, s in { -1, 1 } do
			deco(part(folder, "GateRoof", Vector3.new(10.8, 0.25, 1.35), frame * CFrame.new(0, 8.22, s * 0.52) * CFrame.Angles(s * math.rad(30), 0, 0), TILES, Enum.Material.Slate))
		end
		deco(part(folder, "GateRidge", Vector3.new(11, 0.22, 0.32), frame * CFrame.new(0, 8.6, 0), TILES:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Slate))
		tools.sign(folder, `{string.upper(G.name)}  SAFE ZONE`, Vector3.new(6.2, 1.3, 0.25), frame * CFrame.new(0, 6.45, -0.32), Color3.new(1, 1, 1), nil, G.id, 1.3)
		deco(part(folder, "Threshold", Vector3.new(4.6, 0.14, 1.6), frame * CFrame.new(0, 0.07, 0), STONE, Enum.Material.Slate))
	end

	-- ── The pond ────────────────────────────────────────────────────────────
	-- Its bed and its water, disc by disc (each a hair over the last), koi under the surface, lotus pads on it.
	local top = WALK + G.water
	for n, disc in G.pond do
		deco(cylinder(tools, folder, "PondBed", 0.04, 2 * disc.r, CFrame.new(at(disc.u, WALK + 0.02 + n * 0.003, disc.v)) * UPRIGHT, POND_BED, Enum.Material.Slate))
		local water = deco(cylinder(tools, folder, "PondWater", G.water - 0.04, 2 * disc.r, CFrame.new(at(disc.u, WALK + 0.04 + (G.water - 0.04) / 2 + n * 0.003, disc.v)) * UPRIGHT, WATER, Enum.Material.Glass))
		water.Transparency = 0.35
	end
	local function inPond(u: number, v: number, margin: number): boolean
		for _, disc in G.pond do
			if (u - disc.u) ^ 2 + (v - disc.v) ^ 2 < (disc.r - margin) ^ 2 then
				return true
			end
		end
		return false
	end
	local fish = 0
	local tries = 0
	while fish < 10 and tries < 200 do
		tries += 1
		local disc = G.pond[rng:NextInteger(1, #G.pond)]
		local angle = rng:NextNumber(0, 2 * math.pi)
		local r = rng:NextNumber(0, disc.r - 2)
		local u, v = disc.u + math.cos(angle) * r, disc.v + math.sin(angle) * r
		if not inPond(u, v, 1.6) or math.abs(u - G.stones.u) < 2 or math.abs(u - G.planks.u) < 2.5 then
			continue
		end
		fish += 1
		local heading = CFrame.new(at(u, WALK + 0.24, v)) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0)
		local color = KOI[(fish - 1) % #KOI + 1]
		deco(cylinder(tools, folder, "Koi", 1.3, 0.42, heading * CFrame.Angles(0, math.rad(90), 0), color, Enum.Material.SmoothPlastic))
		deco(part(folder, "KoiTail", Vector3.new(0.06, 0.45, 0.45), heading * CFrame.new(0, 0, 0.82) * CFrame.Angles(math.rad(45), 0, 0), color, Enum.Material.SmoothPlastic))
	end
	for n = 1, 6 do
		local disc = G.pond[(n - 1) % #G.pond + 1]
		local angle = rng:NextNumber(0, 2 * math.pi)
		local r = rng:NextNumber(disc.r * 0.35, disc.r - 1.6)
		local u, v = disc.u + math.cos(angle) * r, disc.v + math.sin(angle) * r
		if math.abs(u - G.stones.u) < 2.2 or math.abs(u - G.planks.u) < 2.6 then
			continue
		end
		deco(cylinder(tools, folder, "LotusPad", 0.05, rng:NextNumber(1.4, 2), CFrame.new(at(u, top + 0.03, v)) * UPRIGHT, Color3.fromRGB(72, 124, 60), Enum.Material.Grass))
		if n % 3 == 1 then
			ball(tools, folder, "LotusFlower", 0.6, at(u + 0.3, top + 0.3, v), Color3.fromRGB(244, 168, 196), Enum.Material.SmoothPlastic)
		end
	end
	-- The stepping stones (the two on the shores lower: a step up from the ground) and the zig-zag plank bridge, both
	-- solid; the shore's rocks leave room for them.
	local S = G.stones
	local ends: { Vector3 } = { Vector3.new(S.u, 0, S.v0), Vector3.new(S.u, 0, S.v1), Vector3.new(G.planks.u, 0, G.planks.v0), Vector3.new(G.planks.u, 0, G.planks.v1) }
	for n = 0, S.count - 1 do
		local v = S.v0 + (S.v1 - S.v0) * n / (S.count - 1)
		local shore = n == 0 or n == S.count - 1
		local height = if shore then 0.45 else 0.85
		local u = S.u + (if shore then 0 else rng:NextNumber(-0.4, 0.4))
		cylinder(tools, folder, "SteppingStone", height, rng:NextNumber(2.2, 2.6), CFrame.new(at(u, WALK + height / 2, v)) * UPRIGHT, STONE, Enum.Material.Slate)
	end
	do
		local P = G.planks
		local length = (P.v1 - P.v0) / 3
		for n = 0, 2 do
			local v = P.v0 + length * (n + 0.5)
			local u = P.u + (if n % 2 == 0 then -0.8 else 0.8)
			part(folder, "Plank", Vector3.new(1.8, 0.3, math.abs(length) + 0.6), CFrame.new(at(u, WALK + 0.8, v)), WOOD, Enum.Material.WoodPlanks)
			for _, s in { -1, 1 } do
				deco(cylinder(tools, folder, "PlankPost", 0.65, 0.35, CFrame.new(at(u, WALK + 0.33, v + s * (math.abs(length) / 2 - 0.2))) * UPRIGHT, DARK_WOOD, Enum.Material.Wood))
			end
		end
		for _, v in { P.v0 + (if P.v0 > P.v1 then 1.3 else -1.3), P.v1 + (if P.v0 > P.v1 then -1.3 else 1.3) } do
			cylinder(tools, folder, "SteppingStone", 0.45, 2.2, CFrame.new(at(P.u - 0.8, WALK + 0.225, v)) * UPRIGHT, STONE, Enum.Material.Slate)
		end
	end
	-- The rocks round the shore: along every disc's edge where no other disc's water is, every 3 studs or so, not where
	-- the stones and the planks come ashore nor at the waterfall.
	local fall = G.waterfall
	for _, disc in G.pond do
		local around = 2 * math.pi * (disc.r + 0.9)
		local count = math.floor(around / 3)
		local first = rng:NextNumber(0, 2 * math.pi)
		for n = 0, count - 1 do
			local angle = first + n * 2 * math.pi / count
			local u, v = disc.u + math.cos(angle) * (disc.r + 0.8), disc.v + math.sin(angle) * (disc.r + 0.8)
			local free = (u - fall.u) ^ 2 + (v - fall.v - 2) ^ 2 > 4.6 ^ 2
			for _, other in G.pond do
				free = free and (other == disc or (u - other.u) ^ 2 + (v - other.v) ^ 2 > (other.r + 0.6) ^ 2)
			end
			for _, e in ends do
				free = free and (u - e.X) ^ 2 + (v - e.Z) ^ 2 > 2.7 ^ 2
			end
			if free then
				local r = rock(tools, folder, at(u, WALK, v), Vector3.new(rng:NextNumber(1.7, 2.6), rng:NextNumber(0.6, 0.95), rng:NextNumber(1.3, 2)), rng, STONE_DARK:Lerp(STONE, 0.4))
				r.Name = "ShoreRock"
			end
		end
	end
	-- The waterfall: a pile of rocks on the north shore, the water over its face into a short run to the pond.
	do
		local w = at(fall.u, WALK, fall.v)
		rock(tools, folder, w + Vector3.new(0, 0, -2.6), Vector3.new(6.4, 6, 3.8), rng, STONE_DARK, 0)
		rock(tools, folder, w + Vector3.new(-2.8, 0, 0.4), Vector3.new(2.6, 3.4, 2.6), rng, STONE_DARK, 0.3)
		rock(tools, folder, w + Vector3.new(2.9, 0, 0.3), Vector3.new(2.8, 2.8, 2.6), rng, STONE_DARK, -0.3)
		rock(tools, folder, w + Vector3.new(-2.2, 0, 2.6), Vector3.new(1.8, 1.2, 1.6), rng, STONE_DARK:Lerp(STONE, 0.4))
		rock(tools, folder, w + Vector3.new(2.3, 0, 2.7), Vector3.new(1.7, 1.1, 1.5), rng, STONE_DARK:Lerp(STONE, 0.4))
		local face = w + Vector3.new(0, 0, -0.62)
		local sheet = deco(part(folder, "Waterfall", Vector3.new(2.2, 5.3, 0.22), CFrame.new(face + Vector3.new(0, G.water + 5.3 / 2, 0)), Color3.fromRGB(176, 214, 230), Enum.Material.Glass))
		sheet.Transparency = 0.45
		local run = deco(part(folder, "WaterRun", Vector3.new(2.6, G.water - 0.04, 4.2), CFrame.new(face + Vector3.new(0, 0.04 + (G.water - 0.04) / 2, 2.1)), WATER, Enum.Material.Glass))
		run.Transparency = 0.35
		local foam = deco(cylinder(tools, folder, "Foam", 0.06, 2.6, CFrame.new(face + Vector3.new(0, G.water + 0.03, 0.9)) * UPRIGHT, Color3.fromRGB(240, 246, 248), Enum.Material.SmoothPlastic))
		foam.Transparency = 0.25
		local mist = Instance.new("ParticleEmitter")
		mist.Name = "Mist"
		mist.Color = ColorSequence.new(Color3.fromRGB(236, 246, 252))
		mist.LightEmission = 0.2
		mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1.1) })
		mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		mist.Lifetime = NumberRange.new(0.8, 1.3)
		mist.Rate = 18
		mist.Speed = NumberRange.new(1, 2.4)
		mist.SpreadAngle = Vector2.new(60, 60)
		mist.Acceleration = Vector3.new(0, 1.2, 0)
		mist.Parent = foam
	end

	-- ── The tea pavilion ────────────────────────────────────────────────────
	-- An open floor on four posts under a roof with flared eaves (a shallow skirt round a steep pyramid) whose corners
	-- turn up; its step to the south, a low table and a bench inside, a paper lantern hanging from the roof.
	do
		local P = G.pavilion
		local frame = CFrame.lookAt(at(P.u, WALK, P.v), at(P.u, WALK, P.v - 1)) -- (+Z: the step, to the south)
		local size, floorTop = P.size, 0.8
		part(folder, "PavilionFloor", Vector3.new(size, floorTop, size), frame * CFrame.new(0, floorTop / 2, 0), WOOD, Enum.Material.WoodPlanks)
		part(folder, "PavilionStep", Vector3.new(4.4, 0.4, 1.4), frame * CFrame.new(0, 0.2, size / 2 + 0.7), WOOD, Enum.Material.WoodPlanks)
		local corner = size / 2 - 0.8
		local eaves = floorTop + 7.2
		for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			part(folder, "PavilionPost", Vector3.new(0.7, 7.2, 0.7), frame * CFrame.new(c[1] * corner, floorTop + 3.6, c[2] * corner), DARK_WOOD, Enum.Material.Wood)
		end
		local outer, inner, lift = size / 2 + 1.9, size / 2 - 1.2, 1.1
		for k = 0, 3 do
			local turn = frame * CFrame.Angles(0, k * math.pi / 2, 0)
			deco(part(folder, "PavilionBeam", Vector3.new(size - 0.6, 0.55, 0.5), turn * CFrame.new(0, eaves - 0.25, -corner), DARK_WOOD, Enum.Material.Wood))
			-- the skirt: a shallow plate from the eave's edge up to the pyramid's foot
			local depth = outer - inner
			local width = math.sqrt(depth * depth + lift * lift)
			local pitch = math.atan(lift / depth)
			deco(part(folder, "PavilionEave", Vector3.new(2 * outer, 0.28, width), turn * CFrame.new(0, eaves + lift / 2, -(outer + inner) / 2) * CFrame.Angles(-pitch, 0, 0), TILES, Enum.Material.Slate))
			-- the pyramid: four corner wedges (each one's apex over its +X, -Z corner, at the roof's top)
			local roof = Instance.new("CornerWedgePart")
			roof.Name = "PavilionRoof"
			roof.Anchored = true
			roof.CanCollide = false
			roof.CanQuery = false
			roof.CanTouch = false
			roof.Size = Vector3.new(inner, 3.4, inner)
			roof.CFrame = turn * CFrame.new(-inner / 2, eaves + lift + 1.7, inner / 2)
			roof.Color = TILES
			roof.Material = Enum.Material.Slate
			roof.Parent = folder
			-- the corner turned up
			local tip = turn * CFrame.new(outer - 0.6, eaves + 0.15, -(outer - 0.6)) * CFrame.Angles(0, math.rad(-45), 0) * CFrame.Angles(math.rad(28), 0, 0)
			deco(part(folder, "PavilionTip", Vector3.new(0.8, 0.3, 2.4), tip * CFrame.new(0, 0, -0.6), TILES, Enum.Material.Slate))
		end
		cylinder(tools, folder, "PavilionFinial", 1.1, 0.5, frame * CFrame.new(0, eaves + lift + 3.85, 0) * UPRIGHT, Color3.fromRGB(150, 120, 70), Enum.Material.Metal)
		ball(tools, folder, "PavilionFinial", 0.75, (frame * CFrame.new(0, eaves + lift + 4.55, 0)).Position, Color3.fromRGB(176, 140, 76), Enum.Material.Metal)
		part(folder, "PavilionTable", Vector3.new(2.6, 0.9, 1.8), frame * CFrame.new(0, floorTop + 0.45, 0.6), DARK_WOOD, Enum.Material.Wood)
		part(folder, "PavilionBench", Vector3.new(8, 0.4, 1.4), frame * CFrame.new(0, floorTop + 1.5, -corner + 1.2), WOOD, Enum.Material.WoodPlanks)
		for _, x in { -3, 3 } do
			deco(part(folder, "PavilionBenchLeg", Vector3.new(0.4, 1.3, 1.2), frame * CFrame.new(x, floorTop + 0.65, -corner + 1.2), DARK_WOOD, Enum.Material.Wood))
		end
		deco(part(folder, "LanternCord", Vector3.new(0.08, 1.4, 0.08), frame * CFrame.new(0, eaves + 0.3, 0), DARK_WOOD, Enum.Material.Wood))
		local lantern = deco(cylinder(tools, folder, "PaperLantern", 1.5, 1.2, frame * CFrame.new(0, eaves - 1.15, 0) * UPRIGHT, LANTERN_DIM, Enum.Material.SmoothPlastic))
		tools.nightLight(lantern, LANTERN_LIT, LANTERN_DIM, "SmoothPlastic")
		pointLight(lantern, 22, 1.2)
	end

	-- ── The raked gravel ────────────────────────────────────────────────────
	-- A bed of white gravel in a dark stone edge, its lines raked along it, rings raked round its big stones.
	do
		local R = G.gravel
		local w, d = R.u1 - R.u0, R.v1 - R.v0
		local mu, mv = (R.u0 + R.u1) / 2, (R.v0 + R.v1) / 2
		deco(part(folder, "RakedGravel", Vector3.new(w, 0.1, d), CFrame.new(at(mu, WALK + 0.05, mv)), RAKED, Enum.Material.Sand))
		for _, e in { { mu, R.v0, w + 0.8, 0.4 }, { mu, R.v1, w + 0.8, 0.4 }, { R.u0, mv, 0.4, d }, { R.u1, mv, 0.4, d } } do
			deco(part(folder, "GravelEdge", Vector3.new(e[3], 0.3, e[4]), CFrame.new(at(e[1], WALK + 0.15, e[2])), STONE_DARK, Enum.Material.Slate))
		end
		for k = 1, 6 do
			deco(part(folder, "RakeLine", Vector3.new(w - 0.6, 0.02, 0.18), CFrame.new(at(mu, WALK + 0.11, R.v0 + d * k / 7)), RAKE_LINE, Enum.Material.Sand))
		end
		for _, stone in G.rocks do
			local size = stone.size or 2
			for ring, diameter in { size * 2.6, size * 1.9 } do
				local y = WALK + 0.11 + ring * 0.02
				deco(cylinder(tools, folder, "RakeRing", 0.02, diameter, CFrame.new(at(stone.u, y, stone.v)) * UPRIGHT, RAKE_LINE, Enum.Material.Sand))
				deco(cylinder(tools, folder, "RakeRing", 0.02, diameter - 0.36, CFrame.new(at(stone.u, y + 0.01, stone.v)) * UPRIGHT, RAKED, Enum.Material.Sand))
			end
			rock(tools, folder, at(stone.u, WALK, stone.v), Vector3.new(size, size * 0.85, size * 0.75), rng, STONE_DARK)
		end
	end

	-- ── Lanterns, trees, bamboo, shrubs, benches, the basin ─────────────────
	for n, lantern in G.lanterns do
		stoneLantern(tools, folder, at(lantern.u, WALK, lantern.v), lantern.kind, lantern.lit, n * 0.7)
	end
	for n, spot in G.cherries do
		cherry(tools, folder, at(spot.u, WALK, spot.v), rng, n % 2 == 1)
	end
	for _, spot in G.bamboo do
		bamboo(tools, folder, at(spot.u, WALK, spot.v), rng)
	end
	for _, spot in G.shrubs do
		local size = spot.size or 2.4
		ball(tools, folder, "Azalea", size, at(spot.u, WALK + size * 0.38, spot.v), AZALEAS[rng:NextInteger(1, #AZALEAS)], Enum.Material.Grass)
	end
	for _, b in G.benches do
		bench(tools, folder, at(b.u, WALK, b.v), b.du, b.dv)
	end
	do
		local basin = at(G.basin.u, WALK, G.basin.v)
		cylinder(tools, folder, "Basin", 1, 1.9, CFrame.new(basin + Vector3.new(0, 0.5, 0)) * UPRIGHT, STONE, Enum.Material.Slate)
		deco(cylinder(tools, folder, "BasinWater", 0.05, 1.3, CFrame.new(basin + Vector3.new(0, 1.01, 0)) * UPRIGHT, WATER, Enum.Material.Glass))
		cylinder(tools, folder, "SpoutPost", 1.8, 0.3, CFrame.new(basin + Vector3.new(0, 0.9, -1.5)) * UPRIGHT, Color3.fromRGB(120, 146, 72), Enum.Material.SmoothPlastic)
		local a, b = basin + Vector3.new(0, 1.6, -1.5), basin + Vector3.new(0, 1.35, -0.4)
		deco(cylinder(tools, folder, "Spout", (b - a).Magnitude, 0.22, CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(128, 154, 76), Enum.Material.SmoothPlastic))
	end
end

return LanternGarden
