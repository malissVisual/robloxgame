-- 8.3 the lodge: shared/LodgeLooks.luau, The Alpine Lodge's outside as numbers (pure, in the Luau CLI), on the sandbox's
-- house box (shared/SandboxMap.luau House, SandboxScenery.lodgeSpec): within its part budget, sound numbers, its body
-- the house's box, only the body, the roof's two wedges and the doorways solid; the front door (House.doorWidth) in the
-- middle of the front wall, the terrace door on the east wall; each door's leaves (LodgeLooks.Leaves) shut in it, hinged
-- at a jamb; nothing in a door's way out; the balcony under the deep front eave; the roof's slabs over its wedges, the
-- chimneys through it; the name board says the house's name; everything on the lot; bigger than the chalet it replaced.
-- Run with tests/run_tests.py.
local LodgeLooks = require("./LodgeLooks")
local ChaletLooks = require("./ChaletLooks")
local SandboxMap = require("./SandboxMap")
local SandboxScenery = require("./SandboxScenery")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local H = SandboxMap.House
local spec = SandboxScenery.lodgeSpec()
local pieces = LodgeLooks.house(spec)
local w, h, d = spec.w, spec.h, spec.d
local half = w / 2
local EPS = 1e-6

type Box = { name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, piece: any }
local boxes: { Box } = {}
local byName: { [string]: { Box } } = {}
for _, p in pieces do
	local x0, x1, y0, y1, z0, z1 = ChaletLooks.box(p)
	local b: Box = { name = p.name, x0 = x0, x1 = x1, y0 = y0, y1 = y1, z0 = z0, z1 = z1, piece = p }
	table.insert(boxes, b)
	byName[p.name] = byName[p.name] or {}
	table.insert(byName[p.name], b)
end
local function named(name: string): { Box }
	return byName[name] or {}
end
local function one(name: string): Box?
	local list = named(name)
	return if #list == 1 then list[1] else nil
end

-- the spec is the map's house
check("the spec is SandboxMap.House's box, door width and terrace door", spec.w == H.house.sx and spec.h == H.house.sy and spec.d == H.house.sz
	and spec.doorWidth == H.doorWidth and spec.terrace == H.back.z - H.door.z and spec.ground > 6 and spec.ground < spec.h - 6)
check(`within the part budget ({#pieces} of {LodgeLooks.Budget})`, #pieces <= LodgeLooks.Budget and #pieces >= 60, #pieces)
check("the same pieces every time (no dice)", #LodgeLooks.house(spec) == #pieces)

-- sound numbers, known materials and shapes
local bad: string? = nil
local MATERIALS = { Plaster = true, Slate = true, WoodPlanks = true, Wood = true, Glass = true, Grass = true, Neon = true }
for _, p in pieces do
	for _, v in p.size do
		if v ~= v or v <= 0 or v > 100 then
			bad = `{p.name}: size`
		end
	end
	for _, v in p.at do
		if v ~= v or math.abs(v) > 200 then
			bad = `{p.name}: place`
		end
	end
	for _, c in p.color do
		if c < 0 or c > 255 then
			bad = `{p.name}: colour`
		end
	end
	if not MATERIALS[p.material] or (p.shape ~= nil and p.shape ~= "Wedge" and p.shape ~= "Cylinder") then
		bad = `{p.name}: {p.material} / {p.shape}`
	end
	if p.material == "Neon" then
		bad = `{p.name}: glows (the owner: nothing bright)`
	end
end
check("every piece: a size, a place, a colour, a material and a shape it may have; nothing glows", bad == nil, bad)

-- the body and what is solid
local body = one("House")
check("its body: the house's box (its front wall at z 0, its walls h high)", body ~= nil and math.abs(body.x0 + half) < EPS and math.abs(body.x1 - half) < EPS
	and math.abs(body.z0) < EPS and math.abs(body.z1 - d) < EPS and math.abs(body.y0) < EPS and math.abs(body.y1 - h) < EPS)
local solid: { string } = {}
for _, p in pieces do
	if p.solid then
		table.insert(solid, p.name)
	end
end
table.sort(solid)
check(`solid: the body, the roof's two wedges and the two doorways only ({table.concat(solid, ", ")})`, table.concat(solid, ",") == "Door,House,Roof,Roof,TerraceDoor")

-- the doors and their leaves
local door, terrace = one("Door"), one("TerraceDoor")
check("the front door: House.doorWidth wide, in the middle of the front wall, on the ground", door ~= nil and math.abs((door.x1 - door.x0) - spec.doorWidth) < 0.01
	and math.abs(door.x0 + door.x1) < EPS and door.z1 <= EPS and door.z0 > -0.5 and math.abs(door.y0) < 0.05 and door.y1 > 7)
check("the terrace door: on the east wall, spec.terrace back from the front, on the ground", terrace ~= nil and terrace.x0 >= half - EPS and terrace.x1 < half + 0.5
	and math.abs((terrace.z0 + terrace.z1) / 2 - spec.terrace) < EPS and math.abs(terrace.y0) < 0.05 and terrace.y1 > 7)
local leavesOk = true
local count = 0
for name, leaf in LodgeLooks.Leaves do
	count += 1
	local b = one(name)
	local doorway = if leaf.door == "front" then door else terrace
	if not b or not doorway then
		leavesOk = false
		continue
	end
	-- (shut: inside its doorway's box; its hinge a jamb of it: west -X, east +X, south +Z of the house's frame)
	local inside = b.x0 >= doorway.x0 - 0.1 and b.x1 <= doorway.x1 + 0.1 and b.z0 >= doorway.z0 - 0.1 and b.z1 <= doorway.z1 + 0.1 and b.y0 >= -0.05 and b.y1 <= doorway.y1 + 0.05
	local hinged = (leaf.hinge == "west" and math.abs(b.x0 - doorway.x0) < 0.1) or (leaf.hinge == "east" and math.abs(b.x1 - doorway.x1) < 0.1)
		or (leaf.hinge == "south" and math.abs(b.z1 - doorway.z1) < 0.1)
	leavesOk = leavesOk and inside and hinged and not b.piece.solid
end
check("the doors' leaves (FrontLeafWest, FrontLeafEast, TerraceLeaf): each shut in its doorway, hinged at a jamb, not solid", leavesOk and count == 3
	and one("FrontLeafWest") ~= nil and one("FrontLeafEast") ~= nil and one("TerraceLeaf") ~= nil)
local front = one("FrontLeafWest")
local back = one("FrontLeafEast")
check("…the front door's two leaves fill it between them", front ~= nil and back ~= nil and math.abs((front.x1 - front.x0) + (back.x1 - back.x0) - spec.doorWidth) < 0.2)

-- nothing in a door's way out (a body's height, the doorway's width and a little, 5 out), but the door's own pieces, the
-- wall's skin (the plinth, 0.08 out of it) and what lies flat on the ground
local OWN = { Door = true, FrontLeafWest = true, FrontLeafEast = true, DoorSurround = true, TerraceDoor = true, TerraceLeaf = true, TerraceSurround = true }
local ways = {
	{ name = "the front door's", x0 = -spec.doorWidth / 2 - 0.5, x1 = spec.doorWidth / 2 + 0.5, z0 = -5, z1 = -0.15 },
	{ name = "the terrace door's", x0 = half + 0.45, x1 = half + 5, z0 = spec.terrace - 2.5, z1 = spec.terrace + 2.5 },
}
local blocked: string? = nil
for _, b in boxes do
	if OWN[b.name] or b.y1 <= 0.35 or b.y0 >= 7.5 then
		continue
	end
	for _, way in ways do
		if b.x0 < way.x1 and b.x1 > way.x0 and b.z0 < way.z1 and b.z1 > way.z0 then
			blocked = `{b.name} in {way.name} way`
		end
	end
end
check("nothing in either door's way out (a body's height)", blocked == nil, blocked)

-- the balcony, the roof, the chimneys
local floor = one("BalconyFloor")
local rise, eaves = LodgeLooks.roof(spec)
check("the balcony along the whole front on the ground floor's top, under the deep front eave", floor ~= nil and floor.x1 - floor.x0 >= w and math.abs(floor.y1 - spec.ground - 0.25) < 0.05
	and -floor.z0 < eaves.Front and #named("Balustrade") == 1 and #named("BalconyStrut") == 4)
local wedges = named("Roof")
local slabs = named("RoofShingles")
local covered = #wedges == 2 and #slabs == 2
if covered then
	local lo, hi = math.huge, -math.huge
	for _, s in slabs do
		lo, hi = math.min(lo, s.z0), math.max(hi, s.z1)
		covered = covered and s.x0 <= -half - eaves.Side + 0.1 and s.x1 >= half + eaves.Side - 0.1
	end
	covered = covered and lo <= -eaves.Front + 0.3 and hi >= d + eaves.Back - 0.3
	for _, wg in wedges do
		covered = covered and math.abs(wg.y0 - h) < EPS and math.abs(wg.y1 - (h + rise)) < EPS
	end
end
check(`the gable across the house ({string.format("%.1f", rise)} over the walls): its wedges, the slate over them with deep eaves, the ridge on top`, covered
	and one("RoofRidge") ~= nil and (one("RoofRidge") :: Box).y1 > h + rise)
local chimneys = true
for _, c in named("Chimney") do
	local z = (c.z0 + c.z1) / 2
	local slope = h + rise - (z - d / 2) * (rise / (d / 2))
	chimneys = chimneys and c.y1 > slope + 2 and c.y0 < slope and z > d / 2
end
check("two chimneys through the back slope", #named("Chimney") == 2 and #named("ChimneyCap") == 2 and chimneys)
check("the cross gable over the entrance, its sun", #named("CrossGable") == 2 and #named("CrossShingles") == 2 and one("GableSun") ~= nil)

-- the name, the lot, the size
check("the name board on the balcony says the house's name", LodgeLooks.Sign == string.upper(H.name) and one("LodgeSign") ~= nil
	and (one("LodgeSign") :: Box).y0 > spec.ground and (one("LodgeSign") :: Box).z1 < 0)
local lot = H.lot
local outside: string? = nil
for _, b in boxes do
	-- (the house's frame on the map: yaw 0, its origin at House.door)
	if b.x0 + H.door.x < lot.x0 or b.x1 + H.door.x > lot.x1 or b.z0 + H.door.z < lot.z0 or b.z1 + H.door.z > lot.z1 then
		outside = b.name
	end
end
check("every piece on the house's lot", outside == nil, outside)
check(`bigger than the chalet it replaced (20.4 × 12.6 × 17.6): {w} × {h} × {d}, two storeys`, w * d >= 2 * 20.36 * 17.57 and h >= 12.6 + 6)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
