-- 6.4.1, the bag shows and what is in it shows (shared/BagFill.luau, shared/KitFit.luau's bag key and grip,
-- server/KitWear.luau): the worn bag's slot key gives KitArt a look it knows (6.4 asked for "bag@hand" and no bag was
-- ever built), every bag in every way of wearing it rests close to the hand / the torso it hangs on, on the courier's
-- R15 body and on an R6 body, and the pieces in it stick out of its opening as small shapes of their looks, up to its
-- room, while its body swells a little. Run with tests/run_tests.py.
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

check("the key of a bag in the hand", KitFit.bagKey("bag", "hand") == "bag@hand")
check("6.6: the key of a slung duffel (no backpack mark any more)", KitFit.bagKey("duffel", "back") == "duffel@back")
for _, def in bags do
	for _, place in { "hand", "shoulder", "hip", "back", "hipBack" } do
		local key = KitFit.bagKey(def.id, place)
		local id, at = KitFit.parseBagKey(key)
		local ok = pcall(KitArt.pieces, id :: string)
		check(`{key}: back to its bag and place, a look KitArt knows`, id == def.id and at == place and ok)
	end
end
check("not a key: nil", KitFit.parseBagKey("bag") == nil and KitFit.parseBagKey("") == nil and KitFit.parseBagKey("duffel@back+") == nil)
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
			do
				local spot = Config.Courier.BagPlaces[place]
				local partName = if spot then spot.part else "LeftHand"
				local part = body.parts[partName]
				local at, turn = KitFit.bagGrip(def.id, place, partName, part.size)
				local mouth = Config.Courier.BagFill.Mouth[def.id]
				local full = BagFill.swell(KitArt.pieces(def.id), mouth, def.extra or 0, def.extra or 0)
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
				local label = `{body.name}, {def.id} {place}`
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
local handAt = KitFit.bagGrip("bag", "hand", "LeftHand", { 1, 0.3, 1 })
check("the plastic bag's grip just under the R15 hand", math.abs(handAt[2] - (-0.15 - Config.Courier.Bag.Grip)) < 1e-9 and handAt[1] == 0, handAt[2])
local armAt = KitFit.bagGrip("bag", "hand", "LeftHand", { 1, 2, 1 })
check("… and under the bottom of an R6 Left Arm", math.abs(armAt[2] - (-1 - Config.Courier.Bag.Grip)) < 1e-9, armAt[2])
local thermalAt = KitFit.bagGrip("thermal", "hand", "LeftHand", { 1, 0.3, 1 })
check("the thermal bag a little further out", thermalAt[1] < 0)
local shoulder = KitFit.bagGrip("tote", "shoulder", "UpperTorso", { 2, 1.6, 1 })
local shoulderR6 = KitFit.bagGrip("tote", "shoulder", "UpperTorso", { 2, 2, 1 })
check("the tote's shoulder spot on the top of the torso, R15 and R6 (scaled to the taller Torso)", math.abs(shoulder[2] - 0.8) < 1e-9 and math.abs(shoulderR6[2] - 1) < 1e-9, `{shoulder[2]} {shoulderR6[2]}`)
local slung = KitFit.bagGrip("duffel", "back", "UpperTorso", { 2, 1.6, 1 })
local back = Config.Courier.BagPlaces.back
check("6.6: a slung bag hangs at its place on the back (no backpack to push it)", math.abs(slung[3] - back.at[3]) < 1e-9 and (Config.Courier :: any).PackPush == nil, slung[3])

-- What is in the bag ---------------------------------------------------------------------------------------------

check("the looks attribute", table.concat(BagFill.looks("pizza,bouquet"), "|") == "pizza|bouquet" and #BagFill.looks(nil) == 0 and #BagFill.looks("") == 0)
check("a pizza is a pizza box", BagFill.kind("pizza") == "pizza")
check("a bouquet", BagFill.kind("bouquet") == "bouquet")
check("mail, a newspaper, documents", BagFill.kind("mail") == "mail" and BagFill.kind("newspaper") == "paper" and BagFill.kind("documents") == "folder")
check("a burger, noodles: a food box", BagFill.kind("burger") == "food" and BagFill.kind("noodles") == "food")
check("anything else, or nothing known: a parcel", BagFill.kind("crate") == "parcel" and BagFill.kind(nil) == "parcel")
for look in Config.Cargo.LightLooks do
	check(`light look {look}: a shape`, BagFill.Shapes[BagFill.kind(look)] ~= nil)
end

local plastic = Config.Courier.BagFill.Mouth.bag
check("an empty bag shows nothing", #BagFill.layout(plastic, 0, 2, nil) == 0 and #BagFill.pieces(plastic, 0, 2, nil) == 0)
check("never more than its room", #BagFill.layout(plastic, 5, 2, nil) == 2)
check("never more than Max", #BagFill.layout(Config.Courier.BagFill.Mouth.duffel, 20, 20, nil) == Config.Courier.BagFill.Max)
local two = BagFill.layout(plastic, 2, 2, { "pizza" })
check("two pieces: the pizza box, then a parcel (no look known)", two[1].kind == "pizza" and two[2].kind == "parcel")
check("one row along the opening, front and back", two[1].x == 0 and two[2].x == 0 and two[1].z < 0 and two[2].z > 0)
check("they lean opposite ways", two[1].tilt == -two[2].tilt and two[1].tilt ~= 0)
local six = BagFill.layout(Config.Courier.BagFill.Mouth.duffel, 6, 6, nil)
check("six in the duffel: two rows side by side", six[1].x < 0 and six[2].x > 0 and six[1].z == six[2].z)

for _, def in bags do
	local mouth = Config.Courier.BagFill.Mouth[def.id]
	check(`{def.id}: its opening`, mouth ~= nil)
	if not mouth then
		continue
	end
	-- the opening lies on the bag: under the grip, over its lowest piece, within its body's width and length
	local low, wide, long = 0, 0, 0
	for _, piece in KitArt.pieces(def.id) do
		low = math.min(low, piece.at[2])
		if piece.at[2] < mouth.y then
			wide = math.max(wide, 2 * (math.abs(piece.at[1]) + halfX(piece)))
			long = math.max(long, math.abs(piece.at[3]) * 2 + piece.size[3])
		end
	end
	check(`{def.id}: the opening on the bag`, mouth.y < 0 and mouth.y > low and mouth.x <= wide and mouth.z <= long + 1e-6, `{mouth.y} {low} {wide} {long}`)
	for n = 1, def.extra or 0 do
		local looks = { "pizza", "bouquet", "mail", "newspaper", "bread", "cake" }
		local inside = true
		local out = true
		local why = ""
		for _, spot in BagFill.layout(mouth, n, def.extra or 0, looks) do
			local shape = BagFill.Shapes[spot.kind]
			local s = spot.scale
			if math.abs(spot.x) + shape.x * s / 2 > mouth.x / 2 + 1e-6 or math.abs(spot.z) + shape.z * s / 2 > mouth.z / 2 + 1e-6 then
				inside = false
				why = `{spot.kind} at {spot.x}, {spot.z}`
			end
			if not (spot.y < mouth.y and spot.y + shape.h * s > mouth.y + 0.05) then
				out = false
			end
		end
		check(`{def.id}, {n} in it: each within the opening`, inside, why)
		check(`{def.id}, {n} in it: each sticks out of it`, out)
	end
	local pieces = BagFill.pieces(mouth, def.extra or 0, def.extra or 0, nil)
	local names: { [string]: boolean } = {}
	local unique, onPivot = true, true
	for _, piece in pieces do
		unique = unique and not names[piece.name]
		names[piece.name] = true
		onPivot = onPivot and piece.attach == "BagPivot"
	end
	check(`{def.id}: the shapes' parts, named once each, on the pivot`, #pieces > 0 and unique and onPivot)
	-- the swell: only the body (under the opening) grows, across by Bulge when full
	local art = KitArt.pieces(def.id)
	local swollen = BagFill.swell(art, mouth, def.extra or 0, def.extra or 0)
	local grew, kept = false, true
	for i, piece in art do
		local after = swollen[i]
		if piece.at[2] < mouth.y then
			grew = grew or halfX(after) > halfX(piece) + 1e-9 or math.abs(after.at[1]) > math.abs(piece.at[1]) + 1e-9
		else
			kept = kept and after == piece
		end
	end
	check(`{def.id}: full, its body swells, the handles do not`, grew and kept)
	check(`{def.id}: empty, it is as it was`, BagFill.swell(art, mouth, 0, def.extra or 0) == art)
end
check("the bulge: none empty, 10–20 % full", BagFill.bulge(0, 4) == 1 and BagFill.bulge(4, 4) >= 1.1 and BagFill.bulge(4, 4) <= 1.2 and BagFill.bulge(2, 4) < BagFill.bulge(4, 4))
check("the bulge never past full", BagFill.bulge(9, 4) == BagFill.bulge(4, 4) and BagFill.bulge(3, 0) == 1)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
