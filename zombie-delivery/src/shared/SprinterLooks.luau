--!strict
-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md): the ZDC Sprinter's parts look, as plain numbers (Pure Luau: the tests run it
-- outside Roblox, tests/sprinter_test.luau). A Mercedes-Sprinter-like high-roof panel van in the company's livery that
-- you walk into: server/Vehicles.luau (STYLES.sprinter, SprinterBuild) makes the parts. Its measures are
-- Config.Sprinter's; the owner's Blender model (server/SprinterMesh.luau) may dress it later: the hull and the walk-in
-- bay's colliders stay these.
--
-- The van's frame: from the ground under its middle (Vehicles' chassis middle, the wheelbase's middle), -z its front,
-- +x its right (the kerb side: the sliding door), +y up. Vehicles' styles count from the chassis' top
-- (SprinterLooks.Top over the ground, the bay's floor): it takes Top off every y.
--
--   SprinterLooks.hull()      the boxes that always collide (Vehicles' hull, hidden): the cab, the nose, the bulkhead
--                             (the cab's back wall) and the walk-in bay's walls and roof; its floor is the chassis' top.
--                             kind: "glass" the cab (a passenger seat in it gets a cab door), "body" the rest
--   SprinterLooks.Switched    the colliders a door switches (Vehicles' SprinterBuild.wire): the closed back doors' and
--                             sliding door's blocks (solid while shut: nobody falls out of a moving van) and the two
--                             fold-out steps (solid and shown while their door is open)
--   SprinterLooks.body()      the skin (on the body that sways): the cab with its windscreen, quarter windows, roof cap,
--                             dashboard, steering wheel and seats; the nose, grille, lamps and bumpers; the high-roof
--                             box with wheel arches; the ZDC livery (the red stripe all round, the ZDC logo and the
--                             company's name on both sides, the plates); the bay inside: the plywood floor,
--                             light grey panelled walls and ceiling, tie-down rails, the ceiling lamps and the bulkhead
--                             with its small window into the cab
--   SprinterLooks.door(side)  a cab door's skin (welded to its hinged panel): the door, its window, handle, stripe and
--                             the mirror
--   SprinterLooks.leaves()    the two back doors (Vehicles' back leaves): size, centre, hinge (the body's back corner:
--                             they swing out Config.Sprinter.Doors.Swing degrees and lie flat against the sides), angle
--                             and their skin
--   SprinterLooks.slider()    the sliding door's skin (its first piece is the door: the others weld to it) and how far
--                             it rolls back (open: { x, z } added to where it stands shut)
--   SprinterLooks.Finish      the finishes' colours and materials (paint: the car's own colour)
--   SprinterLooks.Seat / Passenger / Head / CargoDoor / Light / SidePrompt   points in the van's frame: the driver's
--                             seat, the one passenger seat, the headlights' beam (y, z), the back opening's middle (the
--                             Load and back prompts), the bay's ceiling light, the sliding door's prompt
--   SprinterLooks.DoorSpan    the cab doors' reach before and behind the seats' middle (hinged at the front edge)
--   SprinterLooks.Top / Length / Width / Axle / Track   the chassis' top over the ground (the floor), the hull's length
--                             (the chassis: a hair shorter than the body, for the steepest road's 15° at both ends),
--                             the width, the axles (±z) and the wheels (±x)
--   SprinterLooks.Bay         the bay inside: x0, x1, y0, y1, z0, z1 (the floor, the ceiling, the bulkhead, the back)

local Config = require(script.Parent.Config)

local SprinterLooks = {}

export type Piece = {
	name: string,
	size: { number }, -- along its own X, Y, Z
	at: { number }, -- its middle in the van's frame
	finish: string, -- SprinterLooks.Finish's key
	turn: { number }?, -- degrees about X, Y, Z (CFrame.Angles), after the move
	shape: string?, -- "Wedge" (its slope from its front bottom up to its back top) | "Cylinder" (along its own X)
	text: string?, -- a label on its front face (-Z)
	ink: string?, -- the label's finish
	font: string?, -- the label's Enum.Font name
	clear: boolean?, -- the part itself unseen (only its label shows)
}
export type Box = { name: string, kind: string, size: { number }, at: { number } }
export type Switched = { name: string, size: { number }, at: { number }, door: string, solid: string, finish: string? }
export type Leaf = { size: { number }, center: { number }, hinge: { number }, angle: number, pieces: { Piece } }
export type Finish = { color: { number }?, material: string, transparency: number?, reflectance: number?, lit: { number }? }

local S = Config.Sprinter

local HW = S.Width / 2 -- 4.0: the body's side
local FRONT, BACK = -S.Length / 2, S.Length / 2 -- -11, 11
local FLOOR = S.Bay.Floor -- 2.4: the chassis' top
local CEIL = FLOOR + S.Bay.Height -- 10.0
local ROOF = S.Height -- 10.4
local BW = S.Bay.Width / 2 -- 3.3: the bay's walls inside
local CAB_BACK = FRONT + S.Cab -- -4.0
local BAY0 = CAB_BACK + S.Bay.Gap -- -3.0
local BAY1 = BAY0 + S.Bay.Length -- 11.0 (the back)
local AXLE = S.Wheelbase / 2 -- 6.5
local ARCH = S.Wheel + 0.25 -- the wheel arches' radius
local ARCH_TOP = S.Wheel + ARCH -- 2.65
local WALL_X = (HW + BW) / 2 -- 3.65: the walls' colliders' middle
local WALL = HW - BW -- 0.7
local SKIN = 0.14 -- the outer panels
local SX = HW - SKIN / 2 -- 3.93
local OUT = HW + 0.02 -- the livery on the panels
local SF = S.Slider.Front -- -2.85: the sliding door's opening
local SB = SF + S.Slider.Width -- 2.15
local STOP = FLOOR + S.Slider.Height -- 9.3
local LEAF_Z = BAY1 - 0.1 -- 10.9: the closed back doors' middle (0.2 thick)
local DOOR0, DOOR1 = -8.55, -4.1 -- the cab doors along the van (hinged at their front edge: the Blender model's pivot)
local WAIST = 5.3 -- the cab doors' window line
local DOOR_TOP = 8.0
local WS0 = { -9.5, 5.0 } -- the windscreen's foot (z, y) and its top (the cab doors' front edge under it)
local WS1 = { DOOR0, 8.0 }
local CAP1 = -5.2 -- the high roof's sloped front ends here (z) at the roof
local STRIPE_Y, STRIPE_H = 3.6, 0.45 -- the red livery stripe
local SEAT_Z, SEAT_X, SEAT_Y = -5.75, 1.7, FLOOR + 1.3 -- (the seat part's middle: its top 3.9, the Blender model's seats)
local SIDE = ARCH_TOP + 0.05 -- the panels over the arches start here (y), the rockers end

assert(math.abs(BAY1 - BACK) < 1e-6, "Config.Sprinter: the cab, the gap and the bay make the length")

SprinterLooks.Top = FLOOR
SprinterLooks.Width = S.Width
SprinterLooks.Length = 21.8 -- (the chassis z -10.9 … 10.9: 15.3° over the 1.2 clearance at both axles; the body to ±11)
SprinterLooks.Axle = AXLE
SprinterLooks.Track = S.Track
SprinterLooks.Seat = { -SEAT_X, SEAT_Y, SEAT_Z }
SprinterLooks.Passenger = { SEAT_X, SEAT_Y, SEAT_Z }
SprinterLooks.Head = { 4.05, -10.9 } -- the headlights' height and z (their beam)
SprinterLooks.CargoDoor = { 0, FLOOR + 1.6, BACK + 0.6 } -- the back opening's middle, at a body's chest, 0.6 out (as every car's)
SprinterLooks.DoorSpan = { SEAT_Z - DOOR0, DOOR1 - SEAT_Z } -- the cab doors before and behind the seats' middle (Vehicles' doorSpan)
SprinterLooks.Light = { 0, CEIL - 0.4, (BAY0 + BAY1) / 2 }
SprinterLooks.SidePrompt = { HW + 0.6, FLOOR + 2.2, (SF + SB) / 2 } -- the sliding door's prompt: outside its middle
SprinterLooks.Bay = { x0 = -BW, x1 = BW, y0 = FLOOR, y1 = CEIL, z0 = BAY0, z1 = BAY1 }
SprinterLooks.Lamps = "BayLamp" -- the ceiling lamps' name (they glow while the light is on)
SprinterLooks.StepFolded = "StepFolded" -- the folded rear step's name (hidden while the step is out)

SprinterLooks.Finish = {
	paint = { material = "SmoothPlastic" }, -- the car's colour (Config.Cars color, a paint job)
	stripe = { color = { 179, 38, 30 }, material = "SmoothPlastic" }, -- the ZDC red (the ZDC Van's stripe and logo)
	trim = { color = { 32, 35, 38 }, material = "SmoothPlastic" }, -- black plastic: bumpers, arches, handles, mirrors
	glass = { color = { 40, 58, 68 }, material = "Glass", transparency = 0.35 },
	tint = { color = { 30, 38, 44 }, material = "Glass", reflectance = 0.12 }, -- dark tinted glass you cannot see through
	chrome = { color = { 196, 198, 204 }, material = "Metal", reflectance = 0.1 },
	lamp = { color = { 226, 222, 204 }, material = "Glass", lit = { 255, 246, 214 } },
	amber = { color = { 206, 132, 48 }, material = "Glass", lit = { 255, 166, 52 } },
	tail = { color = { 120, 24, 22 }, material = "Glass", lit = { 255, 36, 30 } },
	plate = { color = { 236, 236, 228 }, material = "SmoothPlastic" },
	lining = { color = { 206, 209, 211 }, material = "SmoothPlastic" }, -- the bay's light grey panels
	seam = { color = { 150, 154, 158 }, material = "SmoothPlastic" },
	floor = { color = { 156, 122, 84 }, material = "WoodPlanks" }, -- plywood
	rail = { color = { 176, 180, 186 }, material = "Metal" },
	light = { color = { 236, 236, 228 }, material = "SmoothPlastic", lit = { 255, 244, 222 } }, -- the bay's lamps (Neon while lit)
	seat = { color = { 58, 60, 64 }, material = "Fabric" },
	step = { color = { 120, 124, 128 }, material = "DiamondPlate" },
	dark = { color = { 22, 24, 26 }, material = "SmoothPlastic" },
} :: { [string]: Finish }

local function add(out: { Piece }, name: string, size: { number }, at: { number }, finish: string, turn: { number }?, shape: string?)
	table.insert(out, { name = name, size = size, at = at, finish = finish, turn = turn, shape = shape })
end

-- A label facing out of the side `side` (-1 left, 1 right; 0 the back: +z, nil the front: -z), on a clear plate (the
-- letters on the paint) or, `plate`, on a white one (a number plate).
local function label(out: { Piece }, name: string, size: { number }, at: { number }, side: number?, text: string, ink: string, font: string, plate: boolean?)
	local turn = if side == nil then nil elseif side == 0 then { 0, 180, 0 } else { 0, -side * 90, 0 }
	table.insert(out, { name = name, size = size, at = at, finish = "plate", turn = turn, text = text, ink = ink, font = font, clear = not plate })
end

-- A box from its edges.
local function span(x0: number, x1: number, y0: number, y1: number, z0: number, z1: number): ({ number }, { number })
	return { x1 - x0, y1 - y0, z1 - z0 }, { (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2 }
end

local function edges(out: { Piece }, name: string, finish: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number)
	local size, at = span(x0, x1, y0, y1, z0, z1)
	add(out, name, size, at, finish)
end

function SprinterLooks.hull(): { Box }
	local list: { Box } = {}
	local function hull(name: string, kind: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number)
		local size, at = span(x0, x1, y0, y1, z0, z1)
		table.insert(list, { name = name, kind = kind, size = size, at = at })
	end
	hull("Nose", "body", -HW, HW, 1.3, WS0[2], FRONT, WS0[1]) -- (1.3 over the ground: 16° to the front axle)
	hull("Cab", "glass", -HW, HW, FLOOR, DOOR_TOP, WS0[1], CAB_BACK)
	hull("CabRoof", "body", -HW, HW, DOOR_TOP, ROOF, CAP1, CAB_BACK)
	hull("Bulkhead", "body", -HW, HW, FLOOR, ROOF, CAB_BACK, BAY0)
	hull("WallLeft", "body", -HW, -BW, FLOOR, CEIL, BAY0, BAY1)
	hull("WallRight", "body", BW, HW, FLOOR, CEIL, BAY0, SF) -- (round the sliding door's opening)
	hull("WallRight", "body", BW, HW, STOP, CEIL, SF, SB)
	hull("WallRight", "body", BW, HW, FLOOR, CEIL, SB, BAY1)
	hull("Roof", "body", -HW, HW, CEIL, ROOF, BAY0, BAY1)
	hull("RearBumper", "body", -HW, HW, 1.4, FLOOR, BAY1 - 0.6, BAY1) -- (its top the floor's: the doorway's sill)
	return list
end

-- door: which door switches it ("back" | "slide"); solid: while that door is "open" or "closed"; finish: shown (as
-- that) while solid, else never seen.
SprinterLooks.Switched = (function(): { Switched }
	local list: { Switched } = {}
	local function switched(name: string, door: string, solid: string, finish: string?, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number)
		local size, at = span(x0, x1, y0, y1, z0, z1)
		table.insert(list, { name = name, door = door, solid = solid, finish = finish, size = size, at = at })
	end
	switched("BackBlock", "back", "closed", nil, -BW, BW, FLOOR, CEIL, BAY1 - 0.2, BAY1)
	switched("SlideBlock", "slide", "closed", nil, BW, HW, FLOOR, STOP, SF, SB)
	local step = S.Step
	switched("RearStep", "back", "open", "step", -step.Width / 2, step.Width / 2, step.Top - 0.2, step.Top, BAY1, BAY1 + step.Depth)
	local side = S.SideStep
	switched("SideStep", "slide", "open", "step", HW, HW + side.Depth, side.Top - 0.2, side.Top, SF + 0.3, SB - 0.3)
	return list
end)()

-- The cab: the nose, the bonnet, the windscreen, the roof cap and what you see through the glass.
local function cab(out: { Piece })
	edges(out, "FrontBumper", "trim", -HW - 0.05, HW + 0.05, 1.05, 2.05, FRONT, FRONT + 0.7)
	label(out, "FrontPlate", { 1.9, 0.45, 0.05 }, { 0, 1.55, FRONT - 0.03 }, nil, "DLV 02", "trim", "GothamBold", true)
	edges(out, "Nose", "paint", -HW + 0.1, HW - 0.1, 2.05, 4.6, FRONT + 0.2, FRONT + 0.7)
	edges(out, "Grille", "trim", -1.8, 1.8, 2.55, 3.95, FRONT + 0.13, FRONT + 0.21)
	edges(out, "GrilleBar", "chrome", -1.7, 1.7, 3.19, 3.31, FRONT + 0.08, FRONT + 0.14)
	add(out, "Badge", { 0.08, 0.7, 0.7 }, { 0, 3.25, FRONT + 0.05 }, "stripe", { 0, 90, 0 }, "Cylinder")
	for _, side in { -1, 1 } do
		add(out, "Headlamp", { 1.5, 0.75, 0.1 }, { side * 2.75, 4.05, FRONT + 0.17 }, "lamp")
		add(out, "Indicator", { 0.45, 0.75, 0.1 }, { side * 3.72, 4.05, FRONT + 0.17 }, "amber")
		-- the front fender up to the door, its strip under the door before the arch, the quarter window under the A-pillar
		add(out, "Fender", { SKIN, 4.8 - 1.25, DOOR0 - FRONT - 0.7 }, { side * SX, (1.25 + 4.8) / 2, (FRONT + 0.7 + DOOR0) / 2 }, "paint")
		add(out, "FenderLow", { SKIN, ARCH_TOP - 1.25, -AXLE - ARCH - DOOR0 }, { side * SX, (1.25 + ARCH_TOP) / 2, (DOOR0 - AXLE - ARCH) / 2 }, "paint") -- (under the door, before the arch)
		add(out, "QuarterGlass", { 0.06, WS1[2] - WS0[2], WS1[1] - WS0[1] }, { side * (HW - 0.03), (WS0[2] + WS1[2]) / 2, (WS0[1] + WS1[1]) / 2 }, "glass", nil, "Wedge")
		add(out, "APillar", { 0.4, math.sqrt((WS1[1] - WS0[1]) ^ 2 + (WS1[2] - WS0[2]) ^ 2), 0.3 }, { side * (HW - 0.2), (WS0[2] + WS1[2]) / 2, (WS0[1] + WS1[1]) / 2 }, "paint", { math.deg(math.atan2(WS1[1] - WS0[1], WS1[2] - WS0[2])), 0, 0 })
		-- behind the door: the B-pillar (on the right up to the sliding door), the sill behind the front arch, the
		-- panel over the door up to the roof
		local back = if side > 0 then SF else BAY0
		add(out, "BPillar", { SKIN, 10.25 - 1.25, back - DOOR1 }, { side * SX, (1.25 + 10.25) / 2, (DOOR1 + back) / 2 }, "paint")
		add(out, "CabSill", { SKIN, SIDE - 1.25, DOOR1 - (-AXLE + ARCH) }, { side * SX, (1.25 + SIDE) / 2, (DOOR1 - AXLE + ARCH) / 2 }, "paint")
		add(out, "CabUpper", { SKIN, 10.25 - DOOR_TOP, DOOR1 - CAP1 }, { side * SX, (DOOR_TOP + 10.25) / 2, (CAP1 + DOOR1) / 2 }, "paint")
		add(out, "Stripe", { 0.04, STRIPE_H, DOOR0 - FRONT - 0.7 }, { side * OUT, STRIPE_Y, (FRONT + 0.7 + DOOR0) / 2 }, "stripe")
	end
	-- the bonnet (rising to the windscreen), the windscreen raked back, the high roof's sloped front
	add(out, "Bonnet", { 2 * HW - 0.2, 0.3, WS0[1] - FRONT - 0.6 }, { 0, (4.6 + WS0[2]) / 2 - 0.15, (FRONT + 0.6 + WS0[1]) / 2 }, "paint", { -math.deg(math.atan2(WS0[2] - 4.6, WS0[1] - FRONT - 0.6)), 0, 0 })
	add(out, "Windscreen", { 2 * HW - 0.8, math.sqrt((WS1[1] - WS0[1]) ^ 2 + (WS1[2] - WS0[2]) ^ 2), 0.08 }, { 0, (WS0[2] + WS1[2]) / 2, (WS0[1] + WS1[1]) / 2 }, "glass", { math.deg(math.atan2(WS1[1] - WS0[1], WS1[2] - WS0[2])), 0, 0 })
	add(out, "RoofCap", { 2 * HW - 0.2, ROOF - DOOR_TOP, CAP1 - WS1[1] }, { 0, (DOOR_TOP + ROOF) / 2, (WS1[1] + CAP1) / 2 }, "paint", nil, "Wedge")
	add(out, "Roof", { 2 * HW - 0.2, ROOF - CEIL, BACK - CAP1 }, { 0, (CEIL + ROOF) / 2, (CAP1 + BACK) / 2 }, "paint")
	-- through the glass: the dashboard, the steering wheel, the two seats
	edges(out, "Dashboard", "dark", -HW + 0.4, HW - 0.4, 4.55, 5.45, -9.2, -8.1)
	add(out, "SteeringWheel", { 0.15, 1.3, 1.3 }, { -SEAT_X, 5.95, -7.05 }, "dark", { -30, 90, 0 }, "Cylinder")
	for _, side in { -1, 1 } do
		add(out, "SeatCushion", { 1.7, 0.4, 1.5 }, { side * SEAT_X, SEAT_Y, SEAT_Z }, "seat")
		add(out, "SeatBack", { 1.7, 2.1, 0.35 }, { side * SEAT_X, SEAT_Y + 1.3, SEAT_Z + 0.85 }, "seat", { -8, 0, 0 })
	end
end

-- The high-roof box outside: the sides round the arches and the sliding door, the arches' black lips, the livery.
local function box(out: { Piece })
	for _, side in { -1, 1 } do
		if side < 0 then
			edges(out, "CargoSide", "paint", -HW, -HW + SKIN, SIDE, 10.25, BAY0, BAY1)
		else
			edges(out, "CargoSide", "paint", HW - SKIN, HW, STOP, 10.25, SF, SB) -- (over the sliding door)
			edges(out, "CargoSide", "paint", HW - SKIN, HW, SIDE, 10.25, SB, BAY1)
			edges(out, "Rocker", "paint", HW - SKIN, HW, 1.25, FLOOR, SF, SB) -- (under its opening)
		end
		-- the rockers before and behind the rear arch
		local x0, x1 = if side < 0 then -HW else HW - SKIN, if side < 0 then -HW + SKIN else HW
		edges(out, "Rocker", "paint", x0, x1, 1.25, SIDE, if side < 0 then BAY0 else SB, AXLE - ARCH)
		edges(out, "Rocker", "paint", x0, x1, 1.25, SIDE, AXLE + ARCH, BAY1)
		-- the arches: three black lips round each wheel
		for _, z in { -AXLE, AXLE } do
			for n = 0, 2 do
				local angle = math.pi * (n + 0.5) / 3
				add(out, "ArchLip", { 0.22, 0.14, ARCH * 1.08 }, { side * (HW + 0.03), S.Wheel + math.sin(angle) * ARCH, z + math.cos(angle) * ARCH }, "trim", { -math.deg(angle) - 90, 0, 0 })
			end
		end
		-- the stripe (on the doors and the sliding door their own) and the logo with the company's name
		if side < 0 then
			edges(out, "Stripe", "stripe", -OUT - 0.02, -OUT + 0.02, STRIPE_Y - STRIPE_H / 2, STRIPE_Y + STRIPE_H / 2, DOOR1, BAY1)
		else
			edges(out, "Stripe", "stripe", OUT - 0.02, OUT + 0.02, STRIPE_Y - STRIPE_H / 2, STRIPE_Y + STRIPE_H / 2, DOOR1, SF)
			edges(out, "Stripe", "stripe", OUT - 0.02, OUT + 0.02, STRIPE_Y - STRIPE_H / 2, STRIPE_Y + STRIPE_H / 2, SB, BAY1)
		end
		local logoZ = if side < 0 then 4.0 else 6.2
		label(out, "Logo", { 6.0, 2.4, 0.02 }, { side * (HW + 0.03), 7.6, logoZ }, side, "DELIVEROS", "stripe", "GothamBlack")
		label(out, "CompanyName", { 6.6, 1.1, 0.02 }, { side * (HW + 0.03), 5.6, logoZ }, side, "MOVING & STORAGE\nMOVE · FIND · GROW", "trim", "GothamBold")
	end
	-- the sliding door's track over the side behind it
	edges(out, "SlideTrack", "trim", HW, HW + 0.08, STOP + 0.15, STOP + 0.29, SB, SB + S.Slider.Back)
	-- the back: the corner pillars with the tall tail lamps, the bumper with its plate, the folded step,
	-- the brake light on the roof's back edge
	for _, side in { -1, 1 } do
		local x = side * WALL_X
		add(out, "RearPillar", { WALL, 10.25 - FLOOR, 0.2 }, { x, (FLOOR + 10.25) / 2, LEAF_Z }, "paint")
		add(out, "TailLamp", { 0.5, 1.4, 0.08 }, { x, 5.0, BACK + 0.02 }, "tail")
		add(out, "RearIndicator", { 0.5, 0.5, 0.08 }, { x, 6.0, BACK + 0.02 }, "amber")
		add(out, "Stripe", { WALL, STRIPE_H, 0.04 }, { x, STRIPE_Y, BACK + 0.02 }, "stripe")
	end
	edges(out, "RearBumper", "trim", -HW, HW, 1.4, FLOOR - 0.02, BAY1 - 0.6, BAY1)
	label(out, "RearPlate", { 1.9, 0.45, 0.05 }, { 0, 1.85, BACK + 0.03 }, 0, "DLV 02", "trim", "GothamBold", true)
	edges(out, SprinterLooks.StepFolded, "step", -S.Step.Width / 2, S.Step.Width / 2, 1.17, 1.37, BAY1 - 0.55, BAY1 - 0.05)
	edges(out, "BrakeLight", "tail", -0.7, 0.7, CEIL + 0.12, CEIL + 0.28, BACK, BACK + 0.05)
end

-- The bay inside: the plywood floor, the panelled lining, the tie-down rails, the lamps, the bulkhead and its
-- window into the cab.
local function bay(out: { Piece })
	local inner = BW - 0.025
	edges(out, "BayFloor", "floor", -BW, BW, FLOOR, FLOOR + 0.05, BAY0, LEAF_Z - 0.1)
	edges(out, "Threshold", "chrome", -BW, BW, FLOOR, FLOOR + 0.06, LEAF_Z - 0.1, BAY1)
	edges(out, "Lining", "lining", -BW, -inner, FLOOR, CEIL, BAY0, BAY1)
	edges(out, "Lining", "lining", inner, BW, FLOOR, CEIL, BAY0, SF)
	edges(out, "Lining", "lining", inner, BW, STOP, CEIL, SF, SB)
	edges(out, "Lining", "lining", inner, BW, FLOOR, CEIL, SB, BAY1)
	edges(out, "Ceiling", "lining", -BW, BW, CEIL - 0.05, CEIL, BAY0, BAY1)
	-- the panels' joints (the body's ribs), the tie-down rails at two heights
	for _, z in { 1.5, 6.0 } do
		edges(out, "WallRib", "seam", -inner, -inner + 0.08, FLOOR + 0.05, CEIL - 0.05, z - 0.09, z + 0.09)
	end
	for _, z in { 4.5, 8.0 } do
		edges(out, "WallRib", "seam", inner - 0.08, inner, FLOOR + 0.05, CEIL - 0.05, z - 0.09, z + 0.09)
	end
	for _, y in { 4.4, 7.4 } do
		edges(out, "TieRail", "rail", -inner, -inner + 0.1, y - 0.09, y + 0.09, BAY0 + 0.2, LEAF_Z - 0.3)
		edges(out, "TieRail", "rail", inner - 0.1, inner, y - 0.09, y + 0.09, SB + 0.2, LEAF_Z - 0.3)
	end
	for _, z in { 0.6, 7.2 } do
		edges(out, SprinterLooks.Lamps, "light", -0.9, 0.9, CEIL - 0.15, CEIL - 0.05, z - 0.3, z + 0.3)
	end
	-- the bulkhead (the cab's back wall, light grey both ways) round its window
	local wx, wy0, wy1 = 1.3, 6.6, 7.8
	local x = HW - SKIN
	edges(out, "Bulkhead", "lining", -x, x, FLOOR, wy0, CAB_BACK, BAY0)
	edges(out, "Bulkhead", "lining", -x, x, wy1, CEIL, CAB_BACK, BAY0)
	edges(out, "Bulkhead", "lining", -x, -wx, wy0, wy1, CAB_BACK, BAY0)
	edges(out, "Bulkhead", "lining", wx, x, wy0, wy1, CAB_BACK, BAY0)
	edges(out, "BulkheadWindow", "glass", -wx, wx, wy0, wy1, (CAB_BACK + BAY0) / 2 - 0.03, (CAB_BACK + BAY0) / 2 + 0.03)
end

function SprinterLooks.body(): { Piece }
	local out: { Piece } = {}
	cab(out)
	box(out)
	bay(out)
	return out
end

-- A cab door's skin (side -1 the driver's on the left, 1 the passenger's), shut: welded to its hinged panel.
function SprinterLooks.door(side: number): { Piece }
	local out: { Piece } = {}
	local x0, x1 = if side < 0 then -HW else HW - SKIN, if side < 0 then -HW + SKIN else HW
	edges(out, "DoorSkin", "paint", x0, x1, ARCH_TOP + 0.05, WAIST, DOOR0, DOOR1)
	edges(out, "DoorWindow", "glass", side * (HW - 0.05) - 0.03, side * (HW - 0.05) + 0.03, WAIST, DOOR_TOP - 0.25, DOOR0, DOOR1 - 0.15)
	edges(out, "DoorFrame", "paint", x0, x1, DOOR_TOP - 0.25, DOOR_TOP, DOOR0, DOOR1)
	edges(out, "DoorFrame", "paint", x0, x1, WAIST, DOOR_TOP - 0.25, DOOR1 - 0.15, DOOR1)
	add(out, "DoorHandle", { 0.1, 0.2, 0.7 }, { side * (HW + 0.05), WAIST - 0.35, DOOR1 - 0.6 }, "trim")
	add(out, "DoorStripe", { 0.04, STRIPE_H, DOOR1 - DOOR0 }, { side * OUT, STRIPE_Y, (DOOR0 + DOOR1) / 2 }, "stripe")
	add(out, "MirrorArm", { 0.6, 0.12, 0.15 }, { side * (HW + 0.3), WAIST + 0.35, DOOR0 + 0.3 }, "trim")
	add(out, "Mirror", { 0.3, 1.5, 0.75 }, { side * (HW + S.Mirror - 0.15), WAIST + 0.7, DOOR0 + 0.35 }, "trim")
	return out
end

-- The back doors, shut: two leaves over the opening (its full width and height), hinged at the body's back corners
-- (one is the leaf's middle and the corner Width / 2 apart: the leaf turns round the corner and lies flat on the side).
function SprinterLooks.leaves(): { Leaf }
	local list: { Leaf } = {}
	local width = BW - 0.025
	local y0, y1 = FLOOR + 0.05, CEIL
	for _, side in { -1, 1 } do
		local cx = side * (BW - width / 2)
		local cy = (y0 + y1) / 2
		local pieces: { Piece } = {}
		add(pieces, "RearWindow", { width - 0.9, 1.9, 0.04 }, { cx, 8.65, BACK + 0.02 }, "tint")
		add(pieces, "LeafStripe", { width, STRIPE_H, 0.04 }, { cx, STRIPE_Y, BACK + 0.02 }, "stripe")
		add(pieces, "LeafLining", { width - 0.2, y1 - y0 - 0.3, 0.04 }, { cx, cy, BACK - 0.22 }, "lining")
		if side > 0 then
			add(pieces, "LeafHandle", { 0.2, 0.9, 0.06 }, { side * 0.35, 5.5, BACK + 0.03 }, "trim")
			label(pieces, "LeafName", { width - 0.4, 0.9, 0.02 }, { cx, 6.6, BACK + 0.03 }, 0, "MOVE · FIND · GROW", "trim", "GothamBold")
		else
			label(pieces, "LeafLogo", { width - 0.4, 1.2, 0.02 }, { cx, 6.6, BACK + 0.03 }, 0, "DELIVEROS", "stripe", "GothamBlack")
		end
		table.insert(list, {
			size = { width, y1 - y0, 0.2 },
			center = { cx, cy, LEAF_Z },
			hinge = { side * HW, cy, BACK },
			angle = side * S.Doors.Swing,
			pieces = pieces,
		})
	end
	return list
end

-- The sliding door, shut (its opening's outside: a hair proud of the side, in its track): the door first (the others
-- weld to it), its stripe, handle and lining. open: { x, z } it moves (out of the side, then back along it).
function SprinterLooks.slider(): ({ Piece }, { number })
	local out: { Piece } = {}
	edges(out, "SideDoor", "paint", HW, HW + SKIN, FLOOR, STOP, SF, SB) -- (SprinterMesh's door group "SideDoor": its mover)
	edges(out, "SlideStripe", "stripe", HW + SKIN, HW + SKIN + 0.04, STRIPE_Y - STRIPE_H / 2, STRIPE_Y + STRIPE_H / 2, SF, SB)
	add(out, "SlideHandle", { 0.1, 0.2, 0.7 }, { HW + SKIN + 0.07, WAIST - 0.35, SF + 0.6 }, "trim")
	edges(out, "SlideLining", "lining", HW - 0.02, HW, FLOOR + 0.1, STOP - 0.1, SF + 0.1, SB - 0.1)
	return out, { S.Slider.Out, S.Slider.Back }
end

return SprinterLooks
