-- 7.0 prototype, the moving: the furniture (shared/FurnitureLooks.luau, Config.Furniture) built by the real builder on
-- the recorder (tools/fixtures/item-mock.luau) in the standalone Luau CLI: the catalogue is complete and sane (every
-- room kind, every class, the sentimental ★ pieces, a "pair" piece goes through a doorway end first), and every piece
-- in every colour builds within its part budget: its Root an invisible box of exactly its size at the origin, the only
-- part that collides, every other part welded to it, massless, not colliding or queried, nothing anchored, the look
-- inside the box, standing on its floor and filling it (the box is honest), the attributes set; 7.x: the eight alpine
-- pieces as asked and lean. 7.x farm pieces: Walt's farm's block (a bigDoor piece only through the barn doors), every
-- piece fits the moving truck's bed.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local M = require("./ItemMock")
local Config = require("./Config")
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
local function finite(x: number): boolean
	return x == x and x > -math.huge and x < math.huge
end

local T = Config.Furniture
local Items, Order = FurnitureLooks.Items, FurnitureLooks.Order

-- ── The catalogue ───────────────────────────────────────────────────────────
do
	local count, listed = 0, {}
	for id, def in Items do
		count += 1
		check(`{id}: its entry's id`, def.id == id)
	end
	for _, id in Order do
		listed[id] = (listed[id] or 0) + 1
	end
	local ordered = true
	for id in Items do
		ordered = ordered and listed[id] == 1
	end
	check(`at least 24 pieces ({count}), every one once in Order`, count >= 24 and #Order == count and ordered)
	local rooms: { [string]: number } = {}
	for _, room in FurnitureLooks.Rooms do
		rooms[room] = 0
	end
	for _, room in FurnitureLooks.FarmRooms do -- 7.x farm pieces: the farm's own rooms
		rooms[room] = 0
	end
	local classes: { [string]: number } = { hand = 0, both = 0, pair = 0 }
	local sentimental: { string } = {}
	for _, id in Order do
		local def = Items[id]
		local s = def.size
		check(`{id}: named, an icon, a real size`, def.name ~= "" and def.icon ~= "" and s.X > 0.3 and s.Y > 0.3 and s.Z > 0.3)
		check(`{id}: class {def.class}, weight {def.weight} (1..10), value ${def.value}`, classes[def.class] ~= nil
			and def.weight >= 1 and def.weight <= 10 and def.weight == math.floor(def.weight) and def.value > 0 and type(def.fragile) == "boolean")
		check(`{id}: belongs in a room kind ({def.room})`, rooms[def.room] ~= nil)
		rooms[def.room] = (rooms[def.room] or 0) + 1
		classes[def.class] = (classes[def.class] or 0) + 1
		if def.sentimental then
			table.insert(sentimental, id)
		end
		-- every piece goes through a doorway (Door wide, DoorHeight tall) end first, with room to spare
		local narrow = math.min(s.X, s.Z)
		if def.bigDoor then -- 7.x farm pieces: too wide for a house's doorway (honestly), through the barn doors
			check(`{id}: a bigDoor piece fits only the barn doors ({narrow} × {s.Y} through {T.Farm.BarnDoor} × {T.Farm.BarnDoorHeight}, not {T.Door})`,
				narrow > T.Door - 0.5 and narrow <= T.Farm.BarnDoor - 1 and s.Y <= T.Farm.BarnDoorHeight - 1)
		else
			check(`{id}: fits through a doorway ({narrow} × {s.Y} through {T.Door} × {T.DoorHeight})`, narrow <= T.Door - 0.5 and s.Y <= T.DoorHeight - 1)
		end
		-- a "hand" piece is small and light, a "pair" piece big or heavy
		if def.class == "hand" then
			check(`{id}: a hand piece is light (weight ≤ 3)`, def.weight <= 3)
		elseif def.class == "pair" then
			check(`{id}: a pair piece is big and heavy (weight ≥ 5)`, def.weight >= 5 and math.max(s.X, s.Y, s.Z) >= 3)
		end
	end
	for room, n in rooms do
		check(`room {room} has pieces ({n})`, n >= 2)
	end
	for class, n in classes do
		check(`class {class} has pieces ({n})`, n >= 5)
	end
	table.sort(sentimental)
	check(`the sentimental ★ pieces (${table.concat(sentimental, ", ")})`, #sentimental >= 4 and Items.grandfather_clock.sentimental
		and Items.photo_album.sentimental and Items.record_player.sentimental and Items.rocking_horse.sentimental)
	for _, id in { "lamp", "box", "plant", "painting", "radio" } do
		local def = Items[id] or Items["floor_" .. id]
		check(`{id} is a hand piece`, def ~= nil and def.class == "hand")
	end
	for _, id in { "dining_chair", "tv", "microwave", "nightstand", "guitar" } do
		check(`{id} is a both-hands piece`, Items[id] ~= nil and Items[id].class == "both")
	end
	for _, id in { "sofa", "fridge", "bed", "wardrobe", "dining_table", "piano", "washing_machine", "bookshelf" } do
		check(`{id} is a pair piece`, Items[id] ~= nil and Items[id].class == "pair")
	end
end

-- ── Every piece builds ───────────────────────────────────────────────────────
local function corners(p: any): (any, any)
	local r, s, c = p.CFrame.R, p.Size * 0.5, p.CFrame.Position
	local ax = math.abs(r[1]) * s.X + math.abs(r[2]) * s.Y + math.abs(r[3]) * s.Z
	local ay = math.abs(r[4]) * s.X + math.abs(r[5]) * s.Y + math.abs(r[6]) * s.Z
	local az = math.abs(r[7]) * s.X + math.abs(r[8]) * s.Y + math.abs(r[9]) * s.Z
	return M.Vector3.new(c.X - ax, c.Y - ay, c.Z - az), M.Vector3.new(c.X + ax, c.Y + ay, c.Z + az)
end

local most, mostId, total = 0, "", 0
local EPS = 0.06
for _, id in Order do
	local def = Items[id]
	local s = def.size
	local looks: { [number]: string } = {}
	for variant = 1, 4 do
		local ok, model = pcall(FurnitureLooks.build, id, variant)
		if not ok then
			check(`{id} ({variant}) builds`, false, model)
			continue
		end
		local root = model.PrimaryPart
		check(`{id} ({variant}): Root is the primary part`, root ~= nil and root.Name == "Root" and root.Parent == model)
		if not root then
			continue
		end
		local rs, rp = root.Size, root.CFrame.Position
		check(`{id} ({variant}): Root is the box, invisible, colliding, at the origin, unanchored`,
			math.abs(rs.X - s.X) < 1e-6 and math.abs(rs.Y - s.Y) < 1e-6 and math.abs(rs.Z - s.Z) < 1e-6
				and root.Transparency == 1 and root.CanCollide == true and root.Anchored == false
				and math.abs(rp.X) < 1e-6 and math.abs(rp.Y) < 1e-6 and math.abs(rp.Z) < 1e-6)
		check(`{id} ({variant}): named and marked`, model.Name ~= "" and model:GetAttribute("FurnitureId") == id
			and model:GetAttribute("Class") == def.class and model:GetAttribute("Weight") == def.weight and model.ModelStreamingMode == "Atomic")
		local welded: { [any]: boolean } = {}
		for _, obj in model:GetDescendants() do
			if obj.ClassName == "WeldConstraint" and obj.Part0 == root and obj.Part1 then
				welded[obj.Part1] = true
			end
		end
		local parts, bad = 0, {}
		local lo = M.Vector3.new(math.huge, math.huge, math.huge)
		local hi = M.Vector3.new(-math.huge, -math.huge, -math.huge)
		local colours = {}
		for _, p in model:GetDescendants() do
			if not p:IsA("BasePart") then
				continue
			end
			parts += 1
			if p == root then
				continue
			end
			local ps, pp = p.Size, p.CFrame.Position
			if not (finite(ps.X) and finite(ps.Y) and finite(ps.Z) and ps.X > 0 and ps.Y > 0 and ps.Z > 0 and finite(pp.X) and finite(pp.Y) and finite(pp.Z)) then
				table.insert(bad, p.Name .. " unsound")
			end
			if p.CanCollide ~= false or p.Massless ~= true or p.CanQuery ~= false or p.Anchored ~= false then
				table.insert(bad, p.Name .. " flags")
			end
			if not welded[p] then
				table.insert(bad, p.Name .. " not welded to Root")
			end
			local a, b = corners(p)
			if a.X < -s.X / 2 - EPS or a.Y < -s.Y / 2 - EPS or a.Z < -s.Z / 2 - EPS or b.X > s.X / 2 + EPS or b.Y > s.Y / 2 + EPS or b.Z > s.Z / 2 + EPS then
				table.insert(bad, string.format("%s outside the box (%.2f %.2f %.2f .. %.2f %.2f %.2f)", p.Name, a.X, a.Y, a.Z, b.X, b.Y, b.Z))
			end
			lo = M.Vector3.new(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z))
			hi = M.Vector3.new(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z))
			table.insert(colours, string.format("%.3f,%.3f,%.3f", p.Color.R, p.Color.G, p.Color.B))
		end
		looks[variant] = table.concat(colours, ";")
		total += parts
		if parts > most then
			most, mostId = parts, id
		end
		check(`{id} ({variant}): {parts} parts (2 .. {T.MaxParts}), every one welded, sound, inside the box`, parts >= 2 and parts <= T.MaxParts and #bad == 0,
			table.concat(bad, "; "))
		-- the look stands on the box's floor and fills the box (it is the piece's real size)
		check(string.format("%s (%d): stands on its floor and fills its box (%.1f × %.1f × %.1f of %.1f × %.1f × %.1f)", id, variant,
			hi.X - lo.X, hi.Y - lo.Y, hi.Z - lo.Z, s.X, s.Y, s.Z), math.abs(lo.Y + s.Y / 2) <= EPS
			and hi.X - lo.X >= s.X * 0.85 and hi.Y - lo.Y >= s.Y * 0.9 and hi.Z - lo.Z >= s.Z * 0.85)
	end
	local differ = false
	for variant = 2, 4 do
		differ = differ or looks[variant] ~= looks[1]
	end
	check(`{id}: its colours vary`, differ or id == "box")
end
print(`(the most parts: {mostId}, {most}; {total} parts in {#Order * 4} builds)`)

-- grips: points on the box at hand height; a pair piece at both ends of its long side
for _, id in Order do
	local def = Items[id]
	local s = def.size
	local grips = FurnitureLooks.grips(id)
	local onBox = true
	for _, g in grips do
		local onFace = math.abs(math.abs(g.X) - s.X / 2) < 1e-6 or math.abs(math.abs(g.Z) - s.Z / 2) < 1e-6
		onBox = onBox and onFace and math.abs(g.X) <= s.X / 2 + 1e-6 and math.abs(g.Z) <= s.Z / 2 + 1e-6 and g.Y <= s.Y / 2 and g.Y >= -s.Y / 2
	end
	local want = if def.class == "pair" or def.class == "both" then 2 else 1
	local apart = true
	if def.class == "pair" then
		local d = grips[2] - grips[1]
		apart = math.abs(d.Magnitude - math.max(s.X, s.Z)) < 1e-6
	end
	check(`{id}: {#grips} grips on the box`, #grips == want and onBox and apart)
end

-- 7.x farm pieces: Walt's farm's block of the catalogue: its pieces (FarmPieces, in catalogue order after the house's),
-- every one in a farm room or the Stube or kitchen, the four ★ keepsakes, the hay wagon the one bigDoor piece; every
-- piece fits the moving truck's bed (Config.Moving.Bed: turned 90° about Y at most) and is no taller than it.
do
	local farm = FurnitureLooks.FarmPieces
	local okList, inOrder = #farm >= 14, true
	local first = table.find(Order, farm[1]) or 0
	for n, id in farm do
		okList = okList and Items[id] ~= nil
		inOrder = inOrder and Order[first + n - 1] == id
	end
	check(`the farm's pieces ({#farm}): at least 14, one block of the catalogue, after the house's`, okList and inOrder and first > table.find(Order, "box") :: number)
	local farmRooms: { [string]: boolean } = { living = true, kitchen = true }
	for _, room in FurnitureLooks.FarmRooms do
		farmRooms[room] = true
	end
	local stars, big, wrong = {}, {}, {}
	local bed = Config.Moving.Beds.movingtruck -- (7.x van moves: the old truck's bed; the ZDC Van's smaller one is the packing rework's)
	for _, id in Order do
		local def = Items[id]
		local s = def.size
		local isFarm = table.find(farm, id) ~= nil
		if isFarm and not farmRooms[def.room] then
			table.insert(wrong, `{id} in {def.room}`)
		end
		if isFarm and def.sentimental then
			table.insert(stars, id)
		end
		if def.bigDoor then
			table.insert(big, id)
		end
		local fits = (s.X <= bed.Width and s.Z <= bed.Length) or (s.Z <= bed.Width and s.X <= bed.Length)
		check(`{id}: fits the moving truck's bed ({s.X} × {s.Z}, {s.Y} tall in {bed.Width} × {bed.Length}, {bed.Height})`, fits and s.Y <= bed.Height)
	end
	table.sort(stars)
	check(`the farm's pieces belong in its rooms or the Stube and kitchen`, #wrong == 0, table.concat(wrong, ", "))
	check(`the farm's ★ keepsakes ({table.concat(stars, ", ")})`, #stars == 4 and table.find(stars, "thunders_saddle") ~= nil
		and table.find(stars, "branding_iron") ~= nil and table.find(stars, "cowbells") ~= nil and table.find(stars, "grandmas_churn") ~= nil)
	check(`the hay wagon is the one bigDoor piece ({table.concat(big, ", ")}), a pair piece`, #big == 1 and big[1] == "hay_wagon" and Items.hay_wagon.class == "pair")
	local function same(a: any, b: any): boolean
		return a.X == b.X and a.Y == b.Y and a.Z == b.Z
	end
	check("a ★ variant is its plain piece's size and class (the saddles, the churns), dearer", same(Items.saddle.size, Items.thunders_saddle.size)
		and same(Items.milk_churn.size, Items.grandmas_churn.size) and Items.saddle.class == Items.thunders_saddle.class
		and Items.milk_churn.class == Items.grandmas_churn.class and Items.thunders_saddle.value > Items.saddle.value
		and Items.grandmas_churn.value > Items.milk_churn.value)
	for _, id in { "hay_bale", "saddle", "wheelbarrow", "butter_churn", "sled", "beehive", "ladder", "tack_rack" } do
		check(`{id} is a both-hands piece`, Items[id] ~= nil and Items[id].class == "both")
	end
	for _, id in { "milk_churn", "feed_sacks", "cheese_crate", "apple_crate", "cowbells", "branding_iron" } do
		check(`{id} is a hand piece`, Items[id] ~= nil and Items[id].class == "hand")
	end
	for _, id in { "tool_chest", "anvil", "farm_bench", "hay_wagon" } do
		check(`{id} is a pair piece`, Items[id] ~= nil and Items[id].class == "pair")
	end
	check("the anvil is the heaviest there is, the beehive fragile", Items.anvil.weight == 10 and Items.beehive.fragile)
end

-- 7.x alpine pieces (a chalet's things, the house's recipes draw them): the eight as asked (class, fragile, the two
-- sentimental ★ candidates, their room) and lean: at most ALPINE_PARTS parts each, so that a house drawing several of
-- them stays inside its part budget (Config.Furniture.InteriorMaxParts, tests/houseinterior_test.luau).
do
	local ALPINE_PARTS = 18
	local want: { { any } } = {
		--  id                  class   fragile ★      room
		{ "cuckoo_clock", "hand", true, true, "living" },
		{ "accordion", "both", true, true, "living" },
		{ "heart_chair", "both", false, false, "living" },
		{ "stein_crate", "hand", true, false, "kitchen" },
		{ "painted_cupboard", "pair", false, false, "bedroom" },
		{ "carved_chest", "pair", false, false, "bedroom" },
		{ "edelweiss_frame", "hand", true, false, "bedroom" },
		{ "ski_bundle", "both", false, false, "hall" },
	}
	for _, w in want do
		local id = w[1]
		local def = Items[id]
		check(`alpine {id}: {w[2]}, fragile {w[3]}, sentimental {w[4]}, in the {w[5]}`, def ~= nil and def.class == w[2] and def.fragile == w[3]
			and def.sentimental == w[4] and def.room == w[5])
		local parts = if def then FurnitureLooks.parts(id) else 0
		check(`alpine {id}: lean ({parts} parts, at most {ALPINE_PARTS})`, parts >= 6 and parts <= ALPINE_PARTS)
	end
end

-- An unknown piece is a moving box that still says what was asked for; the part count helper agrees.
do
	local model = FurnitureLooks.build("no_such_thing")
	local root = model.PrimaryPart
	check("an unknown id is a moving box", root ~= nil and root.Size.X == Items.box.size.X and model:GetAttribute("FurnitureId") == "no_such_thing")
	check("FurnitureLooks.parts counts the model's parts", FurnitureLooks.parts("sofa") >= 10 and FurnitureLooks.parts("sofa") <= T.MaxParts)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
