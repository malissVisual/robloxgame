--!strict
-- Pure forecourt skins and carry props. Separate Nozzle targets and named labels/points; no fuel gameplay.
local Geometry = {}
type V = { number }
type Piece = { name: string, size: V, at: V, attach: string, finish: string, shape: string?, turn: V?, shadow: boolean?, text: string?, textSlot: string?, night: boolean? }
Geometry.ids = { "pump", "island", "pricesign", "jerrycan" }
local function add(p: { Piece }, name: string, size: V, at: V, attach: string, finish: string, shape: string?, turn: V?, text: string?, slot: string?)
	table.insert(p, { name = name, size = size, at = at, attach = attach, finish = finish, shape = shape, turn = turn, text = text, textSlot = slot, shadow = name == "PumpBody" or name == "Canopy" or name == "CanBody" })
end
local function hose(p: { Piece }, n: number, a: V, b: V)
	local x, y, z = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	add(p, "ParkedHose" .. n, { math.sqrt(x * x + y * y + z * z), .075, .075 }, { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2 }, "Frame", "sole", "Cylinder", { 0, -math.deg(math.atan2(z, x)), math.deg(math.atan2(y, math.sqrt(x * x + z * z))) })
end
local function pump(): { Piece }
	local p: { Piece } = {}
	add(p, "Foot", { 1.85, .24, 1.1 }, { 0, .12, 0 }, "Frame", "charcoal")
	add(p, "PumpBody", { 1.6, 3.6, .85 }, { 0, 2, 0 }, "Frame", "white")
	add(p, "RedLowerPanel", { 1.48, 1.5, .06 }, { 0, 1.13, -.48 }, "Frame", "red")
	add(p, "DisplaySurround", { 1.46, 1.26, .09 }, { 0, 2.84, -.48 }, "Frame", "charcoal")
	add(p, "LitresDisplay", { 1.2, .44, .04 }, { 0, 3.1, -.55 }, "Frame", "glass", nil, nil, "0.00 L", "Litres")
	add(p, "TotalDisplay", { 1.2, .35, .04 }, { 0, 2.65, -.55 }, "Frame", "glass", nil, nil, "$0.00", "Total")
	add(p, "PricePlate", { .93, .3, .05 }, { -.19, 2.06, -.51 }, "Frame", "charcoal", nil, nil, "$ — / L", "PricePerLitre")
	add(p, "PayPad", { .33, .52, .11 }, { .52, 1.97, -.54 }, "Frame", "charcoal")
	add(p, "CardSlot", { .21, .035, .025 }, { .52, 1.85, -.61 }, "Frame", "steel")
	add(p, "Dock", { .21, .5, .22 }, { .88, 2.25, 0 }, "Frame", "charcoal")
	add(p, "TopCap", { 1.72, .2, .92 }, { 0, 3.91, 0 }, "Frame", "charcoal")
	add(p, "NumberPlate", { .65, .32, .06 }, { 0, 3.68, -.48 }, "Frame", "red", nil, nil, "01", "PumpNumber")
	local bends: { V } = { { .78, 3.2, .17 }, { 1.37, 2.81, .17 }, { 1.5, 1.35, .17 }, { 1.38, .77, .17 }, { 1.12, 1.3, .17 }, { 1.04, 2.05, .1 } }
	for n = 1, 5 do hose(p, n, bends[n], bends[n + 1]) end
	add(p, "NozzleBody", { .18, .24, .33 }, { 0, .16, -.05 }, "Nozzle", "charcoal")
	add(p, "NozzleGrip", { .13, .39, .16 }, { 0, -.13, 0 }, "Nozzle", "sole")
	add(p, "NozzleSpout", { .46, .065, .065 }, { 0, .23, -.39 }, "Nozzle", "steel", "Cylinder", { 0, 90, 0 })
	return p
end
function Geometry.pieces(id: string): { Piece }
	if id == "pump" then return pump() end
	local p: { Piece } = {}
	if id == "island" then
		add(p, "KerbedIsland", { 3.4, .28, 13.8 }, { 0, .14, 0 }, "Frame", "concrete")
		add(p, "IslandTop", { 3.12, .06, 13.5 }, { 0, .31, 0 }, "Frame", "floor")
		for n, z in { -4, 4 } do
			for _, original in pump() do
				local d = table.clone(original)
				d.name = "Pump" .. n .. "_" .. d.name
				if d.attach == "Frame" then d.at = { d.at[1], d.at[2] + .34, d.at[3] + z }
				else d.attach = "Nozzle" .. n end
				if d.textSlot then d.textSlot = "Pump" .. n .. d.textSlot end
				if original.name == "NumberPlate" then d.text = "0" .. n end
				table.insert(p, d)
			end
		end
		for _, x in { -10, 10 } do for _, z in { -8, 8 } do
			add(p, "Post" .. x .. z, { .25, 12, .25 }, { x, 6, z }, "Frame", "steel")
			add(p, "PostFoot" .. x .. z, { .7, .16, .7 }, { x, .08, z }, "Frame", "charcoal")
		end end
		add(p, "Canopy", { 22, .35, 18 }, { 0, 12.17, 0 }, "Frame", "charcoal")
		add(p, "CanopyFrontRule", { 22, .14, .04 }, { 0, 12.22, -9.2 }, "Frame", "red")
		add(p, "CanopyRearRule", { 22, .14, .04 }, { 0, 12.22, 9.2 }, "Frame", "red")
		for n, z in { -4, 4 } do
			add(p, "CanopyLamp" .. n, { 2, .12, 3 }, { 0, 11.92, z }, "Frame", "white")
			p[#p].night = true
		end
	elseif id == "pricesign" then
		add(p, "Pole", { .5, 8.7, .5 }, { 0, 4.35, .35 }, "Frame", "steel")
		add(p, "Foot", { 1.2, .2, 1.2 }, { 0, .1, .35 }, "Frame", "charcoal")
		add(p, "Board", { 5.8, 4.4, .3 }, { 0, 8.8, 0 }, "Frame", "charcoal")
		add(p, "Header", { 5.5, .9, .06 }, { 0, 10.3, -.19 }, "Frame", "red", nil, nil, "FUEL / 24H")
		add(p, "PriceRow", { 5.4, 1.15, .06 }, { 0, 8.9, -.19 }, "Frame", "charcoal", nil, nil, "$ — / L", "PricePerLitre")
		add(p, "ServiceRow", { 5.4, .54, .06 }, { 0, 7.5, -.19 }, "Frame", "charcoal", nil, nil, "PAY AT PUMP")
		add(p, "PriceRule", { 5.5, .045, .04 }, { 0, 8.08, -.2 }, "Frame", "steel")
	elseif id == "jerrycan" then
		add(p, "CanBody", { 1.06, 1.4, .58 }, { 0, .82, 0 }, "Frame", "red")
		add(p, "Shoulder", { 1.03, .22, .58 }, { 0, 1.59, 0 }, "Frame", "red", "Wedge", { 0, 180, 0 })
		for _, x in { -.24, .24 } do add(p, "HandlePost" .. x, { .08, .42, .1 }, { x, 1.71, .06 }, "Frame", "red") end
		add(p, "Handle", { .56, .08, .1 }, { 0, 1.96, .06 }, "Frame", "red")
		add(p, "Cap", { .08, .2, .2 }, { .37, 1.69, -.22 }, "Frame", "charcoal", "Cylinder", { 0, 0, 90 })
		add(p, "PressedCross", { .76, .06, .035 }, { 0, .82, -.31 }, "Frame", "red", nil, { 0, 0, 35 })
	else error("Unknown fuel model: " .. id) end
	return p
end
function Geometry.spec(id: string): any
	local origins: any = { Frame = { 0, 0, 0 } }
	local points: { any } = {}
	local roots = 1
	local function point(name: string, attach: string, at: V, turn: V?) table.insert(points, { name = name, attach = attach, at = at, turn = turn }) end
	if id == "pump" then
		origins.Nozzle = { 1.04, 2.3, 0 }; roots = 2
		point("NozzleDock", "Frame", { 1.04, 2.3, 0 }); point("HoseAnchor", "Frame", { .78, 3.2, .17 })
		point("NozzleGrip", "Nozzle", { 0, -.13, 0 }); point("FuelOutlet", "Nozzle", { 0, .23, -.62 })
	elseif id == "island" then
		roots = 3
		for n, z in { -4, 4 } do
			origins["Nozzle" .. n] = { 1.04, 2.64, z }
			point("Pump" .. n .. "Dock", "Frame", { 1.04, 2.64, z }); point("Pump" .. n .. "HoseAnchor", "Frame", { .78, 3.54, z + .17 })
			point("Pump" .. n .. "Grip", "Nozzle" .. n, { 0, -.13, 0 }); point("Pump" .. n .. "FuelOutlet", "Nozzle" .. n, { 0, .23, -.62 })
			point("Bay" .. n .. "Left", "Frame", { -5.2, 0, z }); point("Bay" .. n .. "Right", "Frame", { 5.2, 0, z })
		end
	elseif id == "jerrycan" then point("CarryGrip", "Frame", { 0, 1.96, .06 }); point("PourOutlet", "Frame", { .37, 1.73, -.22 }, { 90, 0, 0 }) end
	return { id = id, pieces = Geometry.pieces(id), origins = origins, attachments = points, newRoots = roots }
end
return Geometry
