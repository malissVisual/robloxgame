-- The packing fix in the ZDC Van, on the real server/Moving.luau (tests/run_tests.py builds MovingServer.luau and
-- MoveHelperServer.luau on tests/runtime/MovingRuntime.luau's fakes): a solo move in the van (Config.Moving.Beds.zdcvan,
-- 6.2 × 6.4 × 4.3, Cell 0.4), Danny's hands loading through Moving.helperLoad (the rules, the welds, as a player's Load).
--   * Pack.Lie: Grandpa's Clock (6 tall, two hands) has no place standing in the 4.3-high bay: it lies on its side, its
--     model rolled (its up along the floor), every corner of it inside the bay, on the floor.
--   * Pack.Repack: the box and the lamp in, then a slab the bay's whole floor wide: no room as the bed is (canLoad still
--     says yes), so Load repacks it: the slab first, the clock (still lying), the box and the lamp welded again on its
--     top, every model inside the bay.
--   * The Load prompt for a player carrying the sofa (no room even repacked): "Load Sofa", "won't fit · N% full"; pressed,
--     the refusal ("No room") and the sofa stays in the hands.
-- The test's fake art is resized for it (its own process: tests/runtime/MovingRuntime.luau's items).
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Config = require("./Config")
local Map = require("./Map")
local Rules = require("./MovingRules")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local T = Config.Moving
local M = E.Mock
local V3 = M.Vector3.new

local home = Map.home(T.Contracts[1].home) :: any
E.truckAt = V3(home.door.x + 30, 2, home.door.z - 20)
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0)
end
MoveHelper.useMover({
	move = function(body: any, to: any)
		body.root.CFrame = M.CFrame.new(to.X, body.root.Position.Y, to.Z)
	end,
	halt = function() end,
})
-- the pieces for it: a lamp and a box that stand on a slab under the roof, a slab the bay's whole floor (15 × 16 cells)
E.items.lamp.size = V3(1, 2, 1)
E.items.box.size = V3(2, 1.5, 2)
E.items.slab.size = V3(6, 2, 6.4)
E.carId = "zdcvan"

local sol = E.player(44, "Sol", V3(Map.Depot.x, 3, Map.Depot.z))
Moving.useArt(E.art)
Moving.start()
local started = Moving.admin(sol, "start")
check("a solo move in the ZDC Van", string.find(started, "started", 1, true) ~= nil and E.cars[sol] ~= nil and E.cars[sol].id == "zdcvan", started)
Moving.step()
local danny = MoveHelper.find(sol)
check("Danny is there (his hands load for the test)", danny ~= nil and danny.body ~= nil and danny.s ~= nil)
local s = danny.s
local npc = danny.body.model
local truck = E.cars[sol]
local BED = T.Beds.zdcvan
local FLOOR = 0.6 -- (the fake van's cargo slots: the floor over the chassis' middle)

local function itemModel(spot: number): any
	for _, d in M.workspace:GetDescendants() do
		if d.ClassName == "Model" and d:GetAttribute("MoveSpot") == spot and not d.destroyed then
			return d
		end
	end
	return nil
end
-- A model's root in the chassis' frame: its corners' box (min, max) and its up axis.
local function box(model: any): (any, any, any)
	local root = model.PrimaryPart
	local rel = truck.chassis.CFrame:Inverse() * root.CFrame
	local size = root.Size
	local low, high = V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local p = rel * V3(sx * size.X / 2, sy * size.Y / 2, sz * size.Z / 2)
				low = V3(math.min(low.X, p.X), math.min(low.Y, p.Y), math.min(low.Z, p.Z))
				high = V3(math.max(high.X, p.X), math.max(high.Y, p.Y), math.max(high.Z, p.Z))
			end
		end
	end
	return low, high, rel * V3(0, 1, 0) - rel.Position
end
-- Inside the bay: across its width, along its length round its middle (Center), between its floor and its roof.
local function inside(model: any): boolean
	local low, high = box(model)
	local eps = 1e-6
	return low.X >= BED.Center[1] - BED.Width / 2 - eps and high.X <= BED.Center[1] + BED.Width / 2 + eps
		and low.Z >= BED.Center[2] - BED.Length / 2 - eps and high.Z <= BED.Center[2] + BED.Length / 2 + eps
		and low.Y >= FLOOR - eps and high.Y <= FLOOR + BED.Height + eps
end
local function load(spot: number): (boolean, string?)
	Rules.pick(s.move, spot, danny.id)
	local ok, why = Moving.helperLoad(s, npc)
	if not ok then
		Rules.release(s.move, danny.id)
	end
	return ok, why
end

-- Lying down ---------------------------------------------------------------------------------------------------------------

check("the van's bed: its whole 6.4 length in 0.4 cells (15 × 16)", s.move.packing.cell == 0.4 and s.move.packing.cols == 15 and s.move.packing.rows == 16)
check("Grandpa's Clock (6 tall) has no place standing in the 4.3-high bay", not Rules.room(s.move.packing, s.move.things[4].size) and Rules.canLoad(s.move, 4))
local ok = load(4)
local clockAt = s.move.things[4].place
local clock = itemModel(4)
local low, _, up = box(clock)
check("…Load lays it on its side (Pack.Lie)", ok and clockAt ~= nil and clockAt.lying ~= nil and clockAt.top <= BED.Height + 1e-6, clockAt and clockAt.lying)
check("…its model rolled: its up along the floor", math.abs(up.Y) < 1e-6 and math.abs(up.Magnitude - 1) < 1e-6, up)
check("…every corner of it inside the bay, on its floor", inside(clock) and math.abs(low.Y - FLOOR) < 1e-6, low)

-- Repacking -----------------------------------------------------------------------------------------------------------------

check("the box and the lamp in", (load(5)) and (load(1)) and inside(itemModel(5)) and inside(itemModel(1)))
check("the slab: no room as the bed is, but Load would take it (repacked)", not Rules.room(s.move.packing, s.move.things[6].size, true) and Rules.canLoad(s.move, 6))
local slabOk = load(6)
local slab = itemModel(6)
local slabLow, slabHigh = box(slab)
check("…Load repacks the van: the slab in, on the floor", slabOk and s.move.things[6].state == "truck" and math.abs(slabLow.Y - FLOOR) < 1e-6 and inside(slab), slabLow)
local top = slabHigh.Y
local function onTop(spot: number): boolean
	local model = itemModel(spot)
	local l = box(model)
	return math.abs(l.Y - top) < 1e-6 and inside(model) and model.PrimaryPart:FindFirstChildOfClass("WeldConstraint") ~= nil
end
check("…the clock, the box and the lamp welded again on its top, inside the bay", onTop(4) and onTop(5) and onTop(1))
local _, _, up2 = box(clock)
check("…the clock still lying", s.move.things[4].place.lying ~= nil and math.abs(up2.Y) < 1e-6)
check("…Take out: a top one, never the slab", Rules.lastOut(s.move) ~= 6 and Rules.lastOut(s.move) ~= nil)

-- "won't fit" on the Load prompt ----------------------------------------------------------------------------------------------

check("the sofa has no room even repacked", not Rules.canLoad(s.move, 3))
local door = truck.chassis:FindFirstChild("CargoDoor")
truck.model:SetAttribute("BackOpen", true)
E.place(sol, door.WorldPosition + V3(0, 0, 2))
Rules.pick(s.move, 3, sol.UserId)
E.clock += 0.2
Moving.step()
local loadPrompt: any = nil
for _, d in truck.model:GetDescendants() do
	if d.ClassName == "ProximityPrompt" and string.find(tostring(d.ActionText), "Load", 1, true) == 1 then
		loadPrompt = d
	end
end
check("carrying it at the back: \"Load Sofa\", \"won't fit · N% full\"", loadPrompt ~= nil and loadPrompt.Enabled and loadPrompt.ActionText == "Load Sofa"
	and string.find(loadPrompt.ObjectText, "won't fit · ", 1, true) == 1 and string.find(loadPrompt.ObjectText, "% full", 1, true) ~= nil, loadPrompt and loadPrompt.ObjectText)
loadPrompt.Triggered:Fire(sol)
check("…pressed: the refusal, the sofa still in the hands", string.find(E.lastNotice(sol), "No room", 1, true) ~= nil and s.move.things[3].state == "carried"
	and s.move.things[3].carrier == sol.UserId, E.lastNotice(sol))
Moving.admin(sol, "end")

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
