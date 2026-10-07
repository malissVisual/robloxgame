-- 6.4.1, the bag shows and what is in it shows (shared/BagFill.luau, shared/KitFit.luau's bag key and grip,
-- server/KitWear.luau): the worn bag's slot key gives KitArt a look it knows (6.4 asked for "bag@hand" and no bag was
-- ever built), every bag in every way of wearing it rests close to the hand / the torso it hangs on, on the courier's
-- R15 body and on an R6 body, and the pieces in it stick out of its opening as small shapes of their looks, up to its
-- room, while its body swells a little. 6.7: real-size bags and real-size pieces packed in them (a pizza box flat in the
-- thermal bag, on its edge in a plastic one, a bouquet sticking out), the top layer out of the opening by 20–40 %,
-- nothing under the bottom or in each other, the thermal lid open while loaded. Run with tests/run_tests.py.
local Config = require("./Config")
local Transport = require("./Transport")
local Holding = require("./Holding")
local KitFit = require("./KitFit")
local BagFill = require("./BagFill")
local KitArt = require("./KitGeometry")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- Rx · Ry · Rz (CFrame.Angles, degrees) applied to v.
local function rotate(turn: { number }?, v: { number }): { number }
	local r = turn or { 0, 0, 0 }
	local a, b, c = math.rad(r[1]), math.rad(r[2]), math.rad(r[3])
	local x, y, z = v[1], v[2], v[3]
	-- Rz
	x, y = x * math.cos(c) - y * math.sin(c), x * math.sin(c) + y * math.cos(c)
	-- Ry
	x, z = x * math.cos(b) + z * math.sin(b), -x * math.sin(b) + z * math.cos(b)
	-- Rx
	y, z = y * math.cos(a) - z * math.sin(a), y * math.sin(a) + z * math.cos(a)
	return { x, y, z }
end
local function add(a: { number }, b: { number }): { number }
	return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end
local function length(a: { number }): number
	return math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
end
-- How far a (turned) box reaches along the pivot's X from its centre.
local function halfX(piece: any): number
	local reach = 0
	for i, axis in { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } } do
		reach += math.abs(rotate(piece.turn, axis)[1]) * piece.size[i] / 2
	end
	return reach
end

local bags: { Config.KitDef } = {}
for _, def in Config.Kit do
	if Transport.isBag(def) then
		table.insert(bags, def)
	end
end
check("five bags", #bags == 5, #bags)

-- The slot key (the 6.4 bug) -----------------------------------------------------------------------------------------

check("the key of a bag in the hand", KitFit.bagKey("bag", "hand", false) == "bag@hand")
check("the key of a slung duffel behind a backpack", KitFit.bagKey("duffel", "back", true) == "duffel@back+")
for _, def in bags do
	for _, place in { "hand", "shoulder", "hip", "back", "hipBack" } do
		for _, packed in { false, true } do
			local key = KitFit.bagKey(def.id, place, packed)
			local id, at, pack = KitFit.parseBagKey(key)
			local ok = pcall(KitArt.pieces, id :: string)
			check(`{key}: back to its bag, place and pack, a look KitArt knows`, id == def.id and at == place and pack == packed and ok)
		end
	end
end
check("not a key: nil", KitFit.parseBagKey("bag") == nil and KitFit.parseBagKey("") == nil)
check("(6.4's bug: the key itself is no look)", not pcall(KitArt.pieces, "bag@hand"))

-- Where each bag rests, per way of wearing it, on both bodies ------------------------------------------------------

-- The bodies: the courier's R15 (server/CharacterArt/Geometry.luau) and a classic R6. `parts` the R15 names the kit
-- asks for → the part it gets there (KitFit.R6) and its size.
type Body = { name: string, parts: { [string]: { name: string, size: { number } } } }
local bodies: { Body } = {
	{ name = "R15 courier", parts = { LeftHand = { name = "LeftHand", size = { 1, 0.3, 1 } }, UpperTorso = { name = "UpperTorso", size = { 2, 1.6, 1 } } } },
	{ name = "R6", parts = { LeftHand = { name = KitFit.R6.LeftHand, size = { 1, 2, 1 } }, UpperTorso = { name = KitFit.R6.UpperTorso, size = { 2, 2, 1 } } } },
}
check("R6 stand-ins: the bag under the Left Arm, the places on the Torso", KitFit.R6.LeftHand == "Left Arm" and KitFit.R6.UpperTorso == "Torso")

-- Every way a bag can show: its carry while it is the hand, on the back when it stays (the messenger: behind the hip).
local function styles(def: Config.KitDef): { string }
	local out: { string } = {}
	local front = Holding.wornAs("bag", def.carry, def.stays, false) :: string
	table.insert(out, front)
	local away = Holding.wornAs("gun", def.carry, def.stays, false)
	if away then
		table.insert(out, if def.carry == "hip" then "hipBack" else away)
	end
	return out
end
check("the plastic bag: only in the hand", table.concat(styles(bags[1]), ",") == "hand")

for _, body in bodies do
	for _, def in bags do
		for _, place in styles(def) do
			for _, packed in { false, true } do
				local spot = Config.Courier.BagPlaces[place]
				local partName = if spot then spot.part else "LeftHand"
				local part = body.parts[partName]
				local at, turn = KitFit.bagGrip(def.id, place, partName, part.size, packed)
				local mouth = Config.Courier.BagFill.Mouth[def.id]
				local full = BagFill.swell(BagFill.open(KitArt.pieces(def.id), KitArt.open[def.id]), mouth, def.extra or 0, def.extra or 0)
				for _, piece in BagFill.pieces(mouth, def.extra or 0, def.extra or 0, { "pizza", "bouquet", "newspaper", "cake", "mail", "bread" }) do
					table.insert(full, piece)
				end
				local far, farName = 0, ""
				for _, piece in full do
					-- at rest the bag hangs straight from its grip (client/BagSway.luau: in the hand the world's up, elsewhere
					-- the place's turn): the piece's centre on the body part
					local where = add(at, rotate(turn, piece.at))
					if length(where) > far then
						far, farName = length(where), piece.name
					end
				end
				local label = `{body.name}, {def.id} {place}{if packed then " (a backpack worn)" else ""}`
				check(`{label}: the grip on its body part ({part.name})`, length(at) < (if spot then 2 else 1.5), length(at))
				check(`{label}: full, every piece within 3 studs of the {part.name}`, far <= 3, `{farName} {far}`)
				if place == "hand" and body.name == "R15 courier" then
					-- the hand at x = -1.5 from the root, the left leg up to x = -1: a full bag still clears it
					local inner = -math.huge
					for _, piece in full do
						inner = math.max(inner, -1.5 + at[1] + piece.at[1] + halfX(piece))
					end
					check(`{label}: full, it clears the left leg`, inner < -1, inner)
				end
			end
		end
	end
end
local handAt = KitFit.bagGrip("bag", "hand", "LeftHand", { 1, 0.3, 1 }, false)
check("the plastic bag's grip just under the R15 hand", math.abs(handAt[2] - (-0.15 - Config.Courier.Bag.Grip)) < 1e-9 and handAt[1] == 0, handAt[2])
local armAt = KitFit.bagGrip("bag", "hand", "LeftHand", { 1, 2, 1 }, false)
check("… and under the bottom of an R6 Left Arm", math.abs(armAt[2] - (-1 - Config.Courier.Bag.Grip)) < 1e-9, armAt[2])
local thermalAt = KitFit.bagGrip("thermal", "hand", "LeftHand", { 1, 0.3, 1 }, false)
check("the thermal bag a little further out", thermalAt[1] < 0)
local shoulder = KitFit.bagGrip("tote", "shoulder", "UpperTorso", { 2, 1.6, 1 }, false)
local shoulderR6 = KitFit.bagGrip("tote", "shoulder", "UpperTorso", { 2, 2, 1 }, false)
check("the tote's shoulder spot on the top of the torso, R15 and R6 (scaled to the taller Torso)", math.abs(shoulder[2] - 0.8) < 1e-9 and math.abs(shoulderR6[2] - 1) < 1e-9, `{shoulder[2]} {shoulderR6[2]}`)
local slung = KitFit.bagGrip("duffel", "back", "UpperTorso", { 2, 1.6, 1 }, false)
local slungPacked = KitFit.bagGrip("duffel", "back", "UpperTorso", { 2, 1.6, 1 }, true)
check("a slung bag hangs PackPush further back behind a backpack", math.abs(slungPacked[3] - slung[3] - Config.Courier.PackPush) < 1e-9)

-- What is in the bag (6.7: real sizes) -------------------------------------------------------------------------------

local B = Config.Courier.BagFill
check("the looks attribute", table.concat(BagFill.looks("pizza,bouquet"), "|") == "pizza|bouquet" and #BagFill.looks(nil) == 0 and #BagFill.looks("") == 0)
check("a pizza is a pizza box", BagFill.kind("pizza") == "pizza")
check("a bouquet", BagFill.kind("bouquet") == "bouquet")
check("mail, a newspaper, documents", BagFill.kind("mail") == "mail" and BagFill.kind("newspaper") == "paper" and BagFill.kind("documents") == "folder")
check("a burger, noodles: a food box", BagFill.kind("burger") == "food" and BagFill.kind("noodles") == "food")
check("groceries and seedlings: their own shapes", BagFill.kind("groceries") == "groceries" and BagFill.kind("plants") == "plants")
check("anything else, or nothing known: a parcel", BagFill.kind("crate") == "parcel" and BagFill.kind(nil) == "parcel")
for look in Config.Cargo.LightLooks do
	local kind = BagFill.kind(look)
	check(`light look {look}: a shape and its packed size`, BagFill.Shapes[kind] ~= nil and B.Packed[kind] ~= nil)
end
for kind, rule in B.Packed do
	local s = rule.size
	-- real sizes: never the 6.4.1 crumbs (a pizza card 0.07 thick), never bigger than a bag
	check(`{kind}: a real packed size (its longest side 0.3–1.1 studs)`, BagFill.Shapes[kind] ~= nil and #s == 3 and math.max(s[1], s[2], s[3]) >= 0.3
		and math.max(s[1], s[2], s[3]) <= 1.1 and math.min(s[1], s[2], s[3]) >= 0.05, table.concat(s, " × "))
end
local P = B.Packed
check("the owner's sizes: a pizza box 0.95 × 0.12 × 0.95, a parcel, a bouquet a stud tall, a cake box 0.65",
	P.pizza.size[1] == 0.95 and P.pizza.size[2] == 0.12 and P.pizza.stack == true and P.parcel.size[2] == 0.45 and P.bouquet.size[2] == 1
		and P.bouquet.upright == true and P.cake.size[1] == 0.65 and P.cake.upright == true)

local plastic = B.Mouth.bag
check("an empty bag shows nothing", #BagFill.layout(plastic, 0, 2, nil) == 0 and #BagFill.pieces(plastic, 0, 2, nil) == 0)
check("never more than its room", #BagFill.layout(plastic, 5, 2, nil) == 2)
check("never more than Max", #BagFill.layout(B.Mouth.duffel, 20, 20, nil) == B.Max)

-- Every bag, every count up to its room, a few mixes: the packing's rules.
local mixes: { { string } } = {
	{ "pizza", "pizza", "pizza", "pizza", "pizza", "pizza" },
	{ "parcel", "parcel", "parcel", "parcel", "parcel", "parcel" },
	{ "pizza", "bouquet", "mail", "newspaper", "cake", "burger" },
	{ "cake", "groceries", "gadget", "medicine", "bread", "plants" },
	{ "documents", "noodles", "pastry", "icecream", "mail", "parcel" },
}
local EPS = 1e-6
for _, def in bags do
	local mouth = B.Mouth[def.id]
	check(`{def.id}: its opening`, mouth ~= nil and mouth.d ~= nil)
	if not mouth then
		continue
	end
	local room = def.extra or 0
	local floor = mouth.y - (mouth.d or 0)
	for m, looks in mixes do
		for n = 1, room do
			local label = `{def.id}, mix {m}, {n} in it`
			local spots = BagFill.layout(mouth, n, room, looks)
			local inside, deep, out, real, upright = true, true, true, true, true
			local why = ""
			local top = 0
			for _, spot in spots do
				local shrunk = spot.scale <= B.MinScale + EPS
				if not shrunk and (math.abs(spot.x) + spot.sx / 2 > mouth.x / 2 + EPS or math.abs(spot.z) + spot.sz / 2 > mouth.z / 2 + EPS) then
					inside = false
					why = `{spot.kind} at {spot.x}, {spot.z}`
				end
				if spot.y - spot.sy / 2 < floor - EPS then
					deep = false
				end
				real = real and spot.scale >= B.MinScale - EPS and math.max(spot.sx, spot.sy, spot.sz) >= 0.3
				upright = upright and (not P[spot.kind].upright or spot.axes[2] == 2)
				top = math.max(top, if spot.layer == 1 then 1 else 0)
			end
			-- the top layer: each piece (a stack: its top piece) sticks out by its share, 20–40 %; a flat stack's
			-- top box at the rim at least
			local stacks: { [string]: { any } } = {}
			for _, spot in spots do
				if spot.layer == 1 then
					local key = `{spot.kind}{spot.x}:{spot.z}`
					stacks[key] = stacks[key] or {}
					table.insert(stacks[key], spot)
				end
			end
			for _, pile in stacks do
				local high = pile[1]
				for _, spot in pile do
					if spot.y > high.y then
						high = spot
					end
				end
				local over = high.y + high.sy / 2 - mouth.y
				local share = over / high.sy
				if #pile > 1 then
					out = out and over >= -EPS and over <= high.sy * 0.4 + EPS
				else
					out = out and share >= 0.2 - EPS and share <= 0.4 + EPS
				end
			end
			-- no two pieces of a layer in each other (a stack's pieces one on the other)
			local apart = true
			for i, a in spots do
				for j, b in spots do
					if j > i and a.layer == b.layer then
						local overlapX = math.abs(a.x - b.x) < (a.sx + b.sx) / 2 - 1e-3
						local overlapZ = math.abs(a.z - b.z) < (a.sz + b.sz) / 2 - 1e-3
						local overlapY = math.abs(a.y - b.y) < (a.sy + b.sy) / 2 - 1e-3
						if overlapX and overlapZ and overlapY then
							apart = false
							why = `{a.kind} and {b.kind}`
						end
					end
				end
			end
			check(`{label}: {#spots} shown`, #spots == math.min(n, B.Max))
			check(`{label}: each within the opening`, inside, why)
			check(`{label}: none under the bottom`, deep)
			check(`{label}: the top layer sticks out 20–40 % (a flat stack: at the rim)`, out and top == 1)
			check(`{label}: real sizes, never crumbs`, real)
			check(`{label}: upright pieces stay upright`, upright)
			check(`{label}: no two in each other`, apart, why)
		end
	end
	local pieces = BagFill.pieces(mouth, room, room, mixes[3])
	local names: { [string]: boolean } = {}
	local unique, onPivot, round = true, true, true
	for _, piece in pieces do
		unique = unique and not names[piece.name]
		names[piece.name] = true
		onPivot = onPivot and piece.attach == "BagPivot" and piece.size[1] > 0 and piece.size[2] > 0 and piece.size[3] > 0
		if piece.shape == "Cylinder" then
			round = round and math.abs(piece.size[2] - piece.size[3]) < 1e-9
		end
	end
	check(`{def.id}: the shapes' parts, named once each, on the pivot, the cylinders round`, #pieces > 0 and unique and onPivot and round)
	-- the opening lies on the bag: under the grip, its bottom over the bag's lowest point, within its body
	local low, wide, long = 0, 0, 0
	for _, piece in KitArt.pieces(def.id) do
		low = math.min(low, piece.at[2] - piece.size[2] / 2)
		if piece.at[2] < mouth.y then
			wide = math.max(wide, 2 * (math.abs(piece.at[1]) + halfX(piece)))
			long = math.max(long, math.abs(piece.at[3]) * 2 + piece.size[3])
		end
	end
	check(`{def.id}: the opening on the bag, its bottom inside it`, mouth.y < 0 and floor > low and mouth.x <= wide and mouth.z <= long + 1e-6, `{mouth.y} {floor} {low} {wide} {long}`)
	-- real size: it holds its room of everyday pieces (a small box, 0.35 × 0.35 × 0.5: 12 × 12 × 17 cm)
	local volume = mouth.x * mouth.z * (mouth.d or 0)
	check(`{def.id}: room inside for its {room} pieces`, volume >= room * 0.35 * 0.35 * 0.5, volume)
	-- the swell: only the body (under the opening) grows, across by its bulge when full; a cylinder stays round
	local art = KitArt.pieces(def.id)
	local swollen = BagFill.swell(art, mouth, room, room)
	local grew, kept, roundBody = false, true, true
	for i, piece in art do
		local after = swollen[i]
		if piece.at[2] < mouth.y then
			grew = grew or halfX(after) > halfX(piece) + 1e-9 or math.abs(after.at[1]) > math.abs(piece.at[1]) + 1e-9
			if piece.shape == "Cylinder" then
				roundBody = roundBody and math.abs(after.size[2] - after.size[3]) < 1e-9
					and math.abs((after.at[2] + after.size[2] / 2) - (piece.at[2] + piece.size[2] / 2)) < 1e-9
			end
		else
			kept = kept and after == piece
		end
	end
	check(`{def.id}: full, its body swells, the handles do not`, grew and kept)
	check(`{def.id}: a cylinder swells round, its top where it was`, roundBody)
	check(`{def.id}: empty, it is as it was`, BagFill.swell(art, mouth, 0, room) == art)
end

-- The real sizes of the bags (the owner's 6.7 targets, ±25 %): the body's outside, handles and straps left out.
local targets: { [string]: { number } } = {
	bag = { 0.6, 1.3, 1.15 },
	tote = { 0.35, 1.15, 1.15 },
	thermal = { 1.15, 1.15, 1.3 },
	padded = { 0.45, 0.85, 1.15 },
	duffel = { 1.0, 1.0, 2.0 },
}
local bodies2: { [string]: string } = { bag = "BagBody", tote = "ToteBody", thermal = "ThermBody", padded = "MessBody", duffel = "DuffBody" }
for id, want in targets do
	local body: any = nil
	for _, piece in KitArt.pieces(id) do
		if piece.name == bodies2[id] then
			body = piece
		end
	end
	local size = if body then (if body.shape == "Cylinder" then { body.size[2], body.size[3], body.size[1] } else body.size) else { 0, 0, 0 }
	local near = true
	for i = 1, 3 do
		near = near and size[i] >= want[i] * 0.75 and size[i] <= want[i] * 1.25
	end
	check(`{id}: a real-size body ({table.concat(size, " × ")} studs)`, near)
end

-- How it packs
local thermal = B.Mouth.thermal
local pizzas = BagFill.layout(thermal, 4, 4, { "pizza", "pizza", "pizza", "pizza" })
local flat, column = true, true
for _, spot in pizzas do
	flat = flat and spot.axes[2] == 2 and math.abs(spot.sy - 0.12) < 1e-9
	column = column and spot.x == pizzas[1].x and spot.z == pizzas[1].z
end
local highest = -math.huge
for _, spot in pizzas do
	highest = math.max(highest, spot.y + spot.sy / 2)
end
check("four pizza boxes lie flat in the thermal bag, stacked", flat and column)
check("… the top one at the rim, seen through the open lid", highest >= thermal.y and highest <= thermal.y + 0.06, highest)
local edge = BagFill.layout(plastic, 1, 2, { "pizza" })[1]
check("a pizza box stands on its edge in the plastic bag (too wide to lie flat)", edge.axes[2] ~= 2 and math.abs(edge.sx - 0.12) < 1e-9 and edge.scale == 1)
local two = BagFill.layout(B.Mouth.duffel, 2, 6, { "parcel", "parcel" })
check("two parcels side by side along the duffel", two[1].layer == 1 and two[2].layer == 1 and two[1].x == two[2].x and math.abs(two[1].z - two[2].z) > 0.5)
local flowers = BagFill.layout(plastic, 1, 2, { "bouquet" })[1]
check("a bouquet stands, its top 40 % out of the bag", flowers.axes[2] == 2 and math.abs((flowers.y + flowers.sy / 2 - plastic.y) / flowers.sy - 0.4) < 1e-6)
local newest = BagFill.layout(B.Mouth.duffel, 3, 6, { "parcel", "parcel", "cake" })
local cakeOnTop = false
for _, spot in newest do
	cakeOnTop = cakeOnTop or (spot.kind == "cake" and spot.layer == 1)
end
check("the last one put in lies on top", cakeOnTop)
local leaning = BagFill.layout(plastic, 2, 2, { "bouquet", "mail" })
check("loose ones lean a little, opposite ways", leaning[1].tilt == -leaning[2].tilt and leaning[1].tilt ~= 0 and math.abs(leaning[1].tilt) <= 5)

-- The open lid
local lid = BagFill.open(KitArt.pieces("thermal"), KitArt.open.thermal)
local moved, others = false, true
for i, piece in KitArt.pieces("thermal") do
	if piece.name == "ThermLid" then
		moved = lid[i].at[2] > piece.at[2] + 0.3 and lid[i].turn ~= nil and lid[i].turn[1] > 90
	else
		others = others and lid[i].name == piece.name and lid[i].at[2] == piece.at[2]
	end
end
check("loaded, the thermal bag's lid stands open, nothing else moves", moved and others)
local same = KitArt.pieces("bag")
check("a bag without a lid: as it was", BagFill.open(same, KitArt.open.bag) == same)

check("the bulge: none empty, the bag's own amount full", BagFill.bulge(0, 4) == 1 and BagFill.bulge(4, 4) == 1 + B.Bulge and BagFill.bulge(4, 4, 0.1) == 1.1
	and BagFill.bulge(2, 4) < BagFill.bulge(4, 4) and B.Bulge <= 0.25)
check("the bulge never past full", BagFill.bulge(9, 4) == BagFill.bulge(4, 4) and BagFill.bulge(3, 0) == 1)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
