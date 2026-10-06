--!strict
-- 5.1.1: the E-Scooter's skin as pure data (Claude's, in Codex's BikeArt convention, built by server/ModelArt/Builder):
-- a narrow low deck with grip tape and red side stripes, the battery under it, a folded kickstand, a small rear rack
-- with a red tail lamp, a tall stem with a red clamp, a bar with grips and a night lamp. Frame, FrontWheel and
-- RearWheel are separate caller-owned assemblies (server/Vehicles.luau: the hidden BikeFrame on BikeLean, the wheels on
-- WheelMotors); no crank, no seat or controllers here. Forward -Z, up +Y, from the ground under the scooter; studs.
-- Points: Deck (the rider's feet), LeftGrip / RightGrip, the axles, BasketMount (the bar's basket), LightMount (the
-- beam), Slot1 (the rear rack's light piece). Budget 45 with the roots and the reserved seat + collider.
local Geometry = {}
type V = { number }
type Piece = { name: string, size: V, at: V, attach: string, finish: string, turn: V?, shape: string?, shadow: boolean?, text: string?, night: boolean? }
Geometry.ids = { "escooter" }

local RADIUS = .6 -- the wheels
local FRONT, REAR = -1.95, 1.45 -- the axles' z
local DECK_Y, DECK_Z = .5, -.2 -- the deck's middle (it runs from z -1.2 to .8, clear of both tyres)
local HEAD, BAR = { 0, 1.5, -1.62 }, { 0, 3.45, -1.5 } -- the stem's foot (over the front tyre) and top (the bar)

local function add(p: { Piece }, name: string, size: V, at: V, attach: string, finish: string, shape: string?, turn: V?)
	table.insert(p, { name = name, size = size, at = at, attach = attach, finish = finish, shape = shape, turn = turn, shadow = name == "Deck" or name == "Battery" })
end
local function bar(p: { Piece }, name: string, a: V, b: V, diameter: number, attach: string, finish: string)
	local x, y, z = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	local length = math.sqrt(x * x + y * y + z * z)
	add(p, name, { length, diameter, diameter }, { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2 }, attach, finish, "Cylinder", { 0, -math.deg(math.atan2(z, x)), math.deg(math.atan2(y, math.sqrt(x * x + z * z))) })
end
-- A small solid wheel: eight tread segments round a steel disc.
local function wheel(p: { Piece }, name: string)
	for n = 0, 7 do
		local a, b = n * math.pi / 4, (n + 1) * math.pi / 4
		bar(p, if n == 0 then name .. "Tyre" else name .. "Tread" .. n, { 0, math.cos(a) * RADIUS, math.sin(a) * RADIUS }, { 0, math.cos(b) * RADIUS, math.sin(b) * RADIUS }, .2, name .. "Wheel", "sole")
	end
	add(p, name .. "Rim", { .14, .82, .82 }, { 0, 0, 0 }, name .. "Wheel", "steel", "Cylinder")
end

function Geometry.pieces(id: string): { Piece }
	assert(id == "escooter", "Unknown scooter art id: " .. id)
	local p: { Piece } = {}
	wheel(p, "Front")
	wheel(p, "Rear")
	-- The deck: grip tape on top, red stripes down its sides, the battery under it, the kickstand folded along it.
	add(p, "Deck", { .62, .14, 2.0 }, { 0, DECK_Y, DECK_Z }, "Frame", "charcoal")
	add(p, "GripTape", { .54, .02, 1.8 }, { 0, DECK_Y + .08, DECK_Z }, "Frame", "sole")
	for _, side in { -1, 1 } do
		add(p, "DeckStripe" .. side, { .03, .06, 1.85 }, { side * .315, DECK_Y, DECK_Z }, "Frame", "red")
	end
	add(p, "Battery", { .48, .16, 1.5 }, { 0, .35, DECK_Z }, "Frame", "charcoal")
	bar(p, "Kickstand", { -.24, .33, .2 }, { -.3, .24, .72 }, .05, "Frame", "steel")
	-- The rear: two dropouts to the axle, the small rack over the wheel (the one light piece), the red tail lamp.
	for _, side in { -1, 1 } do
		bar(p, "Dropout" .. side, { side * .15, DECK_Y, .75 }, { side * .15, RADIUS, REAR }, .08, "Frame", "charcoal")
	end
	add(p, "RearRack", { .56, .06, .95 }, { 0, 1.36, REAR }, "Frame", "steel")
	for _, side in { -1, 1 } do
		bar(p, "RackStay" .. side, { side * .17, RADIUS, REAR }, { side * .21, 1.34, REAR + .35 }, .05, "Frame", "steel")
	end
	add(p, "TailLamp", { .22, .08, .04 }, { 0, 1.32, REAR + .5 }, "Frame", "red")
	-- The front: the neck up from the deck, the fork down to the axle, the stem with its red clamp, the bar.
	bar(p, "Neck", { 0, DECK_Y + .05, -1.15 }, HEAD, .14, "Frame", "charcoal")
	for _, side in { -1, 1 } do
		bar(p, "Fork" .. side, { side * .15, HEAD[2], HEAD[3] - .02 }, { side * .15, RADIUS, FRONT }, .08, "Frame", "steel")
	end
	add(p, "StemClamp", { .22, .16, .22 }, { 0, HEAD[2] + .2, HEAD[3] + .005 }, "Frame", "red")
	bar(p, "Stem", HEAD, BAR, .12, "Frame", "steel")
	add(p, "Handlebar", { 1.24, .09, .09 }, BAR, "Frame", "steel", "Cylinder")
	for _, side in { -1, 1 } do
		add(p, "Grip" .. side, { .3, .13, .13 }, { side * .52, BAR[2], BAR[3] }, "Frame", "sole", "Cylinder")
	end
	-- The night lamp on the stem, under the bar.
	add(p, "LampHousing", { .24, .22, .16 }, { 0, 3.0, -1.62 }, "Frame", "charcoal")
	add(p, "LampLens", { .2, .17, .03 }, { 0, 3.0, -1.715 }, "Frame", "white")
	p[#p].night = true
	return p
end

function Geometry.spec(id: string): any
	local points: { any } = {}
	local function point(name: string, attach: string, at: V)
		table.insert(points, { name = name, attach = attach, at = at })
	end
	point("Deck", "Frame", { 0, DECK_Y + .09, DECK_Z })
	point("LeftGrip", "Frame", { -.52, BAR[2], BAR[3] })
	point("RightGrip", "Frame", { .52, BAR[2], BAR[3] })
	point("FrontAxle", "Frame", { 0, RADIUS, FRONT })
	point("RearAxle", "Frame", { 0, RADIUS, REAR })
	point("BasketMount", "Frame", { 0, 2.2, -2.08 }) -- the basket hangs on the stem, over the front wheel
	point("LightMount", "Frame", { 0, 3.0, -1.62 })
	point("Slot1", "Frame", { 0, 1.39, REAR }) -- on the rear rack
	return {
		id = id,
		pieces = Geometry.pieces(id),
		attachments = points,
		origins = { Frame = { 0, 0, 0 }, FrontWheel = { 0, RADIUS, FRONT }, RearWheel = { 0, RADIUS, REAR } },
		newRoots = 3,
		reservedParts = 2, -- the doorless seat and the stable collider (server/Vehicles.luau), in the 45-part total
	}
end

return Geometry
