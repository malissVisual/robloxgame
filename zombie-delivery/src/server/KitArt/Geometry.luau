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
local Geometry = {}
type V = { number }
type Piece = { name: string, size: V, at: V, attach: string, finish: string, turn: V?, shape: string?, shadow: boolean?, text: string? }
Geometry.ids = { "backpack", "backpack_loaded", "bigpack", "shoes", "jacket", "cart", "bag", "kevlar", "heavy", "tote", "thermal", "padded", "duffel" }
Geometry.bags = { bag = true, tote = true, thermal = true, padded = true, duffel = true } :: { [string]: boolean } -- 6.4: hung on BagPivot
Geometry.translucent = { BagBody = .3, BagBottom = .15 } :: { [string]: number }
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
		add(out, "BagKnot", { .16, .1, .42 }, { 0, -.02, 0 }, "BagPivot", "white")
		add(out, "BagHandleF", { .06, .46, .07 }, { 0, -.22, -.17 }, "BagPivot", "white", nil, { 20, 0, 0 })
		add(out, "BagHandleB", { .06, .46, .07 }, { 0, -.22, .17 }, "BagPivot", "white", nil, { -20, 0, 0 })
		add(out, "BagBody", { .5, 1.1, 1 }, { 0, -1, 0 }, "BagPivot", "white")
		add(out, "BagBottom", { .52, .08, 1.02 }, { 0, -1.56, 0 }, "BagPivot", "white")
		for _, x in { -.26, .26 } do
			add(out, if x < 0 then "BagPrintL" else "BagPrintR", { .02, .3, .46 }, { x, -.92, 0 }, "BagPivot", "red")
		end
	elseif id == "tote" then
		-- 38 × 37 × 12 cm of canvas, its two long handles (one on each side) gathered in the hand
		add(out, "ToteBody", { .34, 1.05, 1.1 }, { 0, -1.025, 0 }, "BagPivot", "canvas")
		add(out, "ToteHem", { .36, .06, 1.12 }, { 0, -.53, 0 }, "BagPivot", "parcel")
		add(out, "ToteBottom", { .36, .06, 1.12 }, { 0, -1.53, 0 }, "BagPivot", "parcel")
		for _, x in { -.13, .13 } do
			for _, z in { -.205, .205 } do
				add(out, `ToteStrap{if x < 0 then "O" else "I"}{if z < 0 then "F" else "B"}`, { .05, .54, .09 }, { x, -.28, z }, "BagPivot", "parcel", nil, { if z < 0 then 35 else -35, 0, 0 })
			end
			add(out, if x < 0 then "TotePrintO" else "TotePrintI", { .02, .34, .46 }, { x * 1.33, -.98, 0 }, "BagPivot", "red")
		end
		add(out, "ToteGrip", { .2, .1, .16 }, { 0, -.04, 0 }, "BagPivot", "parcel")
	elseif id == "thermal" then
		-- the insulated ZDC food bag, 40 × 33 × 30 cm: red nylon, a black lid and base, a black ZDC patch on each side
		add(out, "ThermBody", { .85, .95, 1.15 }, { 0, -.795, 0 }, "BagPivot", "red")
		add(out, "ThermLid", { .89, .1, 1.19 }, { 0, -.32, 0 }, "BagPivot", "sole")
		add(out, "ThermBase", { .89, .1, 1.19 }, { 0, -1.25, 0 }, "BagPivot", "sole")
		add(out, "ThermZip", { .87, .03, 1.17 }, { 0, -.4, 0 }, "BagPivot", "steel")
		for _, x in { -1, 1 } do
			local side = if x < 0 then "O" else "I"
			add(out, "ThermPatch" .. side, { .5, .3, .03 }, { x * .44, -.74, 0 }, "BagPivot", "sole", nil, { 0, if x < 0 then 90 else -90, 0 }, "ZDC")
			add(out, "ThermReflector" .. side, { .02, .05, 1 }, { x * .435, -1.1, 0 }, "BagPivot", "reflector")
			add(out, "ThermHandle" .. side, { .05, .42, .14 }, { x * .15, -.17, 0 }, "BagPivot", "sole", nil, { 0, 0, if x < 0 then -45 else 45 })
		end
		add(out, "ThermGrip", { .12, .1, .2 }, { 0, -.04, 0 }, "BagPivot", "sole")
	elseif id == "padded" then
		-- a 38 × 28 × 12 cm messenger bag of grey nylon, foam-padded, its dark flap on the outer side, held by the strap
		add(out, "MessBody", { .36, .8, 1.1 }, { 0, -1, 0 }, "BagPivot", "nylon")
		add(out, "MessFlap", { .05, .62, 1.12 }, { -.205, -.86, 0 }, "BagPivot", "cloth")
		add(out, "MessFlapTop", { .4, .05, 1.12 }, { -.02, -.585, 0 }, "BagPivot", "cloth")
		add(out, "MessReflector", { .02, .05, .9 }, { -.235, -.7, 0 }, "BagPivot", "reflector")
		add(out, "MessPadSeam", { .02, .04, 1 }, { .185, -1, 0 }, "BagPivot", "worn")
		for _, z in { -.3, .3 } do
			add(out, if z < 0 then "MessBuckleF" else "MessBuckleB", { .04, .14, .1 }, { -.24, -1.12, z }, "BagPivot", "steel")
			add(out, if z < 0 then "MessStrapF" else "MessStrapB", { .06, .75, .13 }, { 0, -.32, z * .83 }, "BagPivot", "sole", nil, { if z < 0 then 42 else -42, 0, 0 })
		end
		add(out, "MessStrapPad", { .14, .12, .3 }, { 0, -.05, 0 }, "BagPivot", "sole")
	elseif id == "duffel" then
		-- a 60 cm dark-green duffel (30 cm across) lying along your way on its two carry handles, a shoulder strap
		-- clipped along its outer side
		add(out, "DuffBody", { 1.75, .85, .85 }, { 0, -.745, 0 }, "BagPivot", "olive", "Cylinder", { 0, 90, 0 })
		for _, z in { -1, 1 } do
			local tip = if z < 0 then "F" else "B"
			add(out, "DuffEnd" .. tip, { .06, .87, .87 }, { 0, -.745, z * .875 }, "BagPivot", "sole", "Cylinder", { 0, 90, 0 })
			add(out, "DuffBand" .. tip, { .08, .87, .87 }, { 0, -.745, z * .4 }, "BagPivot", "sole", "Cylinder", { 0, 90, 0 })
			add(out, "DuffHandle" .. tip, { .12, .46, .05 }, { 0, -.185, z * .225 }, "BagPivot", "sole", nil, { if z < 0 then 50 else -50, 0, 0 })
			add(out, "DuffClip" .. tip, { .06, .1, .06 }, { -.42, -.45, z * .78 }, "BagPivot", "steel")
		end
		add(out, "DuffZip", { .04, .03, 1.5 }, { 0, -.32, 0 }, "BagPivot", "steel")
		add(out, "DuffStrap", { .04, .06, 1.5 }, { -.44, -.55, 0 }, "BagPivot", "sole")
		add(out, "DuffPocket", { .05, .36, .6 }, { -.42, -.82, 0 }, "BagPivot", "olive")
		add(out, "DuffLabel", { .44, .16, .02 }, { -.455, -.82, 0 }, "BagPivot", "sole", nil, { 0, 90, 0 }, "ZDC")
		add(out, "DuffGrip", { .16, .1, .18 }, { 0, -.04, 0 }, "BagPivot", "sole")
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
		add(out, "ToteOnShoulder", { .44, .06, .26 }, { -.7, .82, .22 }, "UpperTorso", finish)
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
