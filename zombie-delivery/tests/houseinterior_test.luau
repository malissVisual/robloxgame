-- 7.0 prototype, the moving: the real server/HouseInterior.luau builds house plans (shared/HouseLayout.luau) on the
-- recorder (tools/fixtures/item-mock.luau) in the standalone Luau CLI: an interior stays within its part budget
-- (Config.Furniture.InteriorMaxParts, its furniture included) and a modest number of lights, everything anchored (a
-- piece's looks held by welds to its anchored Root), every spot a piece of the right kind at the right place with its
-- Spot and Star, the house closed (walls, a ceiling, ground under it all, the porch's daylight wall), the EXIT sign
-- over the front door; the slots lie far off the map (Map.Bounds) and never overlap; destroy takes it down.
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
-- (seeds 5 and 409 are the busiest of the first 800: 591 and 599 parts; the average is about 540)
for _, seed in { 1, 2, 3, 4, 5, 6, 7, 8, 9, 409, 1955 } do -- (7.0 review: 1955 is Marge's House, Config.Moving.Contracts)
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

	HouseInterior.destroy(model)
	check(`{tag}: destroy takes it down`, #model:GetChildren() == 0 and model.Parent == nil)
end
print(`(the most: {mostParts} parts, {mostLights} lights in an interior)`)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
