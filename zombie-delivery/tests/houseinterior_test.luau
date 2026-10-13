-- 7.0 prototype, the moving: the real server/HouseInterior.luau builds house plans (shared/HouseLayout.luau) on the
-- recorder (tools/fixtures/item-mock.luau) in the standalone Luau CLI: an interior stays within its part budget
-- (Config.Furniture.InteriorMaxParts, its furniture included) and a modest number of lights, everything anchored (a
-- piece's looks held by welds to its anchored Root), every spot a piece of the right kind at the right place with its
-- Spot and Star, the house closed (walls, a ceiling, ground under it all, the porch's daylight wall), the EXIT sign
-- over the front door; the slots lie far off the map (Map.Bounds) and never overlap; destroy takes it down. 7.x alpine:
-- the chalet's looks built (beams, wainscot, one plank floor, the Kachelofen, the corner bench and its shelf, lace, the
-- painted front door, antlers, pictures, rag rugs), warm lights, the same plan the same interior, seeds 10-60 in budget.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local M = require("./ItemMock")
local Config = require("./Config")
local Map = require("./Map")
local HouseLayout = require("./HouseLayout")
local HouseInterior = require("./HouseInterior")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function finite(x: number): boolean
	return x == x and x > -math.huge and x < math.huge
end

local T = Config.Furniture

-- ── The slots ─────────────────────────────────────────────────────────────────
do
	local b = Map.Bounds
	local far, apart = true, true
	local biggest = 0
	for seed = 1, 20 do
		local plan = HouseLayout.plan(seed, "house")
		biggest = math.max(biggest, plan.size.X, plan.size.Z)
	end
	for index = 0, 15 do
		local p = HouseInterior.slot(index).Position
		-- far past the map's edge (and its sea and hills), well above the water
		far = far and (p.X > b.x1 + 3000 or p.X < b.x0 - 3000 or p.Z > b.z1 + 3000 or p.Z < b.z0 - 3000) and p.Y > 100
		if index > 0 then
			local q = HouseInterior.slot(index - 1).Position
			local gap = math.sqrt((p.X - q.X) ^ 2 + (p.Z - q.Z) ^ 2)
			apart = apart and gap >= biggest + 2 * T.Ground.Margin + 100
		end
	end
	check("the interiors' slots lie far off the map, above the water", far)
	check(`the slots never overlap (the biggest house {math.floor(biggest)} studs)`, apart)
end

-- ── Every interior ─────────────────────────────────────────────────────────────
local mostParts, mostLights = 0, 0
local A = T.Alpine
-- (7.x alpine: seeds 4, 174 and 647 are the busiest of the first 1000: 614, 613 and 612 parts; the average is about
-- 558 (it was 539 before the chalet); 409 was the busiest before. 8.0 SANDBOX, with the collectibles: 174, 757 and 151
-- the busiest, 688, 682 and 681 parts; on average 606)
for _, seed in { 1, 2, 3, 4, 5, 6, 7, 8, 9, 174, 409, 647, 1955 } do -- (7.0 review: 1955 is Marge's House, Config.Moving.Contracts)
	local plan = HouseLayout.plan(seed, "house")
	local origin = HouseInterior.slot(seed)
	local ok, model, pieces = pcall(HouseInterior.build, plan, origin)
	local tag = `seed {seed}`
	if not ok then
		check(`{tag}: builds`, false, model)
		continue
	end
	local parts, lights, unsound, loose = 0, 0, {}, {}
	local o = origin.Position
	local lo, hi = M.Vector3.new(math.huge, math.huge, math.huge), M.Vector3.new(-math.huge, -math.huge, -math.huge)
	local ground: any = nil
	local exitSign, daylight = false, false
	for _, obj in model:GetDescendants() do
		if obj.ClassName == "PointLight" or obj.ClassName == "SurfaceLight" or obj.ClassName == "SpotLight" then
			lights += 1
			check(`{tag}: a light without shadows, modest`, obj.Shadows ~= true and (obj.Range or 0) <= 40 and (obj.Brightness or 0) <= 3)
		end
		if not obj:IsA("BasePart") then
			continue
		end
		parts += 1
		local s, p = obj.Size, obj.CFrame.Position
		if not (finite(s.X) and finite(s.Y) and finite(s.Z) and s.X > 0 and s.Y > 0 and s.Z > 0 and finite(p.X) and finite(p.Y) and finite(p.Z)) then
			table.insert(unsound, obj.Name)
		end
		lo = M.Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
		hi = M.Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
		if obj.Name == "Ground" then
			ground = obj
		elseif obj.Name == "ExitSign" then
			exitSign = true
		elseif obj.Name == "Daylight" then
			daylight = obj.CanCollide == true
		end
		-- anchored, or a piece's look welded to its anchored Root
		if obj.Anchored ~= true then
			local piece = obj.Parent
			local root = piece and piece.PrimaryPart
			local welded = false
			for _, w in obj:GetChildren() do
				welded = welded or (w.ClassName == "WeldConstraint" and w.Part0 == root and w.Part1 == obj)
			end
			if not (root and root.Anchored == true and welded) then
				table.insert(loose, obj.Name)
			end
		end
	end
	mostParts, mostLights = math.max(mostParts, parts), math.max(mostLights, lights)
	check(`{tag}: {parts} parts (at most {T.InteriorMaxParts}, {#plan.spots} pieces), {lights} lights (at most 12)`, parts <= T.InteriorMaxParts and lights >= 8 and lights <= 12)
	check(`{tag}: every part sound and anchored (a piece's looks welded to its anchored Root)`, #unsound == 0 and #loose == 0,
		table.concat(unsound, ",") .. " / " .. table.concat(loose, ","))
	check(`{tag}: built at its slot, within the house's box`, lo.X >= o.X + plan.min.X - 12 and hi.X <= o.X + plan.max.X + 12 and lo.Z >= o.Z + plan.min.Z - 12
		and hi.Z <= o.Z + plan.max.Z + 12 and lo.Y >= o.Y - T.Ground.Depth - 1 and hi.Y <= o.Y + plan.ceiling + 1)
	local g = ground and ground.Size
	local gp = ground and ground.CFrame.Position
	check(`{tag}: ground under all of it, below the floor`, ground ~= nil and gp.Y + g.Y / 2 <= o.Y + 1e-6 and gp.X - g.X / 2 <= o.X + plan.min.X - T.Ground.Margin + 1e-6
		and gp.X + g.X / 2 >= o.X + plan.max.X + T.Ground.Margin - 1e-6 and gp.Z - g.Z / 2 <= o.Z + plan.min.Z - T.Ground.Margin + 1e-6
		and gp.Z + g.Z / 2 >= o.Z + plan.max.Z + T.Ground.Margin - 1e-6 and ground.CanCollide == true)
	check(`{tag}: the EXIT sign over the front door, a daylight wall beyond the porch`, exitSign and daylight)
	local walls, ceiling = 0, false
	for _, obj in model:GetDescendants() do
		if obj.Name == "Wall" and obj.CanCollide == true then
			walls += 1
		elseif obj.Name == "Ceiling" and obj.CanCollide == true then
			ceiling = obj.Size.X >= plan.size.X - 1e-6 and obj.Size.Z >= plan.size.Z - 1e-6
		end
	end
	check(`{tag}: walls ({walls}) and a ceiling over the whole house`, walls >= #plan.rooms * 4 and ceiling)

	-- the pieces: one at every spot, the right kind, where the spot says, marked
	local bad = {}
	local count = 0
	for _, spot in plan.spots do
		local piece = pieces[spot.id]
		local root = piece and piece.PrimaryPart
		local want = (origin * spot.at).Position
		local p = root and root.CFrame.Position
		if not (piece and root and piece:GetAttribute("FurnitureId") == spot.item and piece:GetAttribute("Spot") == spot.id
			and piece:GetAttribute("Star") == spot.star and root.Anchored == true and piece.Parent and piece.Parent.Name == "Items"
			and math.abs(p.X - want.X) < 1e-6 and math.abs(p.Y - want.Y) < 1e-6 and math.abs(p.Z - want.Z) < 1e-6) then
			table.insert(bad, `{spot.id} {spot.item}`)
		end
	end
	for _ in pieces do
		count += 1
	end
	check(`{tag}: a piece at each of the {#plan.spots} spots, marked Spot and Star, under Items`, #bad == 0 and count == #plan.spots, table.concat(bad, ", "))
	check(`{tag}: named and pivoted at its origin`, model.Name == "HouseInterior" and model:GetAttribute("Seed") == seed and model.WorldPivot == origin)

	-- 7.x alpine: the chalet's looks (the house's own parts, not the furniture): the beams, the wood panelling (no plain
	-- baseboard left), one plank floor under the house with the bathroom's tiles and the garage's concrete over it, the
	-- Kachelofen, the corner bench and its shelf, lace in the windows, the front door's painted leaves, the antlers, the
	-- pictures, the rag rugs; the ceiling lights warm
	local named: { [string]: number } = {}
	local floors, laceOk, beamsOk = {}, true, true
	local own = {}
	for _, name in { "Shell", "Decor" } do
		local f = model:FindFirstChild(name)
		for _, obj in if f then f:GetDescendants() else {} do
			table.insert(own, obj)
		end
	end
	for _, obj in own do
		if not obj:IsA("BasePart") then
			continue
		end
		named[obj.Name] = (named[obj.Name] or 0) + 1
		if obj.Name == "Floor" then
			table.insert(floors, obj)
		elseif obj.Name == "Lace" then
			laceOk = laceOk and obj.Transparency > 0.1 and obj.Transparency < 0.6 and obj.CanCollide == false
		elseif obj.Name == "Beam" then
			local top = obj.CFrame.Position.Y + obj.Size.Y / 2
			beamsOk = beamsOk and math.abs(top - (o.Y + plan.ceiling)) < 1e-6 and obj.CanCollide == false
		end
	end
	local function n(name: string): number
		return named[name] or 0
	end
	local planks = 0
	for _, f in floors do
		if f.Material == "WoodPlanks" and f.Size.X >= plan.size.X - plan.wall - 1e-6 and f.Size.Z >= plan.size.Z - plan.wall - 1e-6 then
			planks += 1
		end
	end
	check(`{tag}: one plank floor under the house, the bathroom's and the garage's over it ({#floors} floor parts)`, #floors == 3 and planks == 1)
	check(`{tag}: {n("Beam")} beams under the ceiling, {n("Wainscot")} panels of wainscot, no plain baseboard`, n("Beam") >= 2 * A.BeamRows and beamsOk
		and n("Wainscot") >= 20 and n("Baseboard") == 0)
	check(`{tag}: the Kachelofen, the corner bench and the Herrgottswinkel's shelf`, n("FireDoor") == 1 and n("StoveBench") == 1 and n("Upper") == 1
		and n("Backrest") == 2 and n("CornerShelf") == 1 and n("Candle") == 1)
	check(`{tag}: lace in {n("Lace")} windows, the front door's painted leaves, the antlers, {n("PictureFrame")} pictures, rag rugs`, n("Lace") >= 4 and laceOk
		and n("DoorLeaf") == 2 and n("Bloom") == 2 and n("Antler") == 2 and n("PictureFrame") == 2 and n("Stripe") >= 3)
	local warm = true
	for _, obj in model:GetDescendants() do
		if obj.ClassName == "PointLight" and obj.Parent and obj.Parent.Name == "Lamp" then
			warm = warm and obj.Color.R > obj.Color.B + 0.2 and obj.Color.G > obj.Color.B
		end
	end
	check(`{tag}: the ceiling lights are warm`, warm)

	HouseInterior.destroy(model)
	check(`{tag}: destroy takes it down`, #model:GetChildren() == 0 and model.Parent == nil)
end
print(`(the most: {mostParts} parts, {mostLights} lights in an interior)`)

-- 7.x alpine: the same plan builds the same interior (every part's name, class, place, size, colour, material, opacity),
-- another seed another; and every house of seeds 10-60 stays within the part budget and the lights
do
	local function looks(seed: number): string
		local model = HouseInterior.build(HouseLayout.plan(seed, "house"), HouseInterior.slot(0))
		local out = {}
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				local q, s, c = p.CFrame.Position, p.Size, p.Color
				table.insert(out, string.format("%s %s %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %s %.2f", p.Name, p.ClassName, q.X, q.Y, q.Z, s.X, s.Y, s.Z,
					c.R, c.G, c.B, tostring(p.Material), p.Transparency))
			end
		end
		HouseInterior.destroy(model)
		return table.concat(out, "\n")
	end
	local a, b = looks(1955), looks(1955)
	check("the same plan builds the same interior (Marge's House twice)", a == b and #a > 1000)
	check("another seed builds another interior", looks(5) ~= a)
	local worst, worstSeed, over = 0, 0, {}
	for seed = 10, 60 do
		local model = HouseInterior.build(HouseLayout.plan(seed, "house"), HouseInterior.slot(0))
		local parts, lights = 0, 0
		for _, obj in model:GetDescendants() do
			if obj:IsA("BasePart") then
				parts += 1
			elseif obj.ClassName == "PointLight" or obj.ClassName == "SurfaceLight" then
				lights += 1
			end
		end
		HouseInterior.destroy(model)
		if parts > worst then
			worst, worstSeed = parts, seed
		end
		if parts > T.InteriorMaxParts or lights > 12 then
			table.insert(over, `{seed}: {parts} parts, {lights} lights`)
		end
	end
	check(`seeds 10-60 within {T.InteriorMaxParts} parts and 12 lights (the most: seed {worstSeed}, {worst})`, #over == 0, table.concat(over, "; "))
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
