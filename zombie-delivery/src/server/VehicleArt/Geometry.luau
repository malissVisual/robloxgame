--!strict
-- Real, reusable Roblox geometry for the owned fleet, stage equipment and upgrade kits. No engine calls.
local Geometry = {}
export type V = { number }
export type Piece = { name: string, size: V, at: V, finish: string, turn: V?, shape: string?, text: string? }
export type Profile = {
	id: string, stage: number, width: number, length: number, wheel: number, wheelWidth: number,
	wheelY: number, seatY: number, seatZ: number, headY: number, headZ: number, cabWidth: number, cabFront: number, cabBack: number, cabTop: number, windowTop: number,
	hoodTop: number, cargoFront: number, cargoBack: number, cargoTop: number, roof: number,
}
local function add(out: { Piece }, name: string, size: V, at: V, finish: string, turn: V?, shape: string?, text: string?)
	table.insert(out, { name = name, size = size, at = at, finish = finish, turn = turn, shape = shape, text = text })
end
local function ladder(out: { Piece }, x: number, z: number, top: number)
	for _, side in { -1, 1 } do
		add(out, "LadderRail", { top - .7, .12, .12 }, { x, (top + .7) / 2, z + side * .42 }, "steel", { 0, 0, 90 }, "Cylinder")
	end
	for y = 1, top - .3, .65 do add(out, "LadderRung", { .9, .13, .13 }, { x, y, z }, "steel", { 0, 90, 0 }, "Cylinder") end
end
local function rack(out: { Piece }, half: number, front: number, back: number, top: number)
	for _, side in { -1, 1 } do
		add(out, "RackRail", { .16, .18, back - front }, { side * half, top + .5, (front + back) / 2 }, "dark")
		for _, z in { front + .2, back - .2 } do
			add(out, "RackFoot", { .2, .45, .35 }, { side * half, top + .23, z }, "steel")
		end
	end
	for n = 0, 3 do add(out, "RackCrossbar", { half * 2, .13, .18 }, { 0, top + .5, front + (back - front) * n / 3 }, "steel") end
end
function Geometry.body(p: Profile): { Piece }
	local out: { Piece } = {}
	local half, front = p.width / 2, -p.length / 2
	local pickup, muscle = p.id == "pickup", p.id == "muscle"
	local truck = p.id == "boxtruck" or p.id == "freighttruck"
	local cabHalf = p.cabWidth / 2
	local glassBottom = p.hoodTop + .14
	local glassTop = p.windowTop
	local glassHeight = math.max(.9, glassTop - glassBottom)
	local glassY = (glassBottom + glassTop) / 2
	local cabLength = p.cabBack - p.cabFront
	-- A closed cab made of panels and glazing, rather than one transparent solid cube.
	add(out, "Windshield", { p.cabWidth - .48, glassHeight, .06 }, { 0, glassY, p.cabFront + .17 }, "glass", { 12, 0, 0 })
	for _, side in { -1, 1 } do
		add(out, "APillar", { .22, glassHeight + .2, .18 }, { side * (cabHalf - .1), glassY, p.cabFront + .17 }, "paint", { 12, 0, 0 })
		add(out, "RearCabPillar", { .23, glassHeight + .2, .2 }, { side * (cabHalf - .1), glassY, p.cabBack - .12 }, "paint")
		add(out, "WindowWaist", { .2, .12, cabLength }, { side * cabHalf, glassBottom - .08, (p.cabFront + p.cabBack) / 2 }, "dark")
		add(out, "RoofGutter", { .18, .14, cabLength }, { side * cabHalf, p.cabTop - .16, (p.cabFront + p.cabBack) / 2 }, "steel")
		add(out, "MirrorArm", { .65, .09, .12 }, { side * (cabHalf + .28), glassBottom + .45, p.cabFront + .7 }, "dark")
		add(out, "MirrorHousing", { .18, .72, .48 }, { side * (cabHalf + .64), glassBottom + .58, p.cabFront + .7 }, "dark")
		add(out, "MirrorGlass", { .035, .56, .32 }, { side * (cabHalf + .74), glassBottom + .58, p.cabFront + .74 }, "mirror")
	end
	local header = p.cabTop - p.windowTop
	if header > .2 then
		add(out, "CabHeader", { p.cabWidth - .2, header, .13 }, { 0, p.windowTop + header / 2, p.cabFront + .04 }, "paint")
		for _, side in { -1, 1 } do add(out, "UpperCabSide", { .13, header, cabLength }, { side * (cabHalf - .05), p.windowTop + header / 2, (p.cabFront + p.cabBack) / 2 }, "paint") end
	end
	add(out, "CabRoof", { p.cabWidth - .3, .35, cabLength }, { 0, p.cabTop - .175, (p.cabFront + p.cabBack) / 2 }, "paint")
	add(out, "RoofLeadingEdge", { p.cabWidth - .3, .25, .4 }, { 0, p.cabTop - .22, p.cabFront + .2 }, "paint", nil, "Wedge")
	add(out, "Dashboard", { p.cabWidth - .4, .26, .65 }, { 0, p.hoodTop - .24, p.cabFront + .55 }, "dark")
	for _, side in { -1, 1 } do
		add(out, "SeatCushion", { 1.6, .18, 1.35 }, { side * p.cabWidth * .21, p.seatY - .02, p.seatZ }, "dark")
		add(out, "SeatBack", { 1.5, 1.35, .18 }, { side * p.cabWidth * .21, p.seatY + .6, p.seatZ + .55 }, "dark")
	end
	add(out, "CabBack", { p.cabWidth - .2, p.cabTop, .12 }, { 0, p.cabTop / 2, p.cabBack - .02 }, "paint")
	local hoodLength = math.max(.7, p.cabFront - front)
	add(out, "Hood", { p.width - .3, .26, hoodLength }, { 0, p.hoodTop - .13, front + hoodLength / 2 }, "paint")
	add(out, "Nose", { p.width - .1, p.hoodTop, .2 }, { 0, p.hoodTop / 2, front + .08 }, "paint")
	add(out, "FrontValance", { p.width - .7, .55, .15 }, { 0, -.24, front + .05 }, "dark")
	add(out, "GrilleRecess", { p.width * .48, .68, .08 }, { 0, math.min(1.05, p.hoodTop * .54), front - .065 }, "dark")
	for n = 0, 3 do add(out, "GrilleSlat", { p.width * .43, .045, .05 }, { 0, math.min(1.05, p.hoodTop * .54) - .24 + n * .16, front - .115 }, "steel") end
	add(out, "DispatchBadge", { .38, .22, .06 }, { 0, math.min(1.05, p.hoodTop * .54), front - .16 }, "red")
	add(out, "BumperCore", { p.width + .08, .38, .44 }, { 0, .18, front - .16 }, if p.id == "van" and p.stage < 2 then "dark" else "steel")
	add(out, "LowerIntake", { p.width * .54, .23, .07 }, { 0, .16, front - .405 }, "dark")
	for _, side in { -1, 1 } do
		add(out, "HeadlampHousing", { 1.5, .88, .08 }, { side * (half - 1), p.headY, p.headZ + .06 }, "dark")
		add(out, "BumperCorner", { .68, .49, .62 }, { side * (half - .27), .18, front - .12 }, "dark")
		add(out, "Indicator", { .25, .36, .08 }, { side * (half - .25), p.headY, p.headZ + .015 }, "amber")
		add(out, "Wiper", { p.cabWidth * .32, .055, .06 }, { side * p.cabWidth * .21, glassBottom + .2, p.cabFront - .1 }, "dark", { 0, 0, side * 5 })
	end
	-- Side shell with genuine gaps around the wheels; original invisible hull carries collisions.
	local axle = p.length / 2 - p.wheel - .5
	local archTop = math.max(.6, p.wheelY + p.wheel + .08)
	for _, side in { -1, 1 } do
		for _, z in { -axle, axle } do
			for n = 0, 6 do
				local angle = math.pi * n / 6
				add(out, "ArchLip", { .22, .12, .65 }, { side * (half + .02), p.wheelY + math.sin(angle) * (p.wheel + .15), z + math.cos(angle) * (p.wheel + .15) }, if p.id == "rallyvan" or p.id == "armorvan" then "dark" else "paint", { -math.deg(angle) - 90, 0, 0 })
			end
		end
		local intervals = { { front, -axle - p.wheel - .13 }, { -axle + p.wheel + .13, axle - p.wheel - .13 }, { axle + p.wheel + .13, p.cargoBack } }
		for _, interval in intervals do
			local length = interval[2] - interval[1]
			if length > .1 then
				if interval[1] < p.cabBack and interval[2] > p.cabFront then
					add(out, "CabSill", { .13, .18, length }, { side * half, .09, (interval[1] + interval[2]) / 2 }, "paint")
					local start = math.max(interval[1], p.cabBack)
					if interval[2] - start > .1 then add(out, "CargoRocker", { .13, archTop, interval[2] - start }, { side * half, archTop / 2, (start + interval[2]) / 2 }, "paint") end
				else add(out, "RockerPanel", { .13, archTop, length }, { side * half, archTop / 2, (interval[1] + interval[2]) / 2 }, "paint") end
			end
		end
		-- The front fender is above the arch and below the bonnet.
		if p.hoodTop > archTop then add(out, "FrontFender", { .13, p.hoodTop - archTop, hoodLength }, { side * half, (p.hoodTop + archTop) / 2, front + hoodLength / 2 }, "paint") end
		local sideHeight = math.max(.25, p.cargoTop - archTop)
		add(out, "CargoSide", { .14, sideHeight, p.cargoBack - p.cargoFront }, { side * half, archTop + sideHeight / 2, (p.cargoFront + p.cargoBack) / 2 }, "paint")
		add(out, "SideRubStrip", { .06, .14, p.cargoBack - p.cargoFront - .25 }, { side * (half + .1), math.min(1.4, p.cargoTop * .4), (p.cargoFront + p.cargoBack) / 2 }, "dark")
		if not pickup and not muscle then
			add(out, "CargoStamp", { 3.5, .65, .025 }, { side * (half + .095), p.cargoTop * .66, p.cargoFront + (p.cargoBack - p.cargoFront) * .52 }, "dark", { 0, -side * 90, 0 }, nil, if p.id == "van" then "ZDC / 01" elseif p.id == "courier" then "EXPRESS / 02" elseif truck then "FREIGHT / ZDC" else "ZDC / DELIVERY")
			add(out, "DispatchStripe", { .045, .1, p.cargoBack - p.cargoFront - .5 }, { side * (half + .11), p.cargoTop * .66 - .49, (p.cargoFront + p.cargoBack) / 2 }, "red")
		end
		add(out, "RearCornerPost", { .2, p.cargoTop, .2 }, { side * (half - .06), p.cargoTop / 2, p.cargoBack - .02 }, "steel")
	end
	if pickup then
		add(out, "BedFloor", { p.width - .3, .12, p.cargoBack - p.cargoFront }, { 0, .12, (p.cargoFront + p.cargoBack) / 2 }, "dark")
	elseif muscle then
		add(out, "RearDeck", { p.width - .2, .12, p.cargoBack - p.cargoFront }, { 0, p.cargoTop, (p.cargoFront + p.cargoBack) / 2 }, "paint")
	else
		add(out, "CargoRoof", { p.width - .25, .22, p.cargoBack - p.cargoFront }, { 0, p.cargoTop - .11, (p.cargoFront + p.cargoBack) / 2 }, "paint")
		for _, side in { -1, 1 } do add(out, "RoofShoulder", { p.cargoBack - p.cargoFront, .32, .26 }, { side * (half - .08), p.cargoTop - .16, (p.cargoFront + p.cargoBack) / 2 }, "paint", { 0, side * 90, 0 }, "Wedge") end
		add(out, "CargoBulkhead", { p.width - .2, p.cargoTop, .12 }, { 0, p.cargoTop / 2, p.cargoFront + .05 }, "paint")
	end
	add(out, "RearStep", { p.width - .8, .23, .5 }, { 0, .15, p.cargoBack + .22 }, "dark")
	if muscle and p.stage >= 1 then
		add(out, "StageBlower", { 1.3, .6, 1.2 }, { 0, p.hoodTop + .3, front + hoodLength * .55 }, "steel")
		add(out, "BlowerIntake", { 1.45, .25, .8 }, { 0, p.hoodTop + .72, front + hoodLength * .55 }, "dark")
	end
	-- Small irregular paint loss: no giant rust rectangles on the roof or sides.
	if p.id == "van" and p.stage < 2 then
		for _, side in { -1, 1 } do
			for n = 1, 5 do
				local z = p.cargoFront + .6 + n * (p.cargoBack - p.cargoFront - 1.2) / 6
				add(out, "WearPatch", { .027, .22 + n % 3 * .11, .38 + n % 2 * .2 }, { side * (half + .088), archTop + .18 + n % 2 * .18, z }, if p.stage == 0 then "rust" else "primer", { n * 9, 0, 0 }, "Wedge")
			end
		end
	end
	if p.id == "van" and p.stage < 2 then
		for n = 0, 2 do add(out, "WindscreenCrack", { .025, .6 + n * .15, .025 }, { 1.3 + n * .19, glassBottom + .65 + n * .2, p.cabFront + .05 }, "dark", { 12, 0, 35 - n * 42 }) end
	end
	-- Stage equipment: modelled rack, pod, spare and deflector within the current mounting envelope.
	if p.id == "van" and p.stage >= 2 then
		ladder(out, half + .21, p.cargoFront + .6, p.cargoTop)
		for _, y in { 1.9, 2.9, 3.9 } do add(out, "RearShelf", { p.width - .9, .12, .3 }, { 0, y, p.cargoBack - .12 }, "wood") end
		if p.stage >= 3 then rack(out, half - .45, math.max(2.4, p.cargoFront + .7), p.cargoBack - .7, p.cargoTop) end
	end
	if p.id == "courier" and p.stage >= 1 then
		add(out, "ExpressPod", { 4.1, .7, 2.7 }, { 0, p.cargoTop + .35, p.cargoBack - 1.8 }, "paint")
		add(out, "PodNose", { 4.1, .7, .7 }, { 0, p.cargoTop + .35, p.cargoBack - 3.5 }, "paint", nil, "Wedge")
		for _, side in { -1, 1 } do for n = 0, 5 do add(out, "ExpressCheck", { .04, .32, .48 }, { side * (half + .12), 2.3, p.cargoFront + .7 + n * .48 }, if n % 2 == 0 then "dark" else "white") end end
	end
	if p.id == "highroof" and p.stage >= 1 then
		rack(out, half - .4, math.max(2.4, p.cargoFront + 1.3), p.cargoBack - .6, p.cargoTop)
		add(out, "RoofSpare", { .55, 2.1, 2.1 }, { 0, p.cargoTop + .9, p.cargoBack - 2.0 }, "tyre", { 0, 0, 90 }, "Cylinder")
		add(out, "SpareHub", { .6, .95, .95 }, { 0, p.cargoTop + .9, p.cargoBack - 2.0 }, "steel", { 0, 0, 90 }, "Cylinder")
	end
	if truck or p.id == "highroof" then
		local top = if p.id == "freighttruck" then 9.1 else math.min(p.cargoTop - .15, p.cabTop + 1.35)
		local rise = top - p.cabTop
		if rise > .1 then add(out, "WindDeflector", { p.cabWidth - .5, rise, cabLength * .55 }, { 0, p.cabTop + rise / 2, p.cabBack - cabLength * .28 }, "paint", nil, "Wedge") end
	end
	if p.id == "boxtruck" and p.stage >= 1 then
		add(out, "LiftgateDeck", { p.width - .45, .18, .7 }, { 0, -.14, p.cargoBack + .3 }, "steel")
		for _, side in { -1, 1 } do add(out, "LiftgateRam", { 1.2, .18, .18 }, { side * (half - .5), .3, p.cargoBack + .3 }, "dark", { 0, 0, 90 }, "Cylinder") end
	end
	if p.id == "armorvan" then
		for _, side in { -1, 1 } do
			for n = 0, 2 do
				local z = p.cargoFront + 1.2 + n * (p.cargoBack - p.cargoFront - 2.4) / 2
				add(out, "BallisticPanel", { .14, 1.25, 1.8 }, { side * (half + .1), 2.5, z }, "armor")
				for _, y in { 2.02, 2.98 } do add(out, "PanelFastener", { .04, .085, .085 }, { side * (half + .19), y, z - .68 }, "steel", nil, "Cylinder") end
			end
		end
		if p.stage >= 1 then
			for _, side in { -1, 1 } do add(out, "FortressLocker", { .22, .85, 2 }, { side * (half + .3), 3.6, p.cargoBack - 1.6 }, "dark") end
			add(out, "TurretShield", { 3.2, .85, .15 }, { 0, p.roof + .32, -.9 }, "armor")
			add(out, "RoofSpare", { .45, 2, 2 }, { 0, p.cargoTop + .3, p.cargoBack - 1.2 }, "tyre", { 0, 0, 90 }, "Cylinder")
		end
	end
	if p.id == "rallyvan" or (muscle and p.stage >= 1) then
		add(out, "RearWing", { p.width - .3, .12, .65 }, { 0, p.cargoTop + .55, p.cargoBack - .55 }, "dark", { -7, 0, 0 })
		for _, side in { -1, 1 } do add(out, "WingStanchion", { .14, .5, .22 }, { side * (half - .55), p.cargoTop + .29, p.cargoBack - .55 }, "steel") end
	end
	if (p.id == "rallyvan" and p.stage >= 1) or p.id == "courier" or (p.id == "van" and p.stage >= 3) then
		add(out, "RoofLampPod", { 3.5, .18, .45 }, { 0, p.cabTop + .13, p.cabFront + .45 }, "dark")
		for n = 0, 3 do add(out, "RoofLamp", { .13, .45, .45 }, { -.99 + n * .66, p.cabTop + .43, p.cabFront + .45 }, "lamp", { 0, 90, 0 }, "Cylinder") end
	end
	if pickup and p.stage >= 1 then
		for _, side in { -1, 1 } do add(out, "BedRollPost", { 2.1, .17, .17 }, { side * (half - .25), p.cargoTop + 1, p.cargoFront + .6 }, "steel", { 0, 0, 90 }, "Cylinder") end
		add(out, "BedRollBar", { p.width - .5, .17, .17 }, { 0, p.cargoTop + 2, p.cargoFront + .6 }, "steel", nil, "Cylinder")
	end
	return out
end
function Geometry.door(size: V, side: number, windowTop: number, panelTop: number, primer: boolean, inset: number): { Piece }
	local out: { Piece } = {}
	local height = math.max(.45, windowTop - panelTop)
	local y = size[2] / 2 + height / 2
	local turn = { 0, 0, side * math.deg(math.atan2(inset, height)) }
	local paneHeight = math.sqrt(height * height + inset * inset)
	add(out, "DoorGlass", { .055, paneHeight, size[3] - .15 }, { -side * inset / 2, y, 0 }, "glass", turn)
	for _, z in { -size[3] / 2, size[3] / 2 } do add(out, "DoorWindowFrame", { .14, paneHeight + .07, .11 }, { -side * inset / 2, y, z }, if primer then "primer" else "paint", turn) end
	add(out, "WindowTopSeal", { .13, .11, size[3] }, { -side * inset, y + height / 2, 0 }, "dark")
	add(out, "DoorInset", { .035, math.max(.15, size[2] - .35), size[3] - .26 }, { side * .075, 0, 0 }, if primer then "primer" else "paint")
	add(out, "DoorRedPinstripe", { .035, .07, size[3] - .35 }, { side * .104, -size[2] * .15, 0 }, "red")
	return out
end
function Geometry.rear(size: V): { Piece }
	local out: { Piece } = {}
	add(out, "RearDoorInset", { math.max(.2, size[1] - .2), math.max(.2, size[2] - .24), .04 }, { 0, 0, size[3] / 2 + .023 }, "paint")
	for _, x in { -size[1] / 2 + .2, size[1] / 2 - .2 } do
		add(out, "DoorLockRod", { size[2] * .68, .055, .055 }, { x, 0, size[3] / 2 + .08 }, "steel", { 0, 0, 90 }, "Cylinder")
		for _, y in { -size[2] * .25, size[2] * .25 } do add(out, "LockRodBracket", { .16, .13, .1 }, { x, y, size[3] / 2 + .1 }, "dark") end
	end
	add(out, "DoorReflector", { size[1] * .55, .09, .035 }, { 0, -size[2] * .34, size[3] / 2 + .09 }, "red")
	return out
end
function Geometry.wheel(width: number, radius: number, alloy: boolean): { Piece }
	local out: { Piece } = {}
	for _, side in { -1, 1 } do
		local x = side * (width / 2 + .025)
		add(out, "RimLip", { .055, radius * 1.16, radius * 1.16 }, { x, 0, 0 }, "steel", nil, "Cylinder")
		add(out, "RimWell", { .065, radius * 1.04, radius * 1.04 }, { x + side * .025, 0, 0 }, "dark", nil, "Cylinder")
		if alloy then
			for n = 0, 4 do
				local a = n * math.pi * 2 / 5
				add(out, "AlloySpoke", { .09, radius * .48, .1 }, { x + side * .07, math.cos(a) * radius * .26, math.sin(a) * radius * .26 }, "steel", { math.deg(a), 0, 0 })
			end
		else
			add(out, "SteelDisc", { .08, radius * .9, radius * .9 }, { x + side * .07, 0, 0 }, "steel", nil, "Cylinder")
			for n = 0, 5 do local a = n * math.pi / 3; add(out, "VentHole", { .012, radius * .15, radius * .15 }, { x + side * .115, math.cos(a) * radius * .31, math.sin(a) * radius * .31 }, "dark", nil, "Cylinder") end
		end
		add(out, "HubCap", { .1, radius * .34, radius * .34 }, { x + side * .14, 0, 0 }, "steel", nil, "Cylinder")
	end
	return out
end
function Geometry.upgrades(p: Profile, plow: number, armor: number, engine: number): { Piece }
	local out: { Piece } = {}
	local half, front = p.width / 2, -p.length / 2
	if plow > 0 then
		local z = front - .7
		for _, side in { -1, 1 } do add(out, "BullbarUpright", { 2.15, .16 + plow * .02, .16 + plow * .02 }, { side * (half - .5), .65, z }, "dark", { 0, 0, 90 }, "Cylinder") end
		for _, y in { .1, p.headY + .7 } do add(out, "BullbarCross", { p.width - .6, .16 + plow * .02, .16 + plow * .02 }, { 0, y, z }, "steel", nil, "Cylinder") end
		if plow >= 3 then
			add(out, "RamSkid", { p.width - .3, .85, .18 }, { 0, -.25, z - .12 }, "armor", { -15, 0, 0 })
			for _, side in { -1, 1 } do add(out, "RecoveryEye", { .2, .22, .18 }, { side * (half - .7), -.25, z - .27 }, "red") end
		end
		if plow >= 5 then for n = 0, 5 do add(out, "RamFastener", { .075, .075, .025 }, { (n - 2.5) * (p.width - 1) / 5, -.16, z - .245 }, "steel") end end
	end
	if armor > 0 and p.id ~= "armorvan" then
		local length = p.cargoBack - p.cargoFront - .8
		local height = .65 + armor * .15
		for _, side in { -1, 1 } do
			for n = 0, 2 do
				local z = p.cargoFront + .4 + length * (n + .5) / 3
				add(out, "ArmorSection", { .12, height, length / 3 - .1 }, { side * (half + .18), math.max(1.6, p.wheelY + p.wheel + .2), z }, "armor")
				for _, y in { -.35, .35 } do add(out, "ArmorBolt", { .025, .08, .08 }, { side * (half + .26), math.max(1.6, p.wheelY + p.wheel + .2) + y * height, z }, "steel", nil, "Cylinder") end
			end
		end
		if armor >= 3 then
			local y = (p.hoodTop + p.windowTop) / 2
			for _, x in { -p.cabWidth * .25, 0, p.cabWidth * .25 } do add(out, "WindshieldGuard", { .07, math.max(.6, p.windowTop - p.hoodTop), .07 }, { x, y, p.cabFront - .11 }, "dark", { 12, 0, 0 }) end
			add(out, "GuardBrace", { p.cabWidth - .3, .08, .08 }, { 0, y, p.cabFront - .13 }, "dark")
		end
	end
	if engine >= 3 then
		local hoodLength = math.max(.7, p.cabFront - front)
		local height = .3 + .07 * (engine - 3)
		add(out, "EngineIntake", { 1.8, height, math.min(1.5, hoodLength * .65) }, { 0, p.hoodTop + height / 2, front + hoodLength * .58 }, "dark", nil, "Wedge")
		add(out, "IntakeMouth", { 1.55, height * .6, .025 }, { 0, p.hoodTop + height / 2, front + hoodLength * .58 + math.min(1.5, hoodLength * .65) / 2 + .02 }, "steel")
		for _, side in { -1, 1 } do
			add(out, "ExhaustSleeve", { .7, .31, .31 }, { side * (half - .9), -.65, p.length / 2 + .18 }, "steel", { 0, 90, 0 }, "Cylinder")
			add(out, "ExhaustBore", { .015, .22, .22 }, { side * (half - .9), -.65, p.length / 2 + .55 }, "dark", { 0, 90, 0 }, "Cylinder")
		end
	end
	return out
end
return Geometry
