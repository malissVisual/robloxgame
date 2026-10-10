--!strict
-- Pure bike/gear skins. Frame, wheels and Crank are separate caller-owned assemblies; no controllers or seats.
-- 6.19 (the owner: "the bike doesn't fit, the legs"): every bike and its gear is built at Geometry.Scale of the 5.1
-- art (the frames were sized for a rider a third taller than Roblox's classic R15), the saddle a little lower
-- (SaddleDrop), the bars a little higher (BarRise), the cranks a little longer (CrankArm, so the pedalling shows) and
-- the pedals out under the blocky legs' hips, all in the 5.1 art's units before the scale. The classic courier's feet then reach the pedals round the whole crank
-- (client/BikeRider.luau's leg IK, shared/RiderPose.luau legIk). The colliders and the physics are not the art's.
local Geometry = {}
Geometry.Scale = .75
Geometry.SaddleDrop = .38
Geometry.BarRise = .3
Geometry.CrankArm = .45
type V = { number }
type Piece = { name: string, size: V, at: V, attach: string, finish: string, turn: V?, shape: string?, shadow: boolean?, text: string?, night: boolean? }
Geometry.ids = { "rustbike", "citybike", "cargobike", "cargobike_loaded", "ebike", "basket", "panniers", "trailer", "bell", "light" }
local function add(p: { Piece }, name: string, size: V, at: V, attach: string, finish: string, shape: string?, turn: V?, text: string?)
	table.insert(p, { name = name, size = size, at = at, attach = attach, finish = finish, shape = shape, turn = turn, text = text, shadow = name == "CargoFloor" or name == "Battery" })
end
local function bar(p: { Piece }, name: string, a: V, b: V, diameter: number, attach: string, finish: string)
	local x, y, z = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	local length = math.sqrt(x * x + y * y + z * z)
	add(p, name, { length, diameter, diameter }, { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2 }, attach, finish, "Cylinder", { 0, -math.deg(math.atan2(z, x)), math.deg(math.atan2(y, math.sqrt(x * x + z * z))) })
end
local function wheel(p: { Piece }, name: string, radius: number, count: number, finish: string, spokes: boolean)
	for n = 0, count - 1 do
		local a, b = n * math.pi * 2 / count, (n + 1) * math.pi * 2 / count
		bar(p, if n == 0 then name .. "Tyre" else name .. "Tread" .. n, { 0, math.cos(a) * radius, math.sin(a) * radius }, { 0, math.cos(b) * radius, math.sin(b) * radius }, if count == 12 then .22 else .2, name .. "Wheel", "sole")
	end
	if spokes then
		for n = 0, 3 do
			local a = n * math.pi / 4
			bar(p, name .. "Spoke" .. n, { 0, math.cos(a) * radius * .91, math.sin(a) * radius * .91 }, { 0, -math.cos(a) * radius * .91, -math.sin(a) * radius * .91 }, .035, name .. "Wheel", finish)
		end
	end
	add(p, name .. "Hub", { .3, .22, .22 }, { 0, 0, 0 }, name .. "Wheel", finish, "Cylinder")
end
local function bike(id: string): boolean return id == "rustbike" or id == "citybike" or id == "cargobike" or id == "ebike" or id == "cargobike_loaded" end
local function dims(id: string): (number, number, number, number)
	local cargo = id == "cargobike" or id == "cargobike_loaded"
	return if cargo then -2.65 else -2, if cargo then 1.7 else 2, if cargo then .25 else -1.25, if cargo then .85 else .55
end
function Geometry.pieces(id: string): { Piece }
	local p: { Piece } = {}
	if bike(id) then
		local front, rear, head, seat = dims(id)
		local cargo, rusty = id == "cargobike" or id == "cargobike_loaded", id == "rustbike"
		local paint = if rusty then "worn" else "red"
		wheel(p, "Front", 1.19, 12, "steel", true)
		wheel(p, "Rear", 1.19, 12, if rusty then "worn" else "steel", true)
		local drop, rise, arm = Geometry.SaddleDrop, Geometry.BarRise, Geometry.CrankArm
		local h, s, c = { 0, 2.83, head }, { 0, 2.95 - drop, seat }, { 0, 1.22, seat - .12 }
		if not cargo then bar(p, "TopTube", h, s, .11, "Frame", paint) end
		bar(p, "DownTube", h, c, .13, "Frame", paint)
		bar(p, "SeatTube", c, s, .12, "Frame", paint)
		for _, side in { -1, 1 } do
			bar(p, "ChainStay" .. side, { side * .13, c[2], c[3] }, { side * .13, 1.3, rear }, .075, "Frame", paint)
			bar(p, "SeatStay" .. side, { side * .13, s[2], s[3] }, { side * .13, 1.3, rear }, .075, "Frame", paint)
			bar(p, "Fork" .. side, { side * .15, if cargo then 2.6 else h[2], if cargo then front + .12 else h[3] }, { side * .15, 1.3, front }, .095, "Frame", "steel")
		end
		if cargo then bar(p, "LowCargoBeam", { 0, 1.22, seat - .12 }, { 0, 1.48, front + .12 }, .13, "Frame", paint) end
		bar(p, "Stem", h, { 0, 3.25 + rise, head - .18 }, .1, "Frame", "steel")
		add(p, "Handlebar", { 1.42, .09, .09 }, { 0, 3.25 + rise, head - .18 }, "Frame", "steel", "Cylinder")
		for _, side in { -1, 1 } do add(p, "Grip" .. side, { .34, .14, .14 }, { side * .61, 3.25 + rise, head - .18 }, "Frame", "sole", "Cylinder") end
		add(p, "Saddle", { .66, .15, .72 }, { 0, 3.08 - drop, seat }, "Frame", "sole")
		if not cargo then
			add(p, "RearRack", { .76, .065, 1 }, { 0, 2.77, rear - .2 }, "Frame", "steel")
			for _, side in { -1, 1 } do bar(p, "RackStay" .. side, { side * .16, 1.3, rear }, { side * .33, 2.74, rear + .15 }, .05, "Frame", "steel") end
		end
		add(p, "ChainRing", { .07, .62, .62 }, { .22, 0, 0 }, "Crank", "steel", "Cylinder")
		if not cargo and id ~= "ebike" then bar(p, "ChainUpper", { .25, 1.44, seat - .12 }, { .25, 1.42, rear }, .035, "Frame", "sole") end
		for _, side in { -1, 1 } do
			bar(p, "CrankArm" .. side, { side * .36, 0, 0 }, { side * .36, side * arm, 0 }, .075, "Crank", "steel")
			add(p, "Pedal" .. side, { .38, .1, .26 }, { side * .62, side * arm, 0 }, "Crank", "sole")
		end
		if cargo then
			add(p, "CargoFloor", { 1.5, .12, 1.55 }, { 0, 2.14, -.575 }, "Frame", "worn")
			for _, side in { -1, 1 } do add(p, "BoxSide" .. side, { .09, .58, 1.55 }, { side * .755, 2.48, -.575 }, "Frame", "charcoal") end
			add(p, "BoxFront", { 1.5, .58, .08 }, { 0, 2.48, -1.39 }, "Frame", "charcoal", nil, nil, "ZDC / CARGO")
			add(p, "BoxBack", { 1.5, .58, .08 }, { 0, 2.48, .24 }, "Frame", "charcoal")
			if id == "cargobike_loaded" then for n = 1, 6 do
				add(p, "SampleParcel" .. n, { .46, .56, .36 }, { if n % 2 == 1 then -.35 else .35, 2.49, -1.06 + math.floor((n - 1) / 2) * .48 }, "Frame", "parcel")
			end end
		elseif rusty then
			add(p, "RustSleeve", { .32, .16, .16 }, { 0, 2.91, .1 }, "Frame", "rust", "Cylinder")
			add(p, "PrimerRepair", { .26, .15, .15 }, { 0, 2.45, -.78 }, "Frame", "rust", "Cylinder", { 0, 0, 33 })
		else
			add(p, "LampHousing", { .3, .29, .22 }, { 0, 2.98, head - .23 }, "Frame", "charcoal")
			add(p, "LampLens", { .24, .23, .04 }, { 0, 2.98, head - .37 }, "Frame", "white")
			p[#p].night = true
			add(p, "RearReflector", { .25, .13, .045 }, { 0, 2.73, rear + .34 }, "Frame", "red")
		end
		if id == "ebike" then
			add(p, "Battery", { .3, .7, .26 }, { 0, 1.97, -.55 }, "Frame", "charcoal", nil, { 24, 0, 0 })
			add(p, "BatteryStripe", { .31, .07, .27 }, { 0, 1.91, -.55 }, "Frame", "red", nil, { 24, 0, 0 })
			add(p, "BarDisplay", { .29, .06, .22 }, { -.22, 3.32 + rise, head - .18 }, "Frame", "glass", nil, { 15, 0, 0 })
			add(p, "FrontDisc", { .04, .62, .62 }, { .18, 0, 0 }, "FrontWheel", "steel", "Cylinder")
			add(p, "RearDisc", { .04, .62, .62 }, { .18, 0, 0 }, "RearWheel", "steel", "Cylinder")
		end
	elseif id == "basket" then
		add(p, "BasketFloor", { 1.24, .065, .86 }, { 0, 0, 0 }, "Mount", "worn")
		for _, side in { -1, 1 } do
			add(p, "SideRail" .. side, { .055, .055, .86 }, { side * .61, .55, 0 }, "Mount", "steel")
			add(p, "EndRail" .. side, { 1.24, .055, .055 }, { 0, .55, side * .42 }, "Mount", "steel")
			for _, z in { -.42, .42 } do add(p, "Corner" .. side .. z, { .055, .55, .055 }, { side * .61, .275, z }, "Mount", "steel") end
		end
	elseif id == "panniers" then
		for _, side in { -1, 1 } do
			add(p, "Pannier" .. side, { .36, .88, .91 }, { side * .62, -.4, 0 }, "Mount", "cloth")
			add(p, "Lid" .. side, { .39, .1, .95 }, { side * .62, .1, 0 }, "Mount", "charcoal")
			add(p, "Stripe" .. side, { .04, .08, .8 }, { side * .83, -.18, 0 }, "Mount", "red")
			add(p, "RearReflector" .. side, { .23, .1, .035 }, { side * .62, -.57, .48 }, "Mount", "reflector")
			add(p, "MountClip" .. side, { .08, .16, .25 }, { side * .43, .13, 0 }, "Mount", "steel")
		end
	elseif id == "trailer" then
		wheel(p, "Left", .54, 8, "steel", false); wheel(p, "Right", .54, 8, "steel", false)
		add(p, "Deck", { 1.65, .12, 1.9 }, { 0, .55, 0 }, "Frame", "worn")
		bar(p, "HitchArm", { 0, .6, -.8 }, { 0, .75, -1.85 }, .085, "Frame", "steel")
		for _, side in { -1, 1 } do add(p, "SideStop" .. side, { .06, .32, 1.8 }, { side * .8, .75, 0 }, "Frame", "charcoal") end
	elseif id == "bell" then
		add(p, "Bell", { .13, .25, .25 }, { 0, .06, 0 }, "Mount", "steel", "Cylinder", { 0, 0, 90 })
		add(p, "ThumbLever", { .17, .035, .07 }, { .15, .04, 0 }, "Mount", "sole")
	elseif id == "light" then
		add(p, "LampCase", { .29, .27, .31 }, { 0, 0, 0 }, "Mount", "charcoal")
		add(p, "Lens", { .24, .21, .035 }, { 0, 0, -.18 }, "Mount", "white")
		p[#p].night = true
		add(p, "Clip", { .1, .12, .12 }, { 0, -.19, .04 }, "Mount", "sole")
	else error("Unknown bike art id: " .. id) end
	-- 6.19: the whole skin at Geometry.Scale (from the ground origin, or the gear's mount).
	local k = Geometry.Scale
	for _, piece in p do
		piece.size = { piece.size[1] * k, piece.size[2] * k, piece.size[3] * k }
		piece.at = { piece.at[1] * k, piece.at[2] * k, piece.at[3] * k }
	end
	return p
end
function Geometry.spec(id: string): any
	local points: { any } = {}
	local origins: any = { Mount = { 0, 1, 0 } }
	local roots = 1
	local function point(name: string, attach: string, at: V) table.insert(points, { name = name, attach = attach, at = at }) end
	if bike(id) then
		local front, rear, head, seat = dims(id)
		origins = { Frame = { 0, 0, 0 }, FrontWheel = { 0, 1.3, front }, RearWheel = { 0, 1.3, rear }, Crank = { 0, 1.22, seat - .12 } }; roots = 4
		local drop, rise, arm = Geometry.SaddleDrop, Geometry.BarRise, Geometry.CrankArm
		point("Saddle", "Frame", { 0, 3.16 - drop, seat }); point("LeftGrip", "Frame", { -.61, 3.25 + rise, head - .18 }); point("RightGrip", "Frame", { .61, 3.25 + rise, head - .18 })
		point("LeftPedal", "Crank", { -.62, -arm, 0 }); point("RightPedal", "Crank", { .62, arm, 0 })
		point("FrontAxle", "Frame", { 0, 1.3, front }); point("RearAxle", "Frame", { 0, 1.3, rear }); point("CrankAxis", "Frame", { 0, 1.22, seat - .12 })
		point("BasketMount", "Frame", { 0, 2.75, if id == "cargobike" or id == "cargobike_loaded" then -1.88 else head - .6 }); point("PannierMount", "Frame", { 0, 2.82, rear - .2 }); point("Hitch", "Frame", { 0, .75, rear + 1.35 })
		point("BellMount", "Frame", { -.35, 3.3 + rise, head - .18 }); point("LightMount", "Frame", { 0, 3.02, head - .23 })
		if id == "cargobike" or id == "cargobike_loaded" then
			for n = 1, 6 do point("Slot" .. n, "Frame", { if n % 2 == 1 then -.35 else .35, 2.21, -1.06 + math.floor((n - 1) / 2) * .48 }) end
		else point("Slot1", "Frame", { 0, 2.81, rear - .2 }) end
	elseif id == "basket" then point("Slot1", "Mount", { -.3, .06, 0 }); point("Slot2", "Mount", { .3, .06, 0 })
	elseif id == "panniers" then point("Slot1", "Mount", { -.62, .15, 0 }); point("Slot2", "Mount", { .62, .15, 0 })
	elseif id == "trailer" then
		origins = { Frame = { 0, 0, 0 }, LeftWheel = { -.94, .64, .25 }, RightWheel = { .94, .64, .25 } }; roots = 3
		point("Hitch", "Frame", { 0, .75, -1.85 }); point("LeftAxle", "Frame", { -.94, .64, .25 }); point("RightAxle", "Frame", { .94, .64, .25 })
		for n = 1, 4 do point("Slot" .. n, "Frame", { if n % 2 == 1 then -.4 else .4, .63, if n <= 2 then -.4 else .4 }) end
	end
	-- 6.19: the points and the roots at Geometry.Scale too
	local k = Geometry.Scale
	for _, at in points do
		at.at = { at.at[1] * k, at.at[2] * k, at.at[3] * k }
	end
	for name, o in origins do
		origins[name] = { o[1] * k, o[2] * k, o[3] * k }
	end
	return { id = id, pieces = Geometry.pieces(id), attachments = points, origins = origins, newRoots = roots,
		reservedParts = if bike(id) then 2 else 0, -- Claude's stable collider + doorless seat, in the 70-part total
	}
end
return Geometry
