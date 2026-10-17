-- The real house art × a whole run end to end (10.6: every move a run): the real shared/FurnitureLooks.luau,
-- shared/HouseLayout.luau and server/HouseInterior.luau (tests/run_tests.py builds them on tools/fixtures/item-mock.luau,
-- the recorder tests/runtime/MovingRuntime.luau's fakes stand on) and the real server/Moving.luau: a run of Ann and Bob
-- on the lone house (a family house's plan, seed 1955: Ann's card), the real interior built and in the world, in through
-- the front door (open from the start), the house lit (the real ceiling lights on, the porch's daylight on, no fuse box);
-- a real one-hand piece picked up, carried out, loaded, and FINISH: it goes home (the one whose model went never counts),
-- the interior taken down. 8.1 walk-in doors with the real house: in clear of the doorway's zone facing the hall, the
-- ▲ OUT doormat, out by walking into the real 7-wide front doorway, in by walking up to the door.
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local FurnitureLooks = require("./FurnitureLooks")
local HouseLayout = require("./HouseLayout")
local HouseInterior = require("./HouseInterior")

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
local workspace = M.workspace

local function promptIn(model: any, action: string): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and d.ActionText ~= nil and string.find(tostring(d.ActionText), action, 1, true) == 1 then
			return d
		end
	end
	return nil
end
local function trigger(prompt: any, player: any)
	prompt.Triggered:Fire(player)
end
local function lights(model: any): (number, number)
	local on, off = 0, 0
	for _, d in model:GetDescendants() do
		if d.ClassName == "PointLight" or d.ClassName == "SpotLight" then
			if d.Enabled == false then
				off += 1
			else
				on += 1
			end
		end
	end
	return on, off
end

-- the real art, its builds counted (and its origin given to the recorder's rays: the interior's floor)
local built: { any } = {}
Moving.useArt({
	looks = FurnitureLooks,
	layout = HouseLayout,
	interior = {
		slot = HouseInterior.slot,
		build = function(plan: any, origin: any): (any, any)
			E.built += 1
			table.insert(E.interiors, origin)
			local model, pieces = HouseInterior.build(plan, origin)
			table.insert(built, { model = model, plan = plan, origin = origin, pieces = pieces })
			return model, pieces
		end,
		destroy = function(model: any)
			E.destroyed += 1
			HouseInterior.destroy(model)
		end,
	},
})

local HOUSE = "lone_house"
local door, facing, outside = E.doorOf(SandboxMap.house(HOUSE))
local ann = E.player(11, "Ann", outside)
local bob = E.player(22, "Bob", outside + V3(2, 0, 0))
E.crew[ann] = { bob }
E.profiles[ann] = { sandboxHouse = HOUSE, sandboxHouseSeed = 1955 } -- (her card's house and seed: the plan this test knows)
Moving.parkVan = E.parkVan
Moving.start()
local ends: { any } = {}
Moving.onRunEnd(function(_host: any, facts: any)
	table.insert(ends, facts)
end)

-- the run -----------------------------------------------------------------------------------------------------------------

local moves = workspace:FindFirstChild("Moves")
local plan = HouseLayout.plan(1955, "house")
check("the run: Ann's van at the curb, the real interior built at its slot", E.startRun(ann, HOUSE) == nil and E.cars[ann] ~= nil and built[1] ~= nil and E.built == 1
	and built[1].origin.Position.Y == Config.Furniture.Slot.Origin[2])
local truck = E.cars[ann]
local interior = built[1] and built[1].model
local origin = built[1] and built[1].origin
check("…the plan the card's seed's (the real plan's pieces), and the interior in the world (server/HouseInterior.luau builds it unparented)",
	#built[1].plan.spots == #plan.spots and interior:IsDescendantOf(workspace))
Moving.step()
check("Ann and Bob on the run (MoveWith)", ann:GetAttribute("MoveWith") == 11 and bob:GetAttribute("MoveWith") == 11)

-- the door (open), the house (lit) -------------------------------------------------------------------------------------------

local site = moves:FindFirstChild(`Move_{HOUSE}`)
check("the front door open from the start: no Pick lock, no Kick door", promptIn(site, "Pick lock") == nil and promptIn(site, "Kick door") == nil
	and promptIn(site, "Enter house") ~= nil and not promptIn(site, "Enter house").Enabled) -- (8.1 walk-in doors: walked through, the prompt off)
E.place(ann, outside)
trigger(promptIn(site, "Enter house"), ann)
local entry = (origin * plan.entry).Position
check("Ann in through the real front door", (E.rootOf(ann).Position - entry).Magnitude < 6, E.rootOf(ann).Position)
local on, off = lights(interior)
local function named(model: any, name: string): any -- (the recorder's FindFirstChild has no recursive form)
	for _, d in model:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end
local daylight = named(interior, "Daylight")
check(`lit inside from the start: the real ceiling lights on ({on}), the porch's daylight on`, on >= 8 and off == 0 and daylight ~= nil
	and daylight:FindFirstChildOfClass("SurfaceLight") ~= nil and daylight:FindFirstChildOfClass("SurfaceLight").Enabled ~= false, `{on} on, {off} off`)
check("no fuse box in the house any more", named(interior, "FuseBox") == nil)
-- 8.1 walk-in doors with the real house: in at the plan's entry clear of the doorway's zone, facing into the hall; the
-- ▲ OUT doormat on the hall's floor; out by walking into the real front doorway (7 wide: near its jamb too, past the old
-- Leave part's 4), in again by walking up to the front door outside
do
	local D = T.Doors
	local exitAt0 = (origin * M.CFrame.new(plan.exit)).Position
	local into = (origin * V3(0, 0, 1)) - origin.Position
	local side = V3(-into.Z, 0, into.X)
	local function stand(player: any, at: any, look: any)
		E.rootOf(player).CFrame = M.CFrame.lookAt(at, at + look)
	end
	local function isIn(player: any): boolean
		return (E.rootOf(player).Position - origin.Position).Magnitude < 200
	end
	check("8.1 walk-in doors, the real house: in at the plan's entry, clear of the doorway's zone (Depth), facing into the hall",
		(E.rootOf(ann).Position - exitAt0):Dot(into) > D.Depth and E.rootOf(ann).CFrame.LookVector:Dot(into) > 0.99, (E.rootOf(ann).Position - exitAt0):Dot(into))
	local mat = named(interior, "WalkInMat")
	local words = mat and mat:FindFirstChildOfClass("SurfaceGui"):FindFirstChildOfClass("TextLabel")
	check("…the ▲ OUT doormat on the hall's floor just inside the front doorway", mat ~= nil and words.Text == "▲ OUT" and math.abs(mat.Position.Y - origin.Position.Y - 0.12) < 0.05
		and (mat.Position - exitAt0):Dot(into) > 0 and (mat.Position - exitAt0):Dot(into) < D.Depth and math.abs((mat.Position - exitAt0):Dot(side)) < 0.1)
	E.clock += D.Rearm
	stand(ann, exitAt0 + into * 1 + side * (plan.doors[1].width / 2 - 0.5), -into)
	E.clock += 0.1
	Moving.step()
	E.clock += math.max(D.Dwell, D.Open) + 0.01 -- (8.3: the dwell, the leaf open Open s)
	Moving.step()
	check("…out by walking into the real front doorway near its jamb", not isIn(ann) and (E.rootOf(ann).Position - outside).Magnitude < 6, E.rootOf(ann).Position)
	E.clock += D.Rearm
	stand(ann, door + facing * 2, -facing)
	E.clock += 0.1
	Moving.step()
	E.clock += math.max(D.Dwell, D.Open) + 0.01 -- (8.3: the dwell, the leaf open Open s)
	Moving.step()
	check("…and in again by walking up to the front door", isIn(ann) and (E.rootOf(ann).Position - entry).Magnitude < 6, E.rootOf(ann).Position)
end
E.place(bob, outside)
trigger(promptIn(site, "Enter house"), bob)

-- a real piece: picked up, out, loaded, delivered -------------------------------------------------------------------------

local spot: any = nil
for _, s in plan.spots do
	local def = FurnitureLooks.Items[s.item]
	if not spot and def and def.class == "hand" then
		spot = s
	end
end
local piece = spot and built[1].pieces[spot.id]
check("a real one-hand piece in the house", piece ~= nil and piece.PrimaryPart ~= nil and piece:GetAttribute("FurnitureId") == spot.item, spot and spot.item)
E.place(ann, piece.PrimaryPart.Position + piece.PrimaryPart.CFrame.LookVector * 1.5) -- (9.0 in front of it, in its room)
trigger(promptIn(piece, "Pick up"), ann)
check(`Ann picks up the {spot.item}`, ann.Character:GetAttribute("MoveCarry") == spot.id and ann.Character:GetAttribute("CarryHands") == 1)
local exitAt = (origin * M.CFrame.new(plan.exit)).Position
E.place(ann, exitAt + V3(0, 3, 0))
trigger(promptIn(workspace, "Leave house"), ann)
check("…out through the front door with it", (E.rootOf(ann).Position - outside).Magnitude < 6 and ann.Character:GetAttribute("MoveCarry") == spot.id, E.rootOf(ann).Position)
truck.model:SetAttribute("BackOpen", true)
local cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
E.place(ann, cargoDoor.WorldPosition + V3(0, 0, 2))
E.clock += 0.3
Moving.step()
trigger(promptIn(truck.model, "Load"), ann)
check("…loaded into the truck", ann.Character:GetAttribute("MoveCarry") == nil and string.find(E.lastNotice(ann), "loaded", 1, true) ~= nil, E.lastNotice(ann))
-- 7.0 review: a second one-hand piece loaded, then its model goes (destroyed by something else): it never pays
local second: any = nil
for _, s in plan.spots do
	local def = FurnitureLooks.Items[s.item]
	if not second and s ~= spot and def and def.class == "hand" then
		second = s
	end
end
local piece2 = built[1].pieces[second.id]
E.place(ann, outside)
trigger(promptIn(site, "Enter house"), ann)
E.place(ann, piece2.PrimaryPart.Position + piece2.PrimaryPart.CFrame.LookVector * 1.5) -- (9.0 in front of it, in its room: never through a wall)
trigger(promptIn(piece2, "Pick up"), ann)
E.place(ann, exitAt + V3(0, 3, 0))
trigger(promptIn(workspace, "Leave house"), ann)
E.place(ann, cargoDoor.WorldPosition + V3(0, 0, 2))
E.clock += 0.3
Moving.step()
trigger(promptIn(truck.model, "Load"), ann)
check(`the {second.item} loaded too`, ann.Character:GetAttribute("MoveCarry") == nil and string.find(E.lastNotice(ann), "2 in the van", 1, true) ~= nil, E.lastNotice(ann))
piece2:Destroy()
E.clock += 0.3
Moving.step()
E.request(ann, "finish") -- (the host's FINISH: what is in the truck goes home)
local over = ends[#ends]
check("FINISH: the real piece home in Ann's stock (7.0 review: the one whose model went never counts)", over ~= nil and over.phase == "done" and #over.pieces == 1
	and over.pieces[1].item == spot.item and #E.collected == 1 and E.collected[1].player == ann, over and over.phase)
check("the interior taken down, nobody on the run any more", E.destroyed == 1 and interior.Parent == nil and ann:GetAttribute("MoveWith") == nil)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
