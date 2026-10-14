-- 8.3 the big move: shared/HouseLayout.luau's kind "big" (the plan of the sandbox's big house, The Old Chalet: the
-- owner's big Blender house; Config.Furniture.Big) over many seeds, and the real server/HouseInterior.luau building it
-- on the recorder (tools/fixtures/item-mock.luau). A big plan: ten rooms on one floor (eight rooms: the house's six,
-- the guest room and the study; the hall and the corridor), Big.Spots pieces and Big.Collectibles collectibles besides,
-- Big.Stars ★, more pieces for two than a house's; two ways out (the front door, the back door at the corridor's east
-- end) and a way in by each; every piece carried out by either (nothing stuck, HouseLayout.exitsFor every exit); the
-- same plan for the same seed, another for another. Its inside: within Big.InteriorMaxParts; lit as every house
-- (Config.SandboxLight.House: each room's ceiling lamp, two in a room longer than Lamp.Long, at Lamp's numbers, no
-- shadows; the two doors' daylight at Porch's; the panes, the lamps' discs and the porches' walls of daylight in its
-- Neon colours; tests/sandboxlight_runtime_test.luau holds them to the caps); the front door's two leaves and the back
-- door's leaf shut in their doorways (DoorLeaf, Hinge; no collision, a PathfindingModifier PassThrough), the back
-- door's porch and EXIT sign.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local M = require("./ItemMock")
local Config = require("./Config")
local HouseLayout = require("./HouseLayout")
local HouseInterior = require("./HouseInterior")
local FurnitureLooks = require("./FurnitureLooks")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local T = Config.Furniture
local L = (T :: any).Big
local Items = FurnitureLooks.Items
local SEEDS = 40

local LIT = Config.SandboxLight.House
check("Config.Furniture.Big: its numbers (pieces, ★, collectibles 4-6, the back door, a part budget); Config.Moving.Sandbox's kind",
	type(L) == "table" and L.Spots[1] >= 30 and L.Spots[2] >= L.Spots[1] and L.Stars >= T.Stars and L.Collectibles.Count[1] == 4 and L.Collectibles.Count[2] == 6
	and L.BackDoor >= 5 and L.InteriorMaxParts > 0 and table.find(HouseLayout.Kinds, "big") ~= nil and Config.Moving.Sandbox.Kind == "big")

-- ── the plans ────────────────────────────────────────────────────────────────
local function counts(plan: any): (number, number, number, number)
	local pieces, rare, pairs_, stars = 0, 0, 0, 0
	for _, s in plan.spots do
		local def = Items[s.item]
		if def and def.rarity then
			rare += 1
		else
			pieces += 1
		end
		pairs_ += if def and def.class == "pair" then 1 else 0
		stars += if s.star then 1 else 0
	end
	return pieces, rare, pairs_, stars
end

local bad: { string } = {}
local bigPairs, housePairs, bigPieces, housePieces = 0, 0, 0, 0
local fewestRooms, mostRooms = math.huge, 0
local mirrored = 0
for seed = 1, SEEDS do
	local plan: any = HouseLayout.plan(seed, "big")
	local tag = `seed {seed}`
	local ids: { [string]: any } = {}
	for _, r in plan.rooms do
		ids[r.id] = r
	end
	fewestRooms, mostRooms = math.min(fewestRooms, #plan.rooms), math.max(mostRooms, #plan.rooms)
	if plan.kind ~= "big" or #plan.rooms ~= 10 or not ids.guest or not ids.study or not ids.corridor or ids.guest.kind ~= "bedroom" or ids.study.kind ~= "living" then
		table.insert(bad, `{tag}: its rooms`)
	end
	local pieces, rare, pairs_, stars = counts(plan)
	if pieces < L.Spots[1] or pieces > L.Spots[2] or rare < L.Collectibles.Count[1] or rare > L.Collectibles.Count[2] or stars ~= L.Stars then
		table.insert(bad, `{tag}: {pieces} pieces, {rare} collectibles, {stars} ★`)
	end
	local inRoom = true
	for _, s in plan.spots do
		local r, p = ids[s.room], s.at.Position
		inRoom = inRoom and r ~= nil and p.X > r.min.X and p.X < r.max.X and p.Z > r.min.Z and p.Z < r.max.Z
	end
	if not inRoom then
		table.insert(bad, `{tag}: a piece outside its room`)
	end
	bigPairs += pairs_
	bigPieces += pieces
	local house: any = HouseLayout.plan(seed, "house")
	local hp, _, hpairs = counts(house)
	housePairs += hpairs
	housePieces += hp
	-- the two ways out and in
	local exits = HouseLayout.exitsOf(plan)
	local entries = HouseLayout.entries(plan)
	local outside: { any } = {}
	for _, d in plan.doors do
		if d.rooms[2] == "outside" then
			table.insert(outside, d)
		end
	end
	local backDoor = outside[2]
	local corridor = ids.corridor
	if #exits ~= 2 or #entries ~= 2 or #outside ~= 2 or (exits[1] - plan.exit).Magnitude > 1e-6 or outside[1] ~= plan.doors[1] then
		table.insert(bad, `{tag}: {#exits} exits, {#entries} entries, {#outside} doorways out`)
	elseif not (backDoor.rooms[1] == "corridor" and backDoor.axis == "Z" and math.abs(backDoor.at.X - corridor.max.X) < plan.wall
		and backDoor.at.Z > corridor.min.Z and backDoor.at.Z < corridor.max.Z and backDoor.width == L.BackDoor and backDoor.at.X > 0) then
		table.insert(bad, `{tag}: the back door not at the corridor's east end`)
	elseif not ((exits[2] - backDoor.at).Magnitude < plan.wall + T.EntryUp + 0.5 and exits[2].X < backDoor.at.X
		and -entries[2].R[3] < -0.99 and entries[2].Position.X < exits[2].X) then
		table.insert(bad, `{tag}: the back door's way out and in`)
	end
	mirrored += if plan.mirrored then 1 else 0
	-- every piece out by either door
	local stuck = HouseLayout.stuck(plan)
	if #stuck > 0 then
		table.insert(bad, `{tag}: {#stuck} stuck`)
	end
	for _, s in plan.spots do
		local by = HouseLayout.exitsFor(plan, s.item)
		if #by ~= 2 or by[1] ~= 1 or by[2] ~= 2 then
			table.insert(bad, `{tag}: {s.item} not out by both doors`)
			break
		end
	end
	-- the same seed, the same plan
	if seed <= 6 then
		local again: any = HouseLayout.plan(seed, "big")
		local same = #again.spots == #plan.spots and again.mirrored == plan.mirrored and (again.size - plan.size).Magnitude < 1e-9
		for i, s in plan.spots do
			local t = again.spots[i]
			same = same and t ~= nil and t.item == s.item and (t.at.Position - s.at.Position).Magnitude < 1e-9 and t.turn == s.turn and t.star == s.star and t.variant == s.variant
		end
		if not same then
			table.insert(bad, `{tag}: another plan the second time`)
		end
	end
end
check(`{SEEDS} big houses: ten rooms each (the guest room a bedroom, the study a living room), {L.Spots[1]}-{L.Spots[2]} pieces, {L.Collectibles.Count[1]}-{L.Collectibles.Count[2]} collectibles, {L.Stars} ★, each piece in its room`,
	#bad == 0 and fewestRooms == 10 and mostRooms == 10, table.concat(bad, "; "))
check(`more pieces for two than a house's ({string.format("%.1f", bigPairs / SEEDS)} a big house, {string.format("%.1f", housePairs / SEEDS)} a house) and more pieces ({string.format("%.1f", bigPieces / SEEDS)}, {string.format("%.1f", housePieces / SEEDS)})`,
	bigPairs >= housePairs * 1.4 and bigPieces > housePieces + 10)
check(`mirrored and not ({mirrored} of {SEEDS}): the back door at the corridor's east end either way`, mirrored > 0 and mirrored < SEEDS)
local a: any, b: any = HouseLayout.plan(1, "big"), HouseLayout.plan(2, "big")
local differs = #a.spots ~= #b.spots or a.mirrored ~= b.mirrored
for i, s in a.spots do
	differs = differs or b.spots[i] == nil or b.spots[i].item ~= s.item or (b.spots[i].at.Position - s.at.Position).Magnitude > 1e-6
end
check("another seed, another big house (a new seed a move)", differs)
local big: any = HouseLayout.plan(3, "big")
local small: any = HouseLayout.plan(3, "house")
check(`a big house bigger than a house ({math.floor(big.size.X)} × {math.floor(big.size.Z)}, a house {math.floor(small.size.X)} × {math.floor(small.size.Z)}), fitting its interior slot`,
	big.size.X * big.size.Z > 1.4 * small.size.X * small.size.Z and math.max(big.size.X, big.size.Z) + 2 * T.Ground.Margin + 40 <= T.Slot.Spacing)

-- ── the inside ───────────────────────────────────────────────────────────────
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
local function near(c: any, rgb: { number }): boolean
	return math.abs(c.R * 255 - rgb[1]) < 1 and math.abs(c.G * 255 - rgb[2]) < 1 and math.abs(c.B * 255 - rgb[3]) < 1
end

local mostParts = 0
for _, seed in { 1, 2, 3, 4, 5, 6 } do
	local plan: any = HouseLayout.plan(seed, "big")
	local origin = HouseInterior.slot(seed % 7)
	local ok, model = pcall(HouseInterior.build, plan, origin)
	local tag = `seed {seed}`
	if not ok then
		check(`{tag}: builds`, false, model)
		continue
	end
	local o = origin.Position
	local parts, glows = 0, {}
	local roomLights, doorLights, wrongLight = 0, 0, {}
	local NEON = { LIT.Glow, LIT.Tube, LIT.Window, LIT.BathWindow, LIT.Daylight } -- (the house's own Neon: these colours)
	local named: { [string]: { any } } = {}
	local warm, walls = 0, 0
	for _, obj in model:GetDescendants() do
		if obj.ClassName == "PointLight" then
			roomLights += 1
			if not (obj.Brightness == LIT.Lamp.Brightness and obj.Range == LIT.Lamp.Range and obj.Shadows ~= true
				and (near(obj.Color, LIT.Lamp.Color) or (obj.Parent and obj.Parent.Name == "Tube"))) then
				table.insert(wrongLight, `{obj.Parent and obj.Parent.Name}: {obj.Brightness}/{obj.Range}`)
			end
		elseif obj.ClassName == "SurfaceLight" or obj.ClassName == "SpotLight" then
			doorLights += 1
			if not (obj.Brightness == LIT.Porch.Brightness and obj.Range == LIT.Porch.Range and near(obj.Color, LIT.Porch.Color) and obj.Shadows ~= true) then
				table.insert(wrongLight, `{obj.Parent and obj.Parent.Name}: {obj.Brightness}/{obj.Range}`)
			end
		end
		if not obj:IsA("BasePart") then
			continue
		end
		parts += 1
		named[obj.Name] = named[obj.Name] or {}
		table.insert(named[obj.Name], obj)
		local s = obj.Size
		local faces = math.max(s.X * s.Y, s.X * s.Z, s.Y * s.Z)
		if obj.Material == M.Enum.Material.Neon and faces > 2 then -- (a piece's own small glow, a sign or embers: its own)
			local known = false
			for _, c in NEON do
				known = known or near(obj.Color, c)
			end
			if not known then
				table.insert(glows, `{obj.Name} {string.format("%.1f", faces)}`)
			end
		end
		if obj.Name == "Wall" then
			walls += 1
			local c = obj.Color
			warm += if c.R >= c.G and c.G >= c.B - 0.01 and c.R > 0.7 then 1 else 0
		end
	end
	mostParts = math.max(mostParts, parts)
	check(`{tag}: {parts} parts (at most Big.InteriorMaxParts {L.InteriorMaxParts}, {#plan.spots} pieces)`, parts <= L.InteriorMaxParts)
	local lamps = 0
	for _, room in plan.rooms do
		lamps += if math.max(room.max.X - room.min.X, room.max.Z - room.min.Z) > LIT.Lamp.Long then 2 else 1
	end
	check(`{tag}: a ceiling lamp a room, two in a long one ({roomLights} for {#plan.rooms} rooms: Config.SandboxLight.House.Lamp), the two doors' daylight ({doorLights}: Porch), no shadows`,
		roomLights == lamps and doorLights == 2 and #wrongLight == 0, table.concat(wrongLight, ", "))
	check(`{tag}: its big Neon (the lamps' discs, the panes, the porches' walls) in Config.SandboxLight.House's colours only`, #glows == 0, table.concat(glows, ", "))
	check(`{tag}: warm off-white walls ({warm} of {walls}; the bathroom's tiles and the garage's concrete their own)`, walls > 0 and warm >= walls * 0.6)
	-- the doors' leaves
	local front, back = plan.doors[1], nil
	for index, d in plan.doors do
		if index > 1 and d.rooms[2] == "outside" then
			back = d
		end
	end
	local leaves = true
	local function leaf(name: string, door: string, hinge: string, d: any, dx: number): boolean
		local list = named[name] or {}
		local p = list[1]
		if #list ~= 1 or not p then
			return false
		end
		local at = p.CFrame.Position - o
		local through = false -- (Danny's paths through it: a PathfindingModifier PassThrough)
		for _, c in p:GetChildren() do
			through = through or (c.ClassName == "PathfindingModifier" and c.PassThrough == true)
		end
		return through and p:GetAttribute("DoorLeaf") == door and p:GetAttribute("Hinge") == hinge and p.CanCollide == false and p.Transparency ~= 1
			and math.abs(at.X - (d.at.X + dx)) < 0.05 and math.abs(at.Z - d.at.Z) < 0.05 and at.Y > 2 and p.Size.Y > plan.doorHeight - 0.5
	end
	leaves = leaf("FrontLeafWest", "front", "west", front, -front.width / 4) and leaf("FrontLeafEast", "front", "east", front, front.width / 4)
		and back ~= nil and leaf("BackLeaf", "back", "south", back, 0)
	check(`{tag}: the leaves shut in their doorways, hinged (FrontLeafWest west, FrontLeafEast east, BackLeaf south), not solid, Danny's paths through them`, leaves)
	check(`{tag}: no front leaves opened out against the porch (the big house's are shut)`, #(named.DoorLeaf or {}) == 0)
	-- the back door's porch and the way out signs
	local exits = 0
	for _, s in named.ExitSign or {} do
		exits += if textOf(s) == "EXIT" then 1 else 0
	end
	local porch = (named.BackPorch or {})[1]
	local soft = (named.BackDaylight or {})[1]
	check(`{tag}: the back door's porch (its floor, sides, roof, its wall of daylight: LIT.Daylight) east of the house, an EXIT sign over each way out`, porch ~= nil
		and porch.CFrame.Position.X - o.X > back.at.X and soft ~= nil and soft.Material == M.Enum.Material.Neon and near(soft.Color, LIT.Daylight)
		and #(named.BackPorchWall or {}) == 2 and #(named.BackPorchRoof or {}) == 1 and exits == 2)
	model:Destroy()
end
print(`(the busiest of these: {mostParts} parts)`)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
