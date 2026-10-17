--!strict
-- 8.0 SANDBOX: the ZDC Sprinter (Config.Sprinter, Config.Cars sprinter, shared/SprinterLooks.luau: its parts look and
-- its walk-in bay, which server/Vehicles.luau builds; tools/vehicle-preview builds the real thing and checks its
-- ground, joints and welds). Here, from the numbers alone:
--   * the measures everyone shares (the brief's: 8.0 × 10.4 × 22.0, wheelbase 13.0, clearance 1.2; the bay inside
--     6.6 × 7.6 × 14.0 on a floor 2.4 up, from 1.0 behind the cab's 7 studs to the back), the floor the chassis' top
--   * the walk-in bay: no collider in it; its floor, walls, roof, bulkhead and the shut doors' blocks round it on every
--     side; an open back's and an open side door's openings free; the fold-out steps two rises a body walks up
--   * the back doors swing round the body's back corners and lie flat against the sides; the sliding door rolls
--     clear of its opening, outside the side
--   * the hull rides over the ground (only the wheels touch it) with 15° at both axles; the skin inside the body's
--     box and out of the bay's walking room; the livery (the red stripe, the ZDC logo on both sides and the back);
--     the seats in the cab; the part budget
--   * the car: sandbox-only (no dealer, career or advice lists it; a player's car only in the sandbox), heavier than
--     the ZDC Van, a big tank, one passenger
-- Run with tests/run_tests.py.
local Config = require("./Config")
local Economy = require("./Economy")
local Looks = require("./SprinterLooks")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local S = Config.Sprinter
local EPS = 1e-6

-- ── The measures ────────────────────────────────────────────────────────────
check("the body 8.0 wide, 10.4 tall, 22.0 long; wheelbase 13.0; clearance 1.2", S.Width == 8.0 and S.Height == 10.4 and S.Length == 22.0
	and S.Wheelbase == 13.0 and S.Clearance == 1.2)
check("the bay inside 6.6 × 7.6 × 14.0, its floor 2.4 up, 1.0 behind the cab's wall; the cab the front 7", S.Bay.Width == 6.6
	and S.Bay.Height == 7.6 and S.Bay.Length == 14.0 and S.Bay.Floor == 2.4 and S.Bay.Gap == 1.0 and S.Cab == 7.0)
check("the floor is the chassis' top (clearance + the 1.2 chassis): Vehicles' style frame", math.abs(S.Clearance + 1.2 - S.Bay.Floor) < EPS
	and Looks.Top == S.Bay.Floor)
local bay = Looks.Bay
check("the bay: x ±3.3, y 2.4 … 10.0, z -3 … 11 (the cab, the gap and the bay make the length)", math.abs(bay.x0 + 3.3) < EPS
	and math.abs(bay.x1 - 3.3) < EPS and math.abs(bay.y0 - 2.4) < EPS and math.abs(bay.y1 - 10.0) < EPS and math.abs(bay.z0 + 3) < EPS
	and math.abs(bay.z1 - 11) < EPS)
check("the wheels' top at the floor at most (no wheel in the bay), the axles ±6.5", 2 * S.Wheel <= S.Bay.Floor + EPS and Looks.Axle == 6.5
	and Looks.Track + 0.5 <= S.Width / 2 + EPS)

-- ── Boxes ───────────────────────────────────────────────────────────────────
type Ext = { number } -- x0, x1, y0, y1, z0, z1

-- A piece's axis-aligned box (turned: CFrame.Angles(x, y, z) = Rx · Ry · Rz).
local function extent(size: { number }, at: { number }, turn: { number }?): Ext
	local r = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
	if turn then
		local a, b, c = math.rad(turn[1]), math.rad(turn[2]), math.rad(turn[3])
		local rx = { { 1, 0, 0 }, { 0, math.cos(a), -math.sin(a) }, { 0, math.sin(a), math.cos(a) } }
		local ry = { { math.cos(b), 0, math.sin(b) }, { 0, 1, 0 }, { -math.sin(b), 0, math.cos(b) } }
		local rz = { { math.cos(c), -math.sin(c), 0 }, { math.sin(c), math.cos(c), 0 }, { 0, 0, 1 } }
		local function mul(m: { { number } }, n: { { number } }): { { number } }
			local o = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
			for i = 1, 3 do
				for j = 1, 3 do
					for k = 1, 3 do
						o[i][j] += m[i][k] * n[k][j]
					end
				end
			end
			return o
		end
		r = mul(mul(rx, ry), rz)
	end
	local out: Ext = {}
	for i = 1, 3 do
		local half = 0
		for j = 1, 3 do
			half += math.abs(r[i][j]) * size[j] / 2
		end
		out[2 * i - 1], out[2 * i] = at[i] - half, at[i] + half
	end
	return out
end

local function holds(e: Ext, x: number, y: number, z: number): boolean
	return x >= e[1] - EPS and x <= e[2] + EPS and y >= e[3] - EPS and y <= e[4] + EPS and z >= e[5] - EPS and z <= e[6] + EPS
end

local function meets(a: Ext, b: Ext): boolean -- (overlap with some depth)
	return a[1] < b[2] - 1e-3 and a[2] > b[1] + 1e-3 and a[3] < b[4] - 1e-3 and a[4] > b[3] + 1e-3 and a[5] < b[6] - 1e-3 and a[6] > b[5] + 1e-3
end

local hull: { Ext } = {}
for _, b in Looks.hull() do
	table.insert(hull, extent(b.size, b.at))
end
-- the chassis: its top the floor, Looks.Length long, as wide as the body less 0.4 (Vehicles' build)
local chassis: Ext = { -S.Width / 2 + 0.2, S.Width / 2 - 0.2, S.Clearance, S.Bay.Floor, -Looks.Length / 2, Looks.Length / 2 }
local switched: { [string]: { e: Ext, s: any } } = {}
for _, s in Looks.Switched do
	switched[s.name] = { e = extent(s.size, s.at), s = s }
end

-- the colliders with the doors shut / open
local function solidAt(x: number, y: number, z: number, backOpen: boolean, slideOpen: boolean): boolean
	if holds(chassis, x, y, z) then
		return true
	end
	for _, e in hull do
		if holds(e, x, y, z) then
			return true
		end
	end
	for _, item in switched do
		local open = if item.s.door == "back" then backOpen else slideOpen
		if (item.s.solid == "open") == open and holds(item.e, x, y, z) then
			return true
		end
	end
	return false
end

-- ── The walk-in bay ─────────────────────────────────────────────────────────
local inside: Ext = { bay.x0, bay.x1, bay.y0, bay.y1, bay.z0, bay.z1 - 0.2 } -- (the shut doors' inner face 0.2 in)
local clear = true
for _, e in hull do
	clear = clear and not meets(e, inside)
end
for _, item in switched do
	if item.s.solid == "closed" and item.s.name ~= "BackBlock" then
		clear = clear and not meets(item.e, inside)
	end
end
check("no collider in the bay (6.6 × 7.6 × 13.8 with the back shut)", clear)

-- every side of the bay closed while the doors are shut: a grid of points just outside each face
local function closed(face: string, backOpen: boolean, slideOpen: boolean): (boolean, string?)
	local d = 0.1
	for u = 0.05, 0.95, 0.075 do
		for v = 0.05, 0.95, 0.075 do
			local x = bay.x0 + (bay.x1 - bay.x0) * u
			local y = bay.y0 + (bay.y1 - bay.y0) * v
			local z = bay.z0 + (bay.z1 - bay.z0) * u
			local p: { number }
			if face == "floor" then
				p = { x, bay.y0 - d, bay.z0 + (bay.z1 - bay.z0) * v }
			elseif face == "roof" then
				p = { x, bay.y1 + d, bay.z0 + (bay.z1 - bay.z0) * v }
			elseif face == "left" then
				p = { bay.x0 - d, y, z }
			elseif face == "right" then
				p = { bay.x1 + d, y, z }
			elseif face == "front" then
				p = { x, y, bay.z0 - d }
			else
				p = { x, y, bay.z1 - d }
			end
			if not solidAt(p[1], p[2], p[3], backOpen, slideOpen) then
				return false, string.format("%.2f %.2f %.2f", p[1], p[2], p[3])
			end
		end
	end
	return true, nil
end
for _, face in { "floor", "roof", "left", "right", "front", "back" } do
	local ok, where = closed(face, false, false)
	check(`the shut bay's {face} is closed (a collider all over it)`, ok, where)
end
local backOk = closed("back", true, false)
check("the back open: its opening is free", not backOk)
local free = true
for x = bay.x0 + 0.1, bay.x1 - 0.1, 0.25 do
	for y = bay.y0 + 0.1, bay.y1 - 0.1, 0.25 do
		free = free and not solidAt(x, y, bay.z1 - 0.1, true, false)
	end
end
check("… all of it (6.6 × 7.6)", free)
free = true
for z = S.Slider.Front + 0.05, S.Slider.Front + S.Slider.Width - 0.05, 0.2 do
	for y = bay.y0 + 0.05, bay.y0 + S.Slider.Height - 0.05, 0.2 do
		free = free and not solidAt(bay.x1 + 0.35, y, z, false, true) and solidAt(bay.x1 + 0.35, y, z, false, false)
	end
end
check("the sliding door's opening (5.0 × 6.9 on the right): blocked shut, free open", free)
check("… a body (6 tall) walks through it", S.Slider.Height >= 6 and S.Slider.Width >= 3)
check("the bay's height for a body (7.6, a body ~5)", S.Bay.Height >= 6)

-- the steps: ground → step → floor, rises a body walks up (Roblox's step-up ~2)
local rear, side = switched.RearStep, switched.SideStep
check("the rear step folds out with the back: solid only while it is open", rear ~= nil and rear.s.door == "back" and rear.s.solid == "open")
check("… its top 1.2 up: rises 1.2 and 1.2 to the floor", rear ~= nil and math.abs(rear.e[4] - S.Step.Top) < EPS and S.Step.Top <= 1.25
	and S.Bay.Floor - S.Step.Top <= 1.25)
check("… behind the back, under the doorway, Depth deep", rear ~= nil and rear.e[5] >= S.Length / 2 - EPS and rear.e[6] - rear.e[5] >= 1.2
	and rear.e[1] < -1 and rear.e[2] > 1)
check("the side step comes out with the sliding door, its top 1.2 up, outside the side under the opening", side ~= nil and side.s.door == "slide"
	and side.s.solid == "open" and math.abs(side.e[4] - S.SideStep.Top) < EPS and side.e[1] >= S.Width / 2 - EPS and side.e[5] >= S.Slider.Front - EPS
	and side.e[6] <= S.Slider.Front + S.Slider.Width + EPS)
check("the shut doors' blocks never show", switched.BackBlock.s.finish == nil and switched.SlideBlock.s.finish == nil)

-- ── The back doors, the sliding door ────────────────────────────────────────
local leaves = Looks.leaves()
check("two back doors", #leaves == 2)
local leavesOk, cover = true, 0
for n, leaf in leaves do
	local side = if n == 1 then -1 else 1
	cover += leaf.size[1] * leaf.size[2]
	leavesOk = leavesOk and leaf.angle == side * S.Doors.Swing and math.abs(leaf.hinge[1] - side * S.Width / 2) < EPS
		and math.abs(leaf.hinge[3] - S.Length / 2) < EPS
	-- open: turned about Y round the hinge (Vehicles' BackHinge: Transform = angle about Y)
	local a = math.rad(leaf.angle)
	local dx, dz = leaf.center[1] - leaf.hinge[1], leaf.center[3] - leaf.hinge[3]
	local cx = leaf.hinge[1] + dx * math.cos(a) + dz * math.sin(a)
	local cz = leaf.hinge[3] - dx * math.sin(a) + dz * math.cos(a)
	local open = extent(leaf.size, { cx, leaf.center[2], cz }, { 0, leaf.angle, 0 })
	leavesOk = leavesOk and math.min(math.abs(open[1]), math.abs(open[2])) >= S.Width / 2 - EPS and open[6] <= S.Length / 2 + EPS
		and open[5] > Looks.Axle -- (behind the rear wheel)
end
check("the back doors hinge at the body's back corners and swing 270° flat against the sides, behind the rear wheels", leavesOk)
check("… shut, they cover the opening", math.abs(cover - S.Bay.Width * (S.Bay.Height - 0.05)) < 0.5, cover)
local slider, move = Looks.slider()
local door = extent(slider[1].size, slider[1].at)
local moved: Ext = { door[1] + move[1], door[2] + move[1], door[3], door[4], door[5] + move[2], door[6] + move[2] }
check("the sliding door covers its opening shut", door[5] <= S.Slider.Front + EPS and door[6] >= S.Slider.Front + S.Slider.Width - EPS
	and door[3] <= S.Bay.Floor + EPS and door[4] >= S.Bay.Floor + S.Slider.Height - EPS)
check("… open, it stands clear of the opening, outside the side", moved[5] >= S.Slider.Front + S.Slider.Width - EPS and moved[1] > door[2] - EPS
	and moved[6] < S.Length / 2 - 3) -- (and ahead of the folded back door)

-- ── The hull over the ground ────────────────────────────────────────────────
local low, angles = true, true
for _, e in { chassis, table.unpack(hull) } do
	low = low and e[3] >= 0.25
	if e[5] < -Looks.Axle then
		angles = angles and math.deg(math.atan2(e[3], -Looks.Axle - e[5])) >= 15
	end
	if e[6] > Looks.Axle then
		angles = angles and math.deg(math.atan2(e[3], e[6] - Looks.Axle)) >= 15
	end
end
check("only the wheels touch the ground: the hull 1.2+ up (the chassis' clearance)", low)
check("15° from both axles to whatever the hull has past them (the steepest road 14°)", angles)

-- ── The skin ────────────────────────────────────────────────────────────────
local pieces = Looks.body()
for _, s in { -1, 1 } do
	for _, p in Looks.door(s) do
		table.insert(pieces, p)
	end
end
for _, leaf in leaves do
	for _, p in leaf.pieces do
		table.insert(pieces, p)
	end
end
for _, p in slider do
	table.insert(pieces, p)
end
local within, outOfRoom, finishes = true, true, true
local room: Ext = { bay.x0 + 0.15, bay.x1 - 0.15, bay.y0 + 0.15, bay.y1 - 0.2, bay.z0 + 0.15, bay.z1 - 0.3 }
local where: string? = nil
for _, p in pieces do
	local e = extent(p.size, p.at, p.turn)
	local mirror = S.Width / 2 + S.Mirror
	if e[1] < -mirror - 0.05 or e[2] > mirror + 0.05 or e[3] < -EPS or e[4] > S.Height + EPS or e[5] < -S.Length / 2 - 0.07 or e[6] > S.Length / 2 + 0.07 then -- (the plates, the handles)
		within = false
		where = p.name
	end
	if meets(e, room) then
		outOfRoom = false
		where = p.name
	end
	finishes = finishes and Looks.Finish[p.finish] ~= nil and (p.ink == nil or Looks.Finish[p.ink] ~= nil)
end
check("the skin inside the body's box (8.0 × 10.4 × 22.0, the mirrors out to 0.8 more)", within, where)
check("… nothing of it in the bay's walking room (the lining, rails and lamps on its walls)", outOfRoom, where)
check("… every finish known", finishes)
local texts: { [string]: number } = {}
local red = 0
for _, p in pieces do
	if p.text then
		texts[p.text] = (texts[p.text] or 0) + 1
	end
	if p.finish == "stripe" and p.size[2] < 0.6 then
		red += 1
	end
end
check("the Deliveros livery: Deliveros on both sides and the back door, the company's name, the plates", (texts.DELIVEROS or 0) == 3
	and (texts["MOVING & STORAGE\nMOVE · FIND · GROW"] or 0) == 2 and (texts["DLV 02"] or 0) == 2)
check("… the red stripe all round (both sides, the doors, the back)", red >= 10, red)
local count = #pieces + #Looks.hull() + #Looks.Switched
check("the part budget: SprinterLooks' parts at most 150 (Vehicles adds ~30: chassis, wheels, seats, doors' panels)", count <= 150, count)

-- ── Points ──────────────────────────────────────────────────────────────────
local cabFront, cabBack = -S.Length / 2, -S.Length / 2 + S.Cab
check("the driver on the left and one passenger on the right, in the cab", Looks.Seat[1] < 0 and Looks.Passenger[1] > 0 and Looks.Seat[3] > cabFront
	and Looks.Seat[3] < cabBack and Looks.Passenger[3] == Looks.Seat[3])
check("the Load and back prompts at the back opening's middle, 0.6 out (as every car's)", Looks.CargoDoor[1] == 0
	and math.abs(Looks.CargoDoor[3] - (S.Length / 2 + 0.6)) < EPS and Looks.CargoDoor[2] > S.Bay.Floor)
check("the bay's light under its ceiling, in its middle", math.abs(Looks.Light[3] - (bay.z0 + bay.z1) / 2) < EPS and Looks.Light[2] < bay.y1)
-- the owner's Blender model (server/SprinterMesh.luau, design/blender-sprinter/roblox/ZDCSprinterArt.json) is put on
-- these: its seats, its cab doors' hinges (their front edge), its sliding door's way
check("the seats where the Blender model's are: (±1.7, 1.3, -5.75) from the chassis' top", math.abs(Looks.Seat[1] + 1.7) < EPS
	and math.abs(Looks.Seat[2] - Looks.Top - 1.3) < EPS and math.abs(Looks.Seat[3] + 5.75) < EPS)
check("the cab doors hinged at z -8.55 (the model's pivot), back to the cab's end", math.abs(Looks.Seat[3] - Looks.DoorSpan[1] + 8.55) < EPS
	and Looks.Seat[3] + Looks.DoorSpan[2] <= -S.Length / 2 + S.Cab + EPS)
check("the sliding door: its opening from z -2.85, 0.35 out and 5.0 back (the model's door)", S.Slider.Front == -2.85 and move[1] == 0.35
	and move[2] == 5.0)

-- ── The car ─────────────────────────────────────────────────────────────────
local def = Economy.findCar("sprinter") :: Config.CarDef
local van = Economy.findCar(Config.CompanyVan.Car) :: Config.CarDef
check("Config.Cars sprinter: the Deliveros Sprinter, style sprinter, the sandbox's van", def ~= nil and def.name == "Deliveros Sprinter" and def.style == "sprinter"
	and Config.Sandbox.Van == "sprinter")
check("… heavier than the Deliveros Van: slower, slower off the line, a wider turn, tougher", def.maxSpeed < van.maxSpeed and def.accel < van.accel
	and def.turn < van.turn and def.health >= van.health)
check("… a big tank (no pumps in the sandbox): 100,000 studs and more", def.tank ~= nil and def.burn ~= nil
	and (def.tank :: number) * 1000 / (def.burn :: number) * Config.Fuel.Lasts >= 100000)
check("… sandbox-only: no stages, no roof gun, no gear, never sold", def.sandboxOnly == true and def.stages == nil and not def.mount
	and (def.gearSlots or 0) == 0 and def.price == 0)
check("… a player's car only while the sandbox is on", Economy.isPlayerCar("sprinter") == Config.Sandbox.On)
check("… never a bigger car's advice", string.find(Economy.roomAdvice(Config.CompanyVan.Car, 0, 9), "Sprinter", 1, true) == nil)
check("the Deliveros Van stays Config.Cars[1]", Config.Cars[1].id == Config.CompanyVan.Car)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
