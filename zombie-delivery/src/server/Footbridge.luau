--!strict
-- 6.12.15, the footbridge over Bone St (Map.Footbridge): an arched timber bridge mid-block between the Central Park
-- (south, server/CentralPark.luau) and the Lantern Garden (north, server/LanternGarden.luau). server/World.luau builds it
-- as a piece of the world (Footbridge.build, with World's helpers handed over: no new top-level locals there, the -O0
-- register limit).
--
--   the span     from a landing just inside the garden's lawn to one just inside the park's, over both sidewalks and
--                the road (nothing of it stands on them): a cambered plank deck on two beams (their underside at least
--                the tallest vehicle + 3 over the walk: Map.Footbridge), vermilion railings with brass caps, two timber
--                arches over it with hangers down to the beams, three ties across the arches' tops, a red paper lantern
--                hanging from each arch's crown and a lantern on each end post
--   the ramps    from each landing (Map.Footbridge.ramps): a flight along the lawn's edge, a flat corner landing, a
--                flight down the side to the ground, no steps (a bike or a scooter rolls over it), as steep as the
--                curb at most; railings both sides, timber posts under them, a lantern on the corner landing's
--                outer post and a lantern post at the park's foot (the garden's foot has its stone lantern)
-- The decks, the beams, the railings and the posts that stand on the ground are solid (you walk on it, you do not fall
-- off it, nothing drives through its posts); the arches, the hangers, the ties, the rail posts, the caps and the
-- lanterns are decoration (no collision, no ray hits). About 270 parts, two lights.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Map)

local Footbridge = {}

export type Tools = {
	part: (parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?) -> Part,
	deco: (p: Part) -> Part,
	sign: (parent: Instance, text: string, size: Vector3, cframe: CFrame, color: Color3, background: Color3?, art: string?, artHeight: number?) -> (),
	nightLight: (item: Instance, lit: Color3?, dim: Color3?, dimMaterial: string?) -> (),
}

local WALK = Map.WalkTop
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder standing up

local PLANKS = Color3.fromRGB(150, 110, 74)
local TIMBER = Color3.fromRGB(86, 60, 42)
local VERMILION = Color3.fromRGB(196, 62, 42)
local BRASS = Color3.fromRGB(206, 166, 74)
local LANTERN_LIT = Color3.fromRGB(255, 178, 96)
local PAPER = Color3.fromRGB(214, 64, 46)
local GLASS_DIM = Color3.fromRGB(232, 222, 196)

local SLAB = 0.5 -- the planks' thickness
local KICK = 1 -- the kick board's height over the deck (no wheel rolls off)

local function pointLight(parent: Instance, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = Color3.fromRGB(255, 196, 130)
	l.Shadows = false
	l.Parent = parent
end

-- A rail post standing on the deck at `at` (its foot), up to the railing's top and a little over, with a brass cap
-- (`cap`) or a lantern on top (`lantern`: a glass box under a dark roof; it glows at night).
local function railPost(tools: Tools, parent: Instance, at: Vector3, cap: boolean, lantern: boolean)
	local F = Map.Footbridge
	local height = F.rail + 0.4
	tools.deco(tools.part(parent, "RailPost", Vector3.new(0.45, height, 0.45), CFrame.new(at + Vector3.new(0, height / 2, 0)), VERMILION, Enum.Material.Wood))
	if lantern then
		local box = tools.deco(tools.part(parent, "PostLantern", Vector3.new(0.9, 1.1, 0.9), CFrame.new(at + Vector3.new(0, height + 0.55, 0)), GLASS_DIM, Enum.Material.Glass))
		tools.nightLight(box, LANTERN_LIT, GLASS_DIM, "Glass")
		tools.deco(tools.part(parent, "PostLanternRoof", Vector3.new(1.2, 0.25, 1.2), CFrame.new(at + Vector3.new(0, height + 1.22, 0)), TIMBER, Enum.Material.Wood))
	elseif cap then
		local ball = tools.deco(tools.part(parent, "RailCap", Vector3.new(0.6, 0.6, 0.6), CFrame.new(at + Vector3.new(0, height + 0.25, 0)), BRASS, Enum.Material.Metal))
		ball.Shape = Enum.PartType.Ball
	end
end

-- A straight piece of deck from a to b (the middle of its top at both ends): the planks, a beam under each edge (their
-- underside `thick` under the top), and on each side a kick board and the railing over the beam. It overlaps a hair at
-- both ends (no seam a wheel catches).
local function deck(tools: Tools, parent: Instance, a: Vector3, b: Vector3, width: number)
	local F = Map.Footbridge
	local length = (b - a).Magnitude
	local frame = CFrame.lookAt((a + b) / 2, b)
	tools.part(parent, "Deck", Vector3.new(width, SLAB, length + 0.1), frame * CFrame.new(0, -SLAB / 2, 0), PLANKS, Enum.Material.WoodPlanks)
	local edge = width / 2 + F.beam / 2
	for _, side in { -1, 1 } do
		tools.part(parent, "Beam", Vector3.new(F.beam, F.thick + 0.1, length + 0.1), frame * CFrame.new(side * edge, 0.1 - (F.thick + 0.1) / 2, 0), TIMBER, Enum.Material.Wood)
		tools.part(parent, "KickBoard", Vector3.new(0.2, KICK - 0.1, length), frame * CFrame.new(side * edge, 0.1 + (KICK - 0.1) / 2, 0), VERMILION, Enum.Material.Wood)
		tools.part(parent, "Railing", Vector3.new(0.3, 0.3, length), frame * CFrame.new(side * edge, F.rail - 0.15, 0), VERMILION, Enum.Material.Wood)
	end
end

-- A timber post from the ground up to `top` at (x, z), solid.
local function post(tools: Tools, parent: Instance, x: number, z: number, top: number)
	local height = top - WALK
	if height > 0.5 then
		tools.part(parent, "Post", Vector3.new(0.75, height, 0.75), CFrame.new(x, WALK + height / 2, z), TIMBER, Enum.Material.Wood)
	end
end

-- A flat landing (a "landing" piece of Map.Footbridge.ramps): its planks on a timber frame, the railing on every edge
-- no deck joins (`joins`: the points where the span and the ramps meet it, on its edges), posts under it: at all four
-- corners, or (`two`) only at the two on its (+x, +z) / (-x, -z) diagonal (the park's corner path runs under the other).
local function landing(tools: Tools, parent: Instance, piece: Map.RampPiece, joins: { Vector3 }, two: boolean): { Vector3 }
	local F = Map.Footbridge
	local size, y = piece.width, piece.ya
	local cx, cz = (piece.ax + piece.bx) / 2, (piece.az + piece.bz) / 2
	local centre = Vector3.new(cx, y, cz)
	tools.part(parent, "Landing", Vector3.new(size, F.thick, size), CFrame.new(centre - Vector3.new(0, F.thick / 2, 0)), PLANKS, Enum.Material.WoodPlanks)
	local half = size / 2
	local corners: { Vector3 } = {}
	for _, d in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local mid = centre + d * half
		local joined = false
		for _, p in joins do
			if math.abs((p - mid):Dot(d)) < 0.2 and (p - mid).Magnitude < half then
				joined = true
			end
		end
		if not joined then
			local frame = CFrame.lookAt(mid - d * 0.15, mid - d * 0.15 + Vector3.new(d.Z, 0, -d.X))
			tools.part(parent, "KickBoard", Vector3.new(0.2, KICK, size), frame * CFrame.new(0, KICK / 2, 0), VERMILION, Enum.Material.Wood)
			tools.part(parent, "Railing", Vector3.new(0.3, 0.3, size), frame * CFrame.new(0, F.rail - 0.15, 0), VERMILION, Enum.Material.Wood)
		end
	end
	for _, s in { { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } } do
		local corner = Vector3.new(cx + s[1] * (half - 0.15), y, cz + s[2] * (half - 0.15))
		table.insert(corners, corner)
		if not two or s[1] == s[2] then
			post(tools, parent, cx + s[1] * (half - 0.45), cz + s[2] * (half - 0.45), y - F.thick)
		end
	end
	return corners
end

-- A sloped flight (a "ramp" piece): its deck, rail posts along it, and bents under it (two posts and a cap beam)
-- every BENT studs where it is high enough to stand on posts.
local BENT = 9
local function flight(tools: Tools, parent: Instance, piece: Map.RampPiece)
	local F = Map.Footbridge
	local a, b = Vector3.new(piece.ax, piece.ya, piece.az), Vector3.new(piece.bx, piece.yb, piece.bz)
	deck(tools, parent, a, b, piece.width)
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local run = flat.Magnitude
	local along = flat.Unit
	local across = Vector3.new(-along.Z, 0, along.X)
	local edge = piece.width / 2 + F.beam / 2
	local count = math.max(2, math.floor(run / 8.5) + 1)
	for n = 0, count - 1 do
		local t = n / (count - 1)
		local at = a:Lerp(b, t)
		for _, side in { -1, 1 } do
			railPost(tools, parent, at + across * (side * edge) + Vector3.new(0, 0.1, 0), n == count - 1, false)
		end
	end
	local t = 4
	while t < run - 2 do
		local top = piece.ya + (piece.yb - piece.ya) * t / run - F.thick
		if top - WALK < 2.5 then
			break
		end
		local at = a + along * t
		for _, side in { -1, 1 } do
			local spot = at + across * (side * (piece.width / 2 - 0.4))
			post(tools, parent, spot.X, spot.Z, top)
		end
		tools.deco(tools.part(parent, "BentCap", Vector3.new(piece.width + 1.6, 0.5, 0.7), CFrame.lookAt(Vector3.new(at.X, top - 0.25, at.Z), Vector3.new(at.X, top - 0.25, at.Z) + along), TIMBER, Enum.Material.Wood))
		t += BENT
	end
end

-- A red paper lantern hanging from `top` (its cord's top) by a cord `cord` long; `light`: a real light too.
local function paperLantern(tools: Tools, parent: Instance, top: Vector3, cord: number, light: boolean)
	tools.deco(tools.part(parent, "LanternCord", Vector3.new(0.08, cord, 0.08), CFrame.new(top - Vector3.new(0, cord / 2, 0)), TIMBER, Enum.Material.Wood))
	local body = top - Vector3.new(0, cord + 0.95, 0)
	local paper = tools.deco(tools.part(parent, "PaperLantern", Vector3.new(1.7, 1.4, 1.4), CFrame.new(body) * UPRIGHT, PAPER, Enum.Material.SmoothPlastic))
	paper.Shape = Enum.PartType.Cylinder
	tools.nightLight(paper, LANTERN_LIT, PAPER, "SmoothPlastic")
	for _, dy in { 0.95, -0.95 } do
		local cap = tools.deco(tools.part(parent, "LanternCap", Vector3.new(0.22, 0.95, 0.95), CFrame.new(body + Vector3.new(0, dy, 0)) * UPRIGHT, Color3.fromRGB(30, 28, 26), Enum.Material.Wood))
		cap.Shape = Enum.PartType.Cylinder
	end
	if light then
		pointLight(paper, 28, 1.3)
	end
end

function Footbridge.build(parent: Instance, tools: Tools)
	local F = Map.Footbridge
	local folder = Instance.new("Folder")
	folder.Name = "Footbridge"
	folder.Parent = parent
	local x = F.x
	local zm = (F.z0 + F.z1) / 2
	local half = (F.z1 - F.z0) / 2
	local edge = F.width / 2 + F.beam / 2

	-- ── The span ────────────────────────────────────────────────────────────
	-- Five straight pieces along the camber (Map.footbridgeDeck), a rail post at every joint, a lantern on the end posts.
	local SEGMENTS = 5
	for n = 0, SEGMENTS do
		local z = F.z0 + (F.z1 - F.z0) * n / SEGMENTS
		local y = Map.footbridgeDeck(z)
		if n > 0 then
			local z0 = F.z0 + (F.z1 - F.z0) * (n - 1) / SEGMENTS
			deck(tools, folder, Vector3.new(x, Map.footbridgeDeck(z0), z0), Vector3.new(x, y, z), F.width)
		end
		for _, side in { -1, 1 } do
			railPost(tools, folder, Vector3.new(x + side * edge, y + 0.1, z), true, n == 0 or n == SEGMENTS)
		end
	end

	-- The arches over it: a parabola on each side springing from the span's ends, hangers down to the beams, ties
	-- across their tops; a paper lantern from each crown.
	local ARCH = 10
	local archX = edge + 0.55
	local function archY(z: number): number
		local t = math.clamp((z - zm) / half, -1, 1)
		return F.deck - 0.6 + (F.camber + F.arch + 0.6) * (1 - t * t) -- (springing from the beams at the span's ends)
	end
	for _, side in { -1, 1 } do
		for n = 1, ARCH do
			local za, zb = F.z0 + (F.z1 - F.z0) * (n - 1) / ARCH, F.z0 + (F.z1 - F.z0) * n / ARCH
			local a, b = Vector3.new(x + side * archX, archY(za), za), Vector3.new(x + side * archX, archY(zb), zb)
			tools.deco(tools.part(folder, "Arch", Vector3.new(0.7, 0.9, (b - a).Magnitude + 0.25), CFrame.lookAt((a + b) / 2, b), TIMBER, Enum.Material.Wood))
			if n < ARCH then
				local foot = Map.footbridgeDeck(zb) + 0.1
				local top = archY(zb) - 0.45
				tools.deco(tools.part(folder, "Hanger", Vector3.new(0.22, top - foot, 0.22), CFrame.new(x + side * archX, (top + foot) / 2, zb), TIMBER, Enum.Material.Wood))
			end
		end
		paperLantern(tools, folder, Vector3.new(x + side * archX, archY(zm) - 0.45, zm), 0.9, side == -1)
	end
	for _, t in { -0.25, 0, 0.25 } do -- (a head's height and more over the deck: nobody walks into them)
		local z = zm + t * half
		tools.deco(tools.part(folder, "ArchTie", Vector3.new(2 * archX + 0.7, 0.45, 0.5), CFrame.new(x, archY(z) + 0.2, z), TIMBER, Enum.Material.Wood))
	end

	-- ── The landings and the ramps ──────────────────────────────────────────
	for _, entry in { { name = "park", ramp = F.ramps.park }, { name = "garden", ramp = F.ramps.garden } } do
		local name, ramp = entry.name, entry.ramp
		for n, piece in ramp do
			if piece.kind == "landing" then
				-- where the span and the flights before and after it meet its edges
				local joins: { Vector3 } = {}
				if n == 1 then
					local z = if math.abs(piece.az - F.z1) < 1e-6 then F.z1 else F.z0
					table.insert(joins, Vector3.new(x, piece.ya, z))
				end
				for _, k in { n - 1, n + 1 } do
					local other = ramp[k]
					if other then
						table.insert(joins, Vector3.new(other.ax, piece.ya, other.az))
						table.insert(joins, Vector3.new(other.bx, piece.ya, other.bz))
					end
				end
				local corners = landing(tools, folder, piece, joins, n > 1)
				-- the corner landing's outer corner (the farthest from where the flights join it) carries a lantern
				if n > 1 then
					local far, farthest = corners[1], -1
					for _, corner in corners do
						local d = 0
						for _, p in joins do
							d += (corner - p).Magnitude
						end
						if d > farthest then
							far, farthest = corner, d
						end
					end
					railPost(tools, folder, far, false, true)
				end
			else
				flight(tools, folder, piece)
			end
		end
		-- the park's foot: a lantern post on the lawn beside it (the garden's foot has its own stone lantern)
		if name == "park" then
			local last = ramp[#ramp]
			local along = Vector3.new(last.bx - last.ax, 0, last.bz - last.az).Unit
			local across = Vector3.new(-along.Z, 0, along.X)
			local side = if across:Dot(Vector3.new(F.x - last.bx, 0, 0)) > 0 then 1 else -1 -- (toward the park's middle)
			local spot = Vector3.new(last.bx, WALK, last.bz) - along * 1.5 + across * (side * (last.width / 2 + 1.6))
			tools.part(folder, "LanternPost", Vector3.new(0.5, 6.4, 0.5), CFrame.new(spot + Vector3.new(0, 3.2, 0)), TIMBER, Enum.Material.Wood)
			local box = tools.deco(tools.part(folder, "PostLantern", Vector3.new(1, 1.3, 1), CFrame.new(spot + Vector3.new(0, 7.05, 0)), GLASS_DIM, Enum.Material.Glass))
			tools.nightLight(box, LANTERN_LIT, GLASS_DIM, "Glass")
			pointLight(box, 24, 1.1)
			tools.deco(tools.part(folder, "PostLanternRoof", Vector3.new(1.6, 0.3, 1.6), CFrame.new(spot + Vector3.new(0, 7.85, 0)), TIMBER, Enum.Material.Wood))
		end
	end
end

return Footbridge
