--!strict
-- Pure R15 courier kit and personal sack-truck skins. Local offsets belong to the named caller-owned target.
-- 6.0 (Claude's placeholders until Codex's nicer models): "bag", the plastic carrier bag, on BagPivot (a part hung
-- from the left hand by server/KitWear.luau: the origin is the grip, the bag hangs down -Y, its broad sides face
-- out along ±X); "kevlar" (a dark vest with plates) and "heavy" (a bulky armoured vest with shoulder guards) over the
-- courier's own vest. Geometry.translucent: the see-through pieces (the bag's plastic) and how much.
-- 6.4 (Claude's placeholders, the same frame as "bag": the grip at the origin, hanging -Y, the broad sides out along ±X,
-- -X the outer side; the R15 hand holds it about 1.95 above the ground, so nothing reaches lower than -1.7):
-- "tote" a beige canvas tote on two long webbing handles, "thermal" the boxy red insulated food bag with a black lid,
-- base and ZDC patch, "padded" a grey messenger bag with a dark flap, held by its strap, "duffel" a big dark-green
-- duffel (a lying cylinder) on its two carry handles, a shoulder strap along its side. 1 stud ≈ 35 cm of the courier.
-- 6.7, real-size bags (the owner: "the bag is small, the things would never really fit in it"): every bag is the size
-- of the real product (the plastic bag 40 × 45 × 20 cm, the tote 40 × 40 × 13, the thermal food bag 45 × 37 × 38, the
-- messenger 40 × 30 × 15, the duffel 70 cm long and 35 across), with handles of some thickness, seams and hems, a
-- closure (a zip, a lid, a flap), the ZDC print or patch and straps. Still the grip at the origin, hanging -Y: a bag in
-- the hand reaches at most 1.55 under it (the R15 hand's grip is ~1.9 over the ground: tools/character-art/bag-check
-- measures the clearance on the real body), the tote and the messenger hang from the shoulder / the strap's crossing.
-- Geometry.open: the pieces that move when the bag holds something (the thermal bag's lid stands open behind its
-- straps: shared/BagFill.luau's pieces lie in it, seen through the open top).
local Geometry = {}
type V = { number }
type Piece = { name: string, size: V, at: V, attach: string, finish: string, turn: V?, shape: string?, shadow: boolean?, text: string? }
Geometry.ids = { "backpack", "backpack_loaded", "bigpack", "shoes", "jacket", "cart", "bag", "kevlar", "heavy", "tote", "thermal", "padded", "duffel" }
Geometry.bags = { bag = true, tote = true, thermal = true, padded = true, duffel = true } :: { [string]: boolean } -- 6.4: hung on BagPivot
Geometry.translucent = { BagBody = .12, BagBottom = .06, BagKnot = .1, BagHandleF = .1, BagHandleB = .1 } :: { [string]: number } -- (6.4.1: was .3 / .15)
-- 6.7: per bag, the pieces that move while it holds something: their place and turn then (server/KitWear.luau, through
-- BagFill.open). The thermal bag's lid, hinged at the top of its back end, stands open (105°) behind the straps.
Geometry.open = {
	thermal = { ThermLid = { at = { 0, .21, .82 }, turn = { 105, 0, 0 } } },
} :: { [string]: { [string]: { at: V, turn: V } } }
local function add(out: { Piece }, name: string, size: V, at: V, attach: string, finish: string, shape: string?, turn: V?, text: string?)
	table.insert(out, { name = name, size = size, at = at, attach = attach, finish = finish, shape = shape, turn = turn, text = text, shadow = name == "PackBody" or name == "BoxBody" })
end
function Geometry.load(): Piece
	return { name = "VisibleLightParcel", size = { .84, .64, .42 }, at = { 0, .87, 1.03 }, attach = "UpperTorso", finish = "parcel", shadow = true }
end
function Geometry.pieces(id: string): { Piece }
	local out: { Piece } = {}
	if id == "backpack" or id == "backpack_loaded" then
		add(out, "PackBody", { 1.46, 1.6, .54 }, { 0, -.08, 1 }, "UpperTorso", "cloth")
		add(out, "BottomReinforcement", { 1.46, .18, .58 }, { 0, -.85, 1 }, "UpperTorso", "sole")
		add(out, "FoldedTop", { 1.46, .23, .5 }, { 0, .67, 1.01 }, "UpperTorso", "charcoal", "Wedge", { 0, 180, 0 })
		add(out, "FrontPocket", { 1.22, .62, .18 }, { 0, -.32, 1.35 }, "UpperTorso", "cloth")
		add(out, "CourierStripe", { 1.2, .1, .035 }, { 0, -.06, 1.455 }, "UpperTorso", "red")
		add(out, "Zip", { 1.05, .035, .04 }, { 0, .01, 1.45 }, "UpperTorso", "steel")
		add(out, "ZipPull", { .07, .12, .045 }, { .46, -.03, 1.465 }, "UpperTorso", "steel")
		add(out, "BackLabel", { .52, .18, .03 }, { 0, .33, 1.285 }, "UpperTorso", "charcoal", nil, { 0, 180, 0 }, "ZDC")
		for _, x in { -.47, .47 } do
			local side = if x < 0 then "L" else "R"
			add(out, "ShoulderStrap" .. side, { .15, 1.35, .07 }, { x, -.04, -.69 }, "UpperTorso", "sole")
			add(out, "Buckle" .. side, { .18, .13, .08 }, { x, -.42, -.76 }, "UpperTorso", "worn")
		end
		add(out, "GrabLoop", { .45, .08, .09 }, { 0, .89, 1.02 }, "UpperTorso", "sole")
		if id == "backpack_loaded" then table.insert(out, Geometry.load()) end
	elseif id == "bigpack" then
		add(out, "BoxBody", { 1.84, 1.88, .82 }, { 0, -.1, 1.04 }, "UpperTorso", "cloth")
		add(out, "Lid", { 1.9, .13, .86 }, { 0, .91, 1.04 }, "UpperTorso", "charcoal")
		add(out, "ThermalBase", { 1.9, .12, .86 }, { 0, -1.05, 1.04 }, "UpperTorso", "sole")
		add(out, "Flap", { 1.64, .4, .06 }, { 0, .65, 1.485 }, "UpperTorso", "cloth")
		add(out, "RedBand", { 1.8, .12, .04 }, { 0, .1, 1.48 }, "UpperTorso", "red")
		add(out, "LogoPanel", { .88, .33, .035 }, { 0, -.38, 1.48 }, "UpperTorso", "charcoal", nil, { 0, 180, 0 }, "ZDC / FOOD")
		add(out, "ReflectiveBand", { 1.72, .045, .04 }, { 0, -.77, 1.48 }, "UpperTorso", "reflector")
		for _, x in { -.87, .87 } do
			local side = if x < 0 then "L" else "R"
			add(out, "Edge" .. side, { .08, 1.75, .06 }, { x, -.1, 1.49 }, "UpperTorso", "sole")
			add(out, "Closure" .. side, { .08, .24, .07 }, { x * .78, .3, 1.52 }, "UpperTorso", "steel")
			add(out, "ShoulderStrap" .. side, { .18, 1.45, .07 }, { x * .54, -.06, -.69 }, "UpperTorso", "sole")
			add(out, "Buckle" .. side, { .2, .15, .08 }, { x * .54, -.48, -.76 }, "UpperTorso", "worn")
		end
		add(out, "TopHandle", { .46, .08, .1 }, { 0, 1.04, 1.04 }, "UpperTorso", "sole")
	elseif id == "shoes" then
		for _, foot in { "LeftFoot", "RightFoot" } do
			add(out, foot .. "Sole", { 1.05, .14, 1.42 }, { 0, -.23, -.08 }, foot, "sole")
			add(out, foot .. "Upper", { 1.03, .3, 1.2 }, { 0, -.05, -.12 }, foot, "cloth")
			add(out, foot .. "Toe", { 1.03, .17, .32 }, { 0, -.03, -.67 }, foot, "charcoal", "Wedge")
			add(out, foot .. "HeelTab", { .42, .12, .055 }, { 0, .08, .5 }, foot, "red")
		end
	elseif id == "jacket" then
		for _, x in { -.47, .47 } do
			local side = if x < 0 then "L" else "R"
			add(out, "Chest" .. side, { .84, 1.35, .085 }, { x, -.08, -.57 }, "UpperTorso", "cloth")
			add(out, "Pocket" .. side, { .52, .32, .07 }, { x, -.4, -.65 }, "UpperTorso", "charcoal")
			add(out, "Collar" .. side, { .44, .23, .09 }, { x * .6, .68, -.52 }, "UpperTorso", "sole", nil, { 0, 0, x * 18 })
			add(out, "Reflector" .. side, { .71, .055, .04 }, { x, .32, -.64 }, "UpperTorso", "reflector")
			add(out, "Sleeve" .. side, { .09, .7, .62 }, { math.sign(x) * .49, .04, 0 }, if x < 0 then "LeftUpperArm" else "RightUpperArm", "cloth")
		end
		add(out, "BackPanel", { 1.76, 1.3, .08 }, { 0, -.1, .56 }, "UpperTorso", "cloth")
		add(out, "FrontZip", { .045, 1.32, .04 }, { 0, -.08, -.64 }, "UpperTorso", "steel")
		add(out, "RedChestTab", { .16, .11, .03 }, { -.49, .15, -.66 }, "UpperTorso", "red")
	elseif id == "cart" then
		add(out, "ToePlate", { 1.65, .15, 1.4 }, { 0, .24, -.54 }, "Frame", "steel")
		add(out, "BackRest", { 1.42, .22, .13 }, { 0, 1.7, .05 }, "Frame", "red")
		for _, x in { -.65, .65 } do
			local side = if x < 0 then "L" else "R"
			add(out, "Rail" .. side, { 3.05, .12, .12 }, { x, 1.84, .05 }, "Frame", "red", "Cylinder", { 0, 0, 90 })
			add(out, "HandleRise" .. side, { .4, .12, .12 }, { x, 3.46, .16 }, "Frame", "red", "Cylinder", { 60, 0, 90 })
			add(out, "ToeEdge" .. side, { .06, .2, 1.25 }, { x * 1.18, .4, -.53 }, "Frame", "charcoal")
			add(out, "Tyre" .. side, { .26, 1.08, 1.08 }, { 0, 0, 0 }, if x < 0 then "LeftWheel" else "RightWheel", "sole", "Cylinder")
			add(out, "Hub" .. side, { .3, .38, .38 }, { 0, 0, 0 }, if x < 0 then "LeftWheel" else "RightWheel", "steel", "Cylinder")
		end
		for n, y in { .72, 1.18, 2.45 } do add(out, "Crossbar" .. n, { 1.35, .11, .11 }, { 0, y, .05 }, "Frame", "red", "Cylinder") end
		add(out, "Handle", { 1.34, .12, .12 }, { 0, 3.57, .26 }, "Frame", "steel", "Cylinder")
		add(out, "Grip", { 1.12, .17, .17 }, { 0, 3.57, .26 }, "Frame", "sole", "Cylinder")
		add(out, "Axle", { 1.85, .13, .13 }, { 0, .59, .2 }, "Frame", "steel", "Cylinder")
	elseif id == "bag" then
		-- 6.7: a real carrier bag, 40 × 45 × 20 cm (the owner: "the bag is small, the things would never fit in it"): a
		-- gusseted body, a welded hem round its open top, the two handles rising from its corners into the fist, a red
		-- ZDC stripe and the ZDC print on both sides. (6.4.1: a light-tinted plastic, a little see-through)
		add(out, "BagKnot", { .2, .12, .34 }, { 0, -.03, 0 }, "BagPivot", "bagplastic")
		add(out, "BagHandleF", { .22, .52, .06 }, { 0, -.21, -.23 }, "BagPivot", "bagplastic", nil, { 46, 0, 0 })
		add(out, "BagHandleB", { .22, .52, .06 }, { 0, -.21, .23 }, "BagPivot", "bagplastic", nil, { -46, 0, 0 })
		add(out, "BagBody", { .56, 1.12, 1.1 }, { 0, -.94, 0 }, "BagPivot", "bagplastic")
		add(out, "BagBottom", { .6, .06, 1.14 }, { 0, -1.5, 0 }, "BagPivot", "bagplastic")
		add(out, "BagMouth", { .5, .02, 1.04 }, { 0, -.37, 0 }, "BagPivot", "foam") -- (the open top: its shadowed inside)
		add(out, "BagStripe", { .58, .09, 1.12 }, { 0, -.56, 0 }, "BagPivot", "red")
		for _, z in { -1, 1 } do
			-- the side gussets: the folded-in ends of the bag, a darker crease down each
			add(out, if z < 0 then "BagGussetF" else "BagGussetB", { .3, 1.04, .025 }, { 0, -.96, z * .555 }, "BagPivot", "reflector")
		end
		for _, x in { -.29, .29 } do
			add(out, if x < 0 then "BagPrintL" else "BagPrintR", { .52, .34, .02 }, { x, -.98, 0 }, "BagPivot", "red", nil, { 0, if x < 0 then 90 else -90, 0 }, "ZDC")
		end
	elseif id == "tote" then
		-- 6.7: a real canvas tote, 40 × 40 × 13 cm, on two long handles over the shoulder (a hand's drop of 22 cm: the
		-- bag at the hip, under the arm): one handle on each broad side, sewn on at two points; a hem round the top, the
		-- side seams, the ZDC print on both sides.
		add(out, "ToteBody", { .38, 1.12, 1.12 }, { 0, -1.2, 0 }, "BagPivot", "canvas")
		add(out, "ToteHem", { .4, .07, 1.14 }, { 0, -.68, 0 }, "BagPivot", "parcel")
		add(out, "ToteMouth", { .32, .02, 1.06 }, { 0, -.635, 0 }, "BagPivot", "cloth")
		add(out, "ToteBottom", { .4, .07, 1.14 }, { 0, -1.74, 0 }, "BagPivot", "parcel")
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				-- each end of a handle runs from the shoulder down to its stitch at (x .19, y -.64, z .3)
				add(out, `ToteStrap{if x < 0 then "O" else "I"}{if z < 0 then "F" else "B"}`, { .05, .73, .1 }, { x * .095, -.32, z * .15 }, "BagPivot", "parcel", nil, { -z * 25, 0, x * 15 })
			end
			add(out, if x < 0 then "TotePrintO" else "TotePrintI", { .6, .38, .02 }, { x * .195, -1.16, 0 }, "BagPivot", "red", nil, { 0, if x < 0 then 90 else -90, 0 }, "ZDC")
			add(out, if x < 0 then "ToteSeamF" else "ToteSeamB", { .4, 1.08, .03 }, { 0, -1.2, x * .565 }, "BagPivot", "parcel")
		end
		add(out, "ToteGrip", { .2, .08, .3 }, { 0, -.03, 0 }, "BagPivot", "parcel")
	elseif id == "thermal" then
		-- 6.7: a real insulated food-delivery bag, 45 × 37 × 38 cm: red nylon, a black zip-round lid, a black base, a
		-- mesh pocket at the front, a black ZDC patch and a reflective band on both sides, two straps from the sides to
		-- a padded grip. Loaded, its lid stands open behind the straps (Geometry.open; shared/BagFill.luau): the pizza
		-- boxes lie flat in it, the top one at the rim.
		add(out, "ThermBody", { 1.1, .88, 1.26 }, { 0, -.96, 0 }, "BagPivot", "red")
		add(out, "ThermLid", { 1.14, .1, 1.3 }, { 0, -.47, 0 }, "BagPivot", "sole")
		add(out, "ThermBase", { 1.14, .08, 1.3 }, { 0, -1.43, 0 }, "BagPivot", "sole")
		add(out, "ThermZip", { 1.12, .03, 1.28 }, { 0, -.535, 0 }, "BagPivot", "steel")
		add(out, "ThermInside", { 1.04, .02, 1.2 }, { 0, -.51, 0 }, "BagPivot", "sole") -- (under the lid: seen when it is open)
		for _, x in { -1, 1 } do
			local side = if x < 0 then "O" else "I"
			add(out, "ThermPatch" .. side, { .62, .34, .03 }, { x * .56, -.9, 0 }, "BagPivot", "sole", nil, { 0, if x < 0 then 90 else -90, 0 }, "ZDC")
			add(out, "ThermReflector" .. side, { .02, .06, 1.2 }, { x * .556, -1.22, 0 }, "BagPivot", "reflector")
			add(out, "ThermHandle" .. side, { .06, .56, .18 }, { x * .255, -.235, 0 }, "BagPivot", "sole", nil, { 0, 0, x * 46 })
		end
		add(out, "ThermPocket", { .8, .42, .06 }, { 0, -1.04, -.66 }, "BagPivot", "cloth")
		add(out, "ThermGrip", { .14, .12, .26 }, { 0, -.04, 0 }, "BagPivot", "sole")
	elseif id == "padded" then
		-- 6.7: a real messenger bag, 40 × 30 × 15 cm, of courier-blue nylon, foam-padded: its dark flap over the outer
		-- side (rolled over the top edge), a zip along the open top, two buckles, a reflective strip, the strap's two ends
		-- up to the pad where the strap crosses (the pivot).
		add(out, "MessBody", { .42, .86, 1.15 }, { 0, -1.0, 0 }, "BagPivot", "nylon")
		add(out, "MessFlap", { .05, .64, 1.18 }, { -.235, -.88, 0 }, "BagPivot", "cloth")
		add(out, "MessFlapTop", { .1, .06, 1.18 }, { -.2, -.565, 0 }, "BagPivot", "cloth")
		add(out, "MessZip", { .04, .03, 1.06 }, { .17, -.565, 0 }, "BagPivot", "steel")
		add(out, "MessMouth", { .28, .02, 1.06 }, { 0, -.565, 0 }, "BagPivot", "sole")
		add(out, "MessReflector", { .02, .05, .9 }, { -.262, -.68, 0 }, "BagPivot", "reflector")
		add(out, "MessPadSeam", { .02, .05, 1.1 }, { .215, -1.0, 0 }, "BagPivot", "worn")
		add(out, "MessBottom", { .44, .05, 1.17 }, { 0, -1.43, 0 }, "BagPivot", "cloth")
		add(out, "MessLabel", { .44, .16, .02 }, { -.262, -.92, .22 }, "BagPivot", "sole", nil, { 0, 90, 0 }, "ZDC")
		for _, z in { -1, 1 } do
			local tip = if z < 0 then "F" else "B"
			add(out, "MessBuckle" .. tip, { .04, .14, .1 }, { -.265, -1.18, z * .34 }, "BagPivot", "steel")
			-- the strap's end from the pad down to the bag's end (z .5, y -.57)
			add(out, "MessStrap" .. tip, { .07, .62, .13 }, { 0, -.3, z * .26 }, "BagPivot", "sole", nil, { -z * 43, 0, 0 })
		end
		add(out, "MessStrapPad", { .14, .12, .32 }, { 0, -.04, 0 }, "BagPivot", "sole")
	elseif id == "duffel" then
		-- 6.7: a real 70 cm duffel, 35 cm across, of army-green cloth lying along your way: black end caps, two
		-- reinforcing bands the carry handles are sewn to, a zip along the top (open when loaded: the pieces show in
		-- it), a side pocket with the ZDC label, the shoulder strap clipped along its outer side.
		add(out, "DuffBody", { 2.0, 1.0, 1.0 }, { 0, -.88, 0 }, "BagPivot", "olive", "Cylinder", { 0, 90, 0 })
		for _, z in { -1, 1 } do
			local tip = if z < 0 then "F" else "B"
			add(out, "DuffEnd" .. tip, { .06, 1.02, 1.02 }, { 0, -.88, z * 1.0 }, "BagPivot", "sole", "Cylinder", { 0, 90, 0 })
			add(out, "DuffBand" .. tip, { .1, 1.03, 1.03 }, { 0, -.88, z * .45 }, "BagPivot", "sole", "Cylinder", { 0, 90, 0 })
			-- the handle from the band's top (z .45, y -.38) up to the fist
			add(out, "DuffHandle" .. tip, { .12, .51, .06 }, { 0, -.215, z * .255 }, "BagPivot", "sole", nil, { -z * 50, 0, 0 })
			add(out, "DuffClip" .. tip, { .06, .1, .06 }, { -.465, -.66, z * .88 }, "BagPivot", "steel")
		end
		add(out, "DuffZip", { .04, .03, 1.7 }, { .16, -.39, 0 }, "BagPivot", "steel")
		add(out, "DuffMouth", { .3, .02, 1.62 }, { 0, -.385, 0 }, "BagPivot", "sole") -- (the zip open along its top)
		add(out, "DuffZipPull", { .06, .14, .05 }, { 0, -.43, -.86 }, "BagPivot", "steel")
		add(out, "DuffStrap", { .04, .06, 1.76 }, { -.47, -.66, 0 }, "BagPivot", "sole")
		add(out, "DuffPocket", { .06, .42, .7 }, { -.5, -.95, 0 }, "BagPivot", "olive")
		add(out, "DuffLabel", { .5, .18, .02 }, { -.535, -.95, 0 }, "BagPivot", "sole", nil, { 0, 90, 0 }, "ZDC")
		add(out, "DuffGrip", { .16, .12, .2 }, { 0, -.05, 0 }, "BagPivot", "sole")
	elseif id == "kevlar" or id == "heavy" then
		local heavy = id == "heavy"
		local w, h, d = if heavy then 1.98 else 1.88, if heavy then 1.45 else 1.32, if heavy then .2 else .12
		local z = if heavy then .66 else .63
		add(out, "VestFront", { w, h, d }, { 0, -.12, -z }, "UpperTorso", "charcoal")
		add(out, "VestBack", { w, h, d }, { 0, -.12, z }, "UpperTorso", "charcoal")
		for _, x in { -1, 1 } do
			local side = if x < 0 then "L" else "R"
			add(out, "VestSide" .. side, { .14, h - .2, z * 2 }, { x * (w / 2 + .02), -.18, 0 }, "UpperTorso", "charcoal")
			add(out, "VestStrap" .. side, { .42, .12, z * 2 + d }, { x * .55, .6, 0 }, "UpperTorso", "sole")
			add(out, "Velcro" .. side, { .5, .08, .04 }, { x * .5, -.62, -(z + d / 2 + .02) }, "UpperTorso", "sole")
		end
		local plate = if heavy then "steel" else "worn"
		add(out, "PlateFront", { if heavy then 1.3 else 1.1, if heavy then 1 else .8, .08 }, { 0, -.04, -(z + d / 2 + .04) }, "UpperTorso", plate)
		add(out, "PlateBack", { if heavy then 1.3 else 1.1, if heavy then 1 else .8, .08 }, { 0, -.04, z + d / 2 + .04 }, "UpperTorso", plate)
		add(out, "VestTag", { .62, .16, .03 }, { 0, .32, -(z + d / 2 + .1) }, "UpperTorso", "reflector")
		if heavy then
			add(out, "CollarFront", { 1.1, .26, .2 }, { 0, .78, -.6 }, "UpperTorso", "charcoal")
			add(out, "CollarBack", { 1.1, .26, .2 }, { 0, .78, .6 }, "UpperTorso", "charcoal")
			add(out, "Flap", { 1.2, .42, .14 }, { 0, -.98, -.7 }, "UpperTorso", "charcoal")
			for _, arm in { "LeftUpperArm", "RightUpperArm" } do
				local tilt = if arm == "LeftUpperArm" then 12 else -12
				add(out, arm .. "Guard", { 1.12, .56, 1.12 }, { 0, .36, 0 }, arm, "charcoal", nil, { 0, 0, tilt })
				add(out, arm .. "GuardPlate", { 1.16, .12, 1.16 }, { 0, .62, 0 }, arm, "steel", nil, { 0, 0, tilt })
			end
		end
	else error("Unknown kit id: " .. id) end
	return out
end
-- 6.4: the strap of a worn bag on the UpperTorso (Config.Courier.BagPlaces; server/KitWear.luau fits it to the body):
-- the messenger's cross-body strap (the right shoulder to the left hip, front and back) on the hip or behind it, a
-- slung tote's or duffel's strap across the chest (the left shoulder to the right hip), the tote's handles over the
-- left shoulder. None for a bag in the hand.
function Geometry.straps(id: string, place: string): { Piece }
	local out: { Piece } = {}
	local finish = if id == "tote" then "parcel" else "sole"
	if id == "padded" and (place == "hip" or place == "hipBack") then
		add(out, "CrossStrapFront", { .14, 2.2, .04 }, { -.05, 0, -.53 }, "UpperTorso", finish, nil, { 0, 0, -45 })
		add(out, "CrossStrapBack", { .14, 2.2, .04 }, { -.05, 0, .53 }, "UpperTorso", finish, nil, { 0, 0, -45 })
		add(out, "CrossStrapPad", { .5, .08, .22 }, { .62, .8, 0 }, "UpperTorso", finish)
	elseif place == "back" and (id == "tote" or id == "duffel") then
		add(out, "SlingStrapFront", { .12, 2.2, .04 }, { .05, 0, -.53 }, "UpperTorso", finish, nil, { 0, 0, 45 })
		add(out, "SlingStrapBack", { .12, 2.2, .04 }, { .05, 0, .53 }, "UpperTorso", finish, nil, { 0, 0, 45 })
		add(out, "SlingStrapTop", { .5, .06, .2 }, { -.62, .8, 0 }, "UpperTorso", finish)
	elseif place == "shoulder" and id == "tote" then
		add(out, "ToteOnShoulder", { .44, .06, .3 }, { -.72, .82, .34 }, "UpperTorso", finish) -- (6.7: the tote hangs further back)
	end
	return out
end
function Geometry.spec(id: string): any
	local cart = id == "cart"
	local origins = if cart then { Frame = { 0, 0, 0 }, LeftWheel = { -.9, .59, .2 }, RightWheel = { .9, .59, .2 } }
		elseif Geometry.bags[id] then { BagPivot = { -1.5, 1.95, 0 } }
		else { UpperTorso = { 0, 3.4, 0 }, LeftUpperArm = { -1.5, 3.45, 0 }, RightUpperArm = { 1.5, 3.45, 0 }, LeftFoot = { -.52, .37, 0 }, RightFoot = { .52, .37, 0 } }
	return {
		id = id, pieces = Geometry.pieces(id), origins = origins, camera = if cart or id == "shoes" or id == "jacket" or id == "kevlar" or id == "heavy" or Geometry.bags[id] then "front" else "back", newRoots = if cart then 3 else 0,
		attachments = if cart then {
			{ name = "HandleGrip", attach = "Frame", at = { 0, 3.57, .26 } },
			{ name = "LeftGrip", attach = "Frame", at = { -.42, 3.57, .26 } },
			{ name = "RightGrip", attach = "Frame", at = { .42, 3.57, .26 } },
			{ name = "Deck", attach = "Frame", at = { 0, .34, -.52 } },
			{ name = "LeftAxle", attach = "Frame", at = { -.9, .59, .2 } },
			{ name = "RightAxle", attach = "Frame", at = { .9, .59, .2 } },
		} else {},
	}
end
return Geometry
