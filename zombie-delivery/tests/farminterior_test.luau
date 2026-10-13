-- 7.x, Walt's farm built: the real server/HouseInterior.luau builds farm plans (shared/Layouts/Farm.luau through
-- shared/HouseLayout.luau) on the recorder (tools/fixtures/item-mock.luau) in the standalone Luau CLI: an interior stays
-- within the farm's part budget (Config.Furniture.Farm.InteriorMaxParts, its furniture included) and Farm.Lights
-- lights (modest, no shadows), everything anchored (a piece's looks welded to its anchored Root), a piece at every spot;
-- the farmhouse under its ceiling, the barn under its roof, the yard open to the sky and fenced (an invisible wall over
-- the fences), ground under it all; two ways out with daylight beyond them and an EXIT sign over each (the front door's
-- porch, the barn doors' apron); the barn lit by its lanterns, Thunder's stall named; a farm fits its interior slot;
-- destroy takes it down.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local M = require("./ItemMock")
local Config = require("./Config")
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
local F = T.Farm

-- the farms fit the interiors' slots (as the houses do: tests/houseinterior_test.luau)
do
	local biggest = 0
	for seed = 1, 20 do
		local plan = HouseLayout.plan(seed, "farm")
		biggest = math.max(biggest, plan.size.X, plan.size.Z + F.Apron + 6)
	end
	check(`a farm fits its slot ({math.floor(biggest)} studs with its porch and apron, the slots {T.Slot.Spacing} apart)`, biggest + 2 * T.Ground.Margin + 100 <= T.Slot.Spacing)
end

local function textOf(part: any): string?
	for _, gui in part:GetChildren() do
		for _, label in gui:GetChildren() do
			if label.ClassName == "TextLabel" then
				return label.Text
			end
		end
	end
	return nil
end

local mostParts, mostLights = 0, 0
-- (seeds 205 and 268 are the busiest of the first 300: 676 and 669 parts; the average is about 605)
for _, seed in { 1, 2, 3, 4, 5, 6, 7, 8, 205, 268 } do
	local plan: any = HouseLayout.plan(seed, "farm")
	local origin = HouseInterior.slot(seed % 7)
	local ok, model, pieces = pcall(HouseInterior.build, plan, origin)
	local tag = `seed {seed}`
	if not ok then
		check(`{tag}: builds`, false, model)
		continue
	end
	local o = origin.Position
	local parts, lights, unsound, loose = 0, 0, {}, {}
	local lo, hi = M.Vector3.new(math.huge, math.huge, math.huge), M.Vector3.new(-math.huge, -math.huge, -math.huge)
	local named: { [string]: { any } } = {}
	for _, obj in model:GetDescendants() do
		if obj.ClassName == "PointLight" or obj.ClassName == "SurfaceLight" or obj.ClassName == "SpotLight" then
			lights += 1
			check(`{tag}: a light without shadows, modest`, obj.Shadows ~= true and (obj.Range or 0) <= 40 and (obj.Brightness or 0) <= 3)
		end
		if not obj:IsA("BasePart") then
			continue
		end
		parts += 1
		named[obj.Name] = named[obj.Name] or {}
		table.insert(named[obj.Name], obj)
		local s, p = obj.Size, obj.CFrame.Position
		if not (finite(s.X) and finite(s.Y) and finite(s.Z) and s.X > 0 and s.Y > 0 and s.Z > 0 and finite(p.X) and finite(p.Y) and finite(p.Z)) then
			table.insert(unsound, obj.Name)
		end
		lo = M.Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
		hi = M.Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
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
	check(`{tag}: {parts} parts (at most {F.InteriorMaxParts}, {#plan.spots} pieces), {lights} lights (8 to {F.Lights})`, parts <= F.InteriorMaxParts and lights >= 8 and lights <= F.Lights)
	check(`{tag}: every part sound and anchored (a piece's looks welded to its anchored Root)`, #unsound == 0 and #loose == 0,
		table.concat(unsound, ",") .. " / " .. table.concat(loose, ","))
	check(`{tag}: built at its slot, within the farm's box (its porch and apron just past it)`, lo.X >= o.X + plan.min.X - 12 and hi.X <= o.X + plan.max.X + 12
		and lo.Z >= o.Z + plan.min.Z - 12 and hi.Z <= o.Z + plan.max.Z + 12 and lo.Y >= o.Y - T.Ground.Depth - 1 and hi.Y <= o.Y + F.Barrier + 1)

	-- the ground, the roofs and the open yard
	local ground = (named.Ground or {})[1]
	local g, gp = ground and ground.Size, ground and ground.CFrame.Position
	check(`{tag}: ground under all of it, below the floor`, ground ~= nil and gp.Y + g.Y / 2 <= o.Y + 1e-6 and gp.X - g.X / 2 <= o.X + plan.min.X - T.Ground.Margin + 1e-6
		and gp.X + g.X / 2 >= o.X + plan.max.X + T.Ground.Margin - 1e-6 and gp.Z - g.Z / 2 <= o.Z + plan.min.Z - T.Ground.Margin + 1e-6
		and gp.Z + g.Z / 2 >= o.Z + plan.max.Z + T.Ground.Margin - 1e-6 and ground.CanCollide == true)
	local byId: { [string]: any } = {}
	for _, r in plan.rooms do
		byId[r.id] = r
	end
	local function covers(part: any, room: any): boolean
		local p, s = part.CFrame.Position - o, part.Size
		return part.CanCollide == true and p.X - s.X / 2 <= room.min.X + 1e-6 and p.X + s.X / 2 >= room.max.X - 1e-6
			and p.Z - s.Z / 2 <= room.min.Z + 1e-6 and p.Z + s.Z / 2 >= room.max.Z - 1e-6 and math.abs(p.Y - s.Y / 2 - room.max.Y) < 1e-6
	end
	local ceiling, roof = (named.Ceiling or {})[1], (named.BarnRoof or {})[1]
	local houseCovered, barnCovered = true, true
	for _, id in { "mudroom", "stube", "kitchen", "bedroom", "pantry" } do
		houseCovered = houseCovered and ceiling ~= nil and covers(ceiling, byId[id])
	end
	for _, id in { "stable", "barn", "workshop" } do
		barnCovered = barnCovered and roof ~= nil and covers(roof, byId[id])
	end
	local yard = byId.yard
	local open = true
	for _, name in { "Ceiling", "BarnRoof" } do
		for _, p in named[name] or {} do
			local c, s = p.CFrame.Position - o, p.Size
			open = open and (c.Z + s.Z / 2 <= yard.min.Z + 1e-6 or c.Z - s.Z / 2 >= yard.max.Z - 1e-6)
		end
	end
	check(`{tag}: the farmhouse under its ceiling ({T.Ceiling} up), the barn under its roof ({F.BarnCeiling} up), the yard open to the sky`,
		#(named.Ceiling or {}) == 1 and #(named.BarnRoof or {}) == 1 and houseCovered and barnCovered and open)
	local barriers, barrierOk = named.Barrier or {}, true
	for _, b in barriers do
		local c, s = b.CFrame.Position - o, b.Size
		barrierOk = barrierOk and b.Transparency == 1 and b.CanCollide == true and math.abs(c.Y - s.Y / 2 - F.Fence) < 1e-6 and math.abs(c.Y + s.Y / 2 - F.Barrier) < 1e-6
	end
	check(`{tag}: the yard's two fences, an invisible wall over each up to {F.Barrier}`, #barriers == 2 and barrierOk)
	local walls, floors = 0, 0
	for _, w in named.Wall or {} do
		walls += if w.CanCollide == true then 1 else 0
	end
	for _, f in named.Floor or {} do
		floors += if f.CanCollide == true then 1 else 0
	end
	check(`{tag}: walls ({walls}) round every room, a floor in each ({floors})`, walls >= #plan.rooms * 4 and floors == #plan.rooms)

	-- the two ways out
	local exits, daylight = #(named.ExitSign or {}), (named.Daylight or {})[1]
	local barnLight = (named.BarnDaylight or {})[1]
	local doors = named.BarnDoor or {}
	local doorsSolid = #doors == 2
	for _, d in doors do
		doorsSolid = doorsSolid and d.CanCollide == true
	end
	local barnDoors = plan.doors[1]
	for _, d in plan.doors do
		if d.rooms[1] == "barn" and d.rooms[2] == "outside" then
			barnDoors = d
		end
	end
	local beyond = barnLight and (barnLight.CFrame.Position - o).Z > barnDoors.at.Z + F.Apron
	check(`{tag}: two EXIT signs, the porch's daylight and the barn doors' (solid, beyond the apron), the barn doors open against it`, exits == 2
		and daylight ~= nil and daylight.CanCollide == true and barnLight ~= nil and barnLight.CanCollide == true and beyond == true and doorsSolid)
	local lanterns, lit = named.Lantern or {}, 0
	for _, l in lanterns do
		lit += if l:FindFirstChildOfClass("PointLight") then 1 else 0
	end
	local names = {}
	for _, board in named.NameBoard or {} do
		table.insert(names, textOf(board) or "?")
	end
	check(`{tag}: the barn lit by its {#lanterns} lanterns; the stalls' name boards ({table.concat(names, ", ")}), Thunder's first`, #lanterns == 4 and lit == 4
		and #names == F.Stalls and names[1] == "THUNDER")
	local sign = (named.RanchSign or {})[1]
	check(`{tag}: the ranch's name over the barn's yard door`, sign ~= nil and textOf(sign) == "SILVER SPUR RANCH")

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
	check(`{tag}: named, a farm, pivoted at its origin`, model.Name == "HouseInterior" and model:GetAttribute("Seed") == seed and model:GetAttribute("Kind") == "farm"
		and model.WorldPivot == origin)

	HouseInterior.destroy(model)
	check(`{tag}: destroy takes it down`, #model:GetChildren() == 0 and model.Parent == nil)
end
print(`(the most: {mostParts} parts, {mostLights} lights in a farm)`)

-- a house still builds as before: one ceiling over the whole house, no farm in it
do
	local plan = HouseLayout.plan(1955, "house")
	local model = HouseInterior.build(plan, HouseInterior.slot(0))
	local ceilings, farm = 0, 0
	for _, obj in model:GetDescendants() do
		if obj.Name == "Ceiling" then
			ceilings += 1
		elseif obj.Name == "BarnRoof" or obj.Name == "Barrier" or obj.Name == "Lantern" then
			farm += 1
		end
	end
	check("a house still gets its one ceiling and nothing of the farm's", ceilings == 1 and farm == 0)
	HouseInterior.destroy(model)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
