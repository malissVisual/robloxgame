--!strict
-- Pure R15 courier kit and personal sack-truck skins. Local offsets belong to the named caller-owned target.
local Geometry = {}
type V = { number }
type Piece = { name: string, size: V, at: V, attach: string, finish: string, turn: V?, shape: string?, shadow: boolean?, text: string? }
Geometry.ids = { "backpack", "backpack_loaded", "bigpack", "shoes", "jacket", "cart" }
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
	else error("Unknown kit id: " .. id) end
	return out
end
function Geometry.spec(id: string): any
	local cart = id == "cart"
	local origins = if cart then { Frame = { 0, 0, 0 }, LeftWheel = { -.9, .59, .2 }, RightWheel = { .9, .59, .2 } }
		else { UpperTorso = { 0, 3.4, 0 }, LeftUpperArm = { -1.5, 3.45, 0 }, RightUpperArm = { 1.5, 3.45, 0 }, LeftFoot = { -.52, .37, 0 }, RightFoot = { .52, .37, 0 } }
	return {
		id = id, pieces = Geometry.pieces(id), origins = origins, camera = if cart or id == "shoes" or id == "jacket" then "front" else "back", newRoots = if cart then 3 else 0,
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
