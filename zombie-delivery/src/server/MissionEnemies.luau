--!strict
-- 6.15, a mission's fixed enemies in the world (the owner: "I want them to be about a number of zombies, and you have to
-- complete it, so the mission is always the same"). shared/MissionPlan.luau plans them (the same groups at the same
-- spots every time); server/Jobs.luau runs the mission and calls this every tick; server/Zombies.luau does the bodies.
--
--   MissionEnemies.begin(owner, plan, ground)  a mission started: every enemy of its plan waits at its spot (`ground`:
--                                              the stops' ground height, by stop index)
--   MissionEnemies.step(owner, crew, scale, clearing)
--                                              every tick (0.2 s): the dead are counted; one comes when somebody of the
--                                              job is within Fixed.SpawnRange of its spot (the nearest first, MaxAlive
--                                              of the mission alive at most, Batch a tick); one nobody of the job is
--                                              within ParkRange of waits at its spot again; `clearing`: the stuck rescue
--                                              (below). True when the count changed.
--   MissionEnemies.release(owner, wave)        HOLD OUT: that wave of the plan comes now (it makes for the drop); the
--                                              count, 0 when it came already. releaseAll: every wave (the clearing)
--   MissionEnemies.info(owner)                 { killed, total, left, label }: the job payload's ZOMBIES 7/20
--   MissionEnemies.target(owner, from)         the nearest one left (alive: where it is; waiting: its spot) and its place
--   MissionEnemies.finish(owner)               the mission is over (done, failed, given up, left): every one goes
--   MissionEnemies.killAll(owner)              the admin's KILL MISSION ZOMBIES: the ones left die (they count)
--
-- Each of them is owned by the mission's owner (Zombies' caps and clean-up when they leave), its model has the attribute
-- MissionRun ("<mission id>:<n>", the run), Zombie.leash makes it guard its spot (Zombies leashTarget), and its health
-- is × `scale` (co-op: Economy.coopEnemies of the crew; their number never changes). Any death counts: a crew
-- member's kill, a car running it over, a blast, the depot burning it. The count shown is always the plan's whole
-- total: the ones still waiting count as left.
--
-- 6.15 review:
--   * The crew decides, nobody else, and only its living: one comes when somebody of it out of the safe zone is within
--     SpawnRange of its own spot (a HOLD OUT wave's: once let loose, and near too); one nobody of it is within
--     ParkRange of (one in the safe zone: within Fixed.Leash, a fight over its edge; one idling at the depot keeps
--     nothing alive) goes back to waiting. Zombies never despawns them for distance, so nothing comes and goes again
--     every tick and the alive cap follows the crew.
--   * A spot is checked in the world before it is used (placeOf: room for the body, and from its anchor a way to it
--     with no wall or rock in between): else halfway to the anchor, else round the anchor (a HOLD OUT wave's: the
--     nearest road first), else the anchor itself. Worked out once a slot.
--   * Delivered (clearing): one that has not moved Fixed.StuckMove studs nor been hit for StuckTime s while it should
--     (somebody of the crew close but not at it, or it is away from its spot; a bandit: it sees nobody) goes back to
--     waiting and comes again round its anchor (stuck in a wall, a bunker, a fence).
--   * While a mission runs every other enemy stops Fixed.Reserve short of Config.Horde.MaxTotal (Zombies.missionReserve;
--     a mission's own spawn with `reserved`); the marker (target) goes to the alive ones while no more can come.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)
local MissionPlan = require(Shared.MissionPlan)
local World = require(script.Parent.World)
local Zombies = require(script.Parent.Zombies)

local Fixed = Config.Missions.Fixed

local MissionEnemies = {}

type Slot = {
	group: MissionPlan.Group,
	spot: MissionPlan.Spot,
	index: number, -- its number in its group (its place round the anchor when its spot is blocked)
	state: string, -- "waiting" (at its spot, not in the world) | "alive" | "dead"
	zombie: Zombies.Zombie?,
	at: Vector3?, -- where it comes into the world (placeOf, worked out once)
	rescue: boolean?, -- it got stuck once: it comes round its anchor from now on
	still: Vector3?, -- clearing: where it stood …
	stillSince: number, -- … since when (the stuck rescue)
}

type Run = {
	owner: Player,
	tag: string, -- the MissionRun attribute of its enemies
	plan: MissionPlan.Plan,
	slots: { Slot },
	killed: number,
	alive: number,
	released: { [number]: boolean }, -- HOLD OUT's waves let loose
	barricades: { [number]: Model }, -- HUNTED's bandit cars, by route point
	ground: { [number]: number }, -- the stops' ground height, by stop index
	blocked: boolean, -- the last tick wanted more in the world than could come (the cap, the server's room)
}

local runs: { [Player]: Run } = {}
local started = 0

export type Info = { killed: number, total: number, left: number, label: string }

-- While a mission runs the other enemies leave the reserve to its own (Zombies.missionReserve).
local function reserve()
	Zombies.missionReserve = if next(runs) ~= nil then Fixed.Reserve else 0
end

-- A mission started (server/Jobs.luau startJob): its plan's enemies wait at their spots. A run of the owner's before
-- goes first.
function MissionEnemies.begin(owner: Player, plan: MissionPlan.Plan, ground: { [number]: number })
	MissionEnemies.finish(owner)
	started += 1
	local run: Run = {
		owner = owner,
		tag = `{plan.id}:{started}`,
		plan = plan,
		slots = {},
		killed = 0,
		alive = 0,
		released = {},
		barricades = {},
		ground = ground,
		blocked = false,
	}
	for _, group in plan.groups do
		for index, spot in group.spots do
			table.insert(run.slots, { group = group, spot = spot, index = index, state = "waiting", zombie = nil, at = nil, rescue = nil, still = nil, stillSince = 0 })
		end
	end
	runs[owner] = run
	reserve()
end

local function heightOf(run: Run, group: MissionPlan.Group): number
	return if group.road then World.RoadTop else run.ground[group.stop] or World.RoadTop
end

-- Its anchor in the world: a stop's circle, the road at a route point, the drop for a HOLD OUT wave.
local function anchorOf(run: Run, group: MissionPlan.Group): Vector3
	return Vector3.new(group.x, if group.wave then run.ground[group.stop] or World.RoadTop else heightOf(run, group), group.z)
end

-- How far from its spot it goes after anybody: a zombie Fixed.Leash, a bandit or a gunner its range + 40.
local function leashOf(kind: string): number
	local def = Config.Zombies[kind]
	if def and def.ranged then
		return (def.range or 0) + 40
	end
	return Fixed.Leash
end

-- Where the owner and the crew are (alive; a seated one rides along with the car): out of the safe zone (they bring
-- enemies in and keep them), and in it (they only keep the ones within Fixed.Leash: a fight over its edge, not a
-- member idling at the depot).
local function positions(owner: Player, crew: { Player }): ({ Vector3 }, { Vector3 })
	local out: { Vector3 } = {}
	local inside: { Vector3 } = {}
	local function add(player: Player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			table.insert(if World.isSafe(root.Position) then inside else out, root.Position)
		end
	end
	add(owner)
	for _, member in crew do
		if member ~= owner then
			add(member)
		end
	end
	return out, inside
end

-- The flat distance from the nearest of them (math.huge without anybody).
local function nearest(people: { Vector3 }, at: Vector3): number
	local best = math.huge
	for _, here in people do
		best = math.min(best, Vector3.new(at.X - here.X, 0, at.Z - here.Z).Magnitude)
	end
	return best
end

-- ── Is there room? ─────────────────────────────────────────────────────────

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
overlap.RespectCanCollide = true
local sight = RaycastParams.new()
sight.FilterType = Enum.RaycastFilterType.Exclude
sight.RespectCanCollide = true
local MOVING = { "Zombies", "Cars", "Npcs", "Animals", "Loot", "Cargo" } -- (what moves: not the world's walls)

-- What the checks look through: the enemies, the cars, the people, the players.
local function skipList(): { Instance }
	local list: { Instance } = {}
	for _, name in MOVING do
		local child = workspace:FindFirstChild(name)
		if child then
			table.insert(list, child)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	return list
end

-- Room for a body of `scale` standing at `at` (nothing solid where it stands) and, from `from` (its anchor: a place
-- the crew reaches) unless nil, a way there (no wall, no rock, no bunker in between)?
local function roomAt(at: Vector3, from: Vector3?, scale: number, skip: { Instance }): boolean
	overlap.FilterDescendantsInstances = skip
	local size = Vector3.new(1.6, 3.6, 1.6) * scale
	if #workspace:GetPartBoundsInBox(CFrame.new(at + Vector3.new(0, 1.2 + size.Y / 2, 0)), size, overlap) > 0 then
		return false
	end
	if from then
		sight.FilterDescendantsInstances = skip
		local a, b = from + Vector3.new(0, 3, 0), at + Vector3.new(0, 3, 0)
		if (b - a).Magnitude > 0.5 and workspace:Raycast(a, b - a, sight) ~= nil then
			return false
		end
	end
	return true
end

-- Where a slot comes into the world, worked out once (see the header): its spot; else halfway to its anchor; else
-- round the anchor (a HOLD OUT wave's: the road nearest its spot first); else the anchor itself. Once stuck (rescue):
-- round the anchor.
local function placeOf(run: Run, slot: Slot, skip: { Instance }): Vector3
	local known = slot.at
	if known then
		return known
	end
	local group = slot.group
	local def = Config.Zombies[group.kind]
	local scale = if def then def.scale else 1
	local anchor = anchorOf(run, group)
	local spot = Vector3.new(slot.spot.x, heightOf(run, group), slot.spot.z)
	local angle = slot.index * 2.4
	local ring = anchor + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (3 + (slot.index % 4) * 2)
	-- (the way from the anchor is not asked of a roadblock's bandits, behind their own bandit car, nor of HOLD OUT's
	-- waves, which come from round the corner)
	local from = if group.roadblock or group.wave then nil else anchor
	local tries: { { at: Vector3, from: Vector3? } } = {}
	if not slot.rescue then
		table.insert(tries, { at = spot, from = from })
		if group.wave then
			local rx, rz = Map.nearestRoad(spot.X, spot.Z)
			table.insert(tries, { at = Vector3.new(rx, World.RoadTop, rz), from = nil })
		else
			table.insert(tries, { at = spot:Lerp(anchor, 0.5), from = from })
		end
	end
	table.insert(tries, { at = ring, from = if group.roadblock then nil else anchor })
	local chosen = anchor
	for _, try in tries do
		if not World.isSafe(try.at) and roomAt(try.at, try.from, scale, skip) then
			chosen = try.at
			break
		end
	end
	slot.at = chosen
	return chosen
end

-- ── In and out of the world ────────────────────────────────────────────────

-- One of them into the world (HUNTED: its bandit car first). False when the server is full (later).
local function spawnSlot(run: Run, slot: Slot, scale: number, skip: { Instance }): boolean
	local group = slot.group
	local block = group.roadblock
	local point = group.point
	if block and point and not run.barricades[point] then
		run.barricades[point] = (Zombies.barricade(Vector3.new(block.x, World.RoadTop, block.z), Vector3.new(block.ax, 0, block.az), block.lane))
	end
	local z = Zombies.spawn(group.kind, placeOf(run, slot, skip), run.owner, true, false, false, true)
	if not z then
		return false
	end
	z.leash = leashOf(group.kind)
	z.mission = run.tag
	z.model:SetAttribute("MissionRun", run.tag)
	if group.wave then
		-- HOLD OUT's wave: its spot is the drop (it makes for it) and it goes for whoever holds it from the start.
		z.home = anchorOf(run, group)
		z.alertAt = os.clock()
	end
	if scale > 1 then
		local health = z.humanoid.MaxHealth * scale
		z.humanoid.MaxHealth = health
		z.humanoid.Health = health
	end
	slot.zombie = z
	slot.state = "alive"
	slot.still = nil
	run.alive += 1
	return true
end

-- An alive one back to waiting at its spot (nobody of the crew near, or stuck).
local function park(run: Run, slot: Slot)
	local z = slot.zombie
	if z and not z.dead then
		Zombies.despawn(z)
	end
	slot.zombie = nil
	slot.state = "waiting"
	slot.still = nil
	run.alive -= 1
end

-- Clearing: has it stood still (and not been hit) for Fixed.StuckTime while it should be moving: somebody of the crew
-- close to it but not right at it (a bite, a fight), or it is away from its spot; a bandit that sees somebody shoots
-- from where it stands (not stuck).
local function stuck(slot: Slot, z: Zombies.Zombie, here: Vector3, people: { Vector3 }, now: number): boolean
	local still = slot.still
	if z.car or not still or (here - still).Magnitude > Fixed.StuckMove or (z.alertAt or 0) > slot.stillSince then
		slot.still, slot.stillSince = here, now
		return false
	end
	if now - slot.stillSince < Fixed.StuckTime or (z.def.ranged and z.seenSince ~= nil) then
		return false
	end
	local d = nearest(people, here)
	local away = Vector3.new(here.X - z.home.X, 0, here.Z - z.home.Z).Magnitude > 8
	return away or (d > 10 and d <= (if z.def.ranged then z.leash or Fixed.Leash else Fixed.Aggro))
end

-- Every tick of the mission (server/Jobs.luau updatePlayer): the dead counted, the ones the crew left far behind back
-- to waiting (and, `clearing`, the stuck ones), the waiting ones near the crew brought in. `crew`: the job's members
-- and riders; `scale`: their health × this (co-op). True when the count changed.
function MissionEnemies.step(owner: Player, crew: { Player }, scale: number, clearing: boolean?): boolean
	local run = runs[owner]
	if not run then
		return false
	end
	local now = os.clock()
	local people, inside = positions(owner, crew)
	local changed = false
	for _, slot in run.slots do
		local z = slot.zombie
		if slot.state ~= "alive" or not z then
			continue
		end
		if z.dead then
			slot.zombie = nil
			run.alive -= 1
			if z.killed then
				slot.state = "dead"
				run.killed += 1
				changed = true
			else
				slot.state = "waiting" -- (drowned: back at its spot, it comes again with the crew)
			end
			continue
		end
		local here = z.root.Position
		if not z.car and nearest(people, here) > Fixed.ParkRange and nearest(inside, here) > Fixed.Leash then
			park(run, slot)
		elseif clearing and stuck(slot, z, here, people, now) then
			park(run, slot)
			slot.rescue = true
			slot.at = nil
		end
	end
	run.blocked = false
	if run.killed >= run.plan.total or #people == 0 then
		return changed
	end
	-- The waiting ones near the crew, the nearest first.
	local wanted: { { slot: Slot, distance: number } } = {}
	for _, slot in run.slots do
		local wave = slot.group.wave
		if slot.state == "waiting" and (not wave or run.released[wave]) then
			local at = slot.at or Vector3.new(slot.spot.x, 0, slot.spot.z)
			local d = nearest(people, at)
			if d <= Fixed.SpawnRange then
				table.insert(wanted, { slot = slot, distance = d })
			end
		end
	end
	if #wanted == 0 then
		return changed
	end
	table.sort(wanted, function(a, b)
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		if a.slot.group.id ~= b.slot.group.id then
			return a.slot.group.id < b.slot.group.id
		end
		return a.slot.index < b.slot.index
	end)
	local room = math.min(Fixed.Batch, Fixed.MaxAlive - run.alive)
	local skip: { Instance }? = nil
	for count, entry in wanted do
		if count > room then
			run.blocked = run.alive >= Fixed.MaxAlive -- (the batch only waits a tick)
			break
		end
		skip = skip or skipList()
		if not spawnSlot(run, entry.slot, scale, skip :: { Instance }) then
			run.blocked = true -- (the server's cap: the next tick)
			break
		end
	end
	return changed
end

-- HOLD OUT: wave `wave` of the plan comes now. Its count, 0 when it came already (or there is none).
function MissionEnemies.release(owner: Player, wave: number): number
	local run = runs[owner]
	if not run or run.released[wave] then
		return 0
	end
	run.released[wave] = true
	local count = 0
	for _, group in run.plan.groups do
		if group.wave == wave then
			count += group.count
		end
	end
	return count
end

-- Every wave at once (the cargo is delivered: whatever is left of HOLD OUT comes to be cleared).
function MissionEnemies.releaseAll(owner: Player)
	local run = runs[owner]
	if run then
		for wave = 1, run.plan.waves do
			run.released[wave] = true
		end
	end
end

-- HOLD OUT's waves in the plan (0: none, or no run).
function MissionEnemies.waves(owner: Player): number
	local run = runs[owner]
	return if run then run.plan.waves else 0
end

-- The count for the job payload, nil without a run.
function MissionEnemies.info(owner: Player): Info?
	local run = runs[owner]
	if not run then
		return nil
	end
	local total = run.plan.total
	return { killed = run.killed, total = total, left = math.max(0, total - run.killed), label = run.plan.label }
end

-- The enemies still to kill (0 without a run).
function MissionEnemies.left(owner: Player): number
	local run = runs[owner]
	return if run then math.max(0, run.plan.total - run.killed) else 0
end

-- The nearest one left from `from` (alive: where it is; waiting: where it comes, HOLD OUT's: the drop) and its group's
-- place in words; while no more can come (the cap, the server's room) the alive ones first. nil when none is left.
function MissionEnemies.target(owner: Player, from: Vector3): (Vector3?, string?)
	local run = runs[owner]
	if not run then
		return nil, nil
	end
	local aliveOnly = run.blocked and run.alive > 0
	local best: Vector3? = nil
	local place: string? = nil
	local bestDistance = math.huge
	for _, slot in run.slots do
		if slot.state == "dead" or (aliveOnly and slot.state ~= "alive") then
			continue
		end
		local group = slot.group
		local z = slot.zombie
		local at = if slot.state == "alive" and z and z.root.Parent then z.root.Position
			elseif group.wave then anchorOf(run, group)
			else slot.at or Vector3.new(slot.spot.x, heightOf(run, group), slot.spot.z)
		local d = Vector3.new(at.X - from.X, 0, at.Z - from.Z).Magnitude
		if d < bestDistance then
			best, place, bestDistance = at, group.place, d
		end
	end
	return best, place
end

-- The mission is over: every enemy of it goes (the dead lie where they fell), and the bandit cars.
function MissionEnemies.finish(owner: Player)
	local run = runs[owner]
	if not run then
		return
	end
	runs[owner] = nil
	reserve()
	for _, slot in run.slots do
		local z = slot.zombie
		if z and not z.dead then
			Zombies.despawn(z)
		end
		slot.zombie = nil
	end
	for _, model in run.barricades do
		model:Destroy()
	end
end

-- The admin's KILL MISSION ZOMBIES: every one left dies at once (no reward; the waiting ones too). How many.
function MissionEnemies.killAll(owner: Player): number
	local run = runs[owner]
	if not run then
		return 0
	end
	local count = 0
	for _, slot in run.slots do
		if slot.state == "dead" then
			continue
		end
		local z = slot.zombie
		if z and not z.dead then
			Zombies.damage(z, math.huge, nil, { cause = "other" })
		end
		if slot.state == "alive" then
			run.alive -= 1
		end
		slot.zombie = nil
		slot.state = "dead"
		run.killed += 1
		count += 1
	end
	return count
end

return MissionEnemies
