--!strict
-- 6.15, a mission's fixed enemies in the world (the owner: "I want them to be about a number of zombies, and you have to
-- complete it, so the mission is always the same"). shared/MissionPlan.luau plans them (the same groups at the same
-- spots every time); server/Jobs.luau runs the mission and calls this every tick; server/Zombies.luau does the bodies.
--
--   MissionEnemies.begin(owner, plan, ground)  a mission started: every enemy of its plan waits at its spot (`ground`:
--                                              the stops' ground height, by stop index)
--   MissionEnemies.step(owner, crew, scale)    every tick (0.2 s): the dead are counted; a group comes when somebody of
--                                              the job is within Fixed.SpawnRange of its spot (the nearest groups
--                                              first, MaxAlive of the mission alive at most, Batch a tick): true when
--                                              the count changed
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
-- member's kill, a car running it over, a blast, the depot burning it. One that only went away (nobody within
-- Config.Horde.DespawnDistance of it, drowned) waits at its spot again and comes back with the crew. The count shown is
-- always the plan's whole total: the ones still waiting count as left.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MissionPlan = require(Shared.MissionPlan)
local World = require(script.Parent.World)
local Zombies = require(script.Parent.Zombies)

local Fixed = Config.Missions.Fixed

local MissionEnemies = {}

type Slot = {
	group: MissionPlan.Group,
	spot: MissionPlan.Spot,
	state: string, -- "waiting" (at its spot, not in the world) | "alive" | "dead"
	zombie: Zombies.Zombie?,
}

type Run = {
	owner: Player,
	tag: string, -- the MissionRun attribute of its enemies
	plan: MissionPlan.Plan,
	slots: { Slot },
	byGroup: { [number]: { Slot } },
	killed: number,
	alive: number,
	released: { [number]: boolean }, -- HOLD OUT's waves let loose
	barricades: { [number]: Model }, -- HUNTED's bandit cars, by route point
	ground: { [number]: number }, -- the stops' ground height, by stop index
}

local runs: { [Player]: Run } = {}
local started = 0

export type Info = { killed: number, total: number, left: number, label: string }

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
		byGroup = {},
		killed = 0,
		alive = 0,
		released = {},
		barricades = {},
		ground = ground,
	}
	for _, group in plan.groups do
		local list: { Slot } = {}
		for _, spot in group.spots do
			local slot: Slot = { group = group, spot = spot, state = "waiting", zombie = nil }
			table.insert(run.slots, slot)
			table.insert(list, slot)
		end
		run.byGroup[group.id] = list
	end
	runs[owner] = run
end

local function heightOf(run: Run, group: MissionPlan.Group): number
	return if group.road then World.RoadTop else run.ground[group.stop] or World.RoadTop
end

-- How far from its spot it goes after anybody: a zombie Fixed.Leash, a bandit or a gunner its range + 40.
local function leashOf(kind: string): number
	local def = Config.Zombies[kind]
	if def and def.ranged then
		return (def.range or 0) + 40
	end
	return Fixed.Leash
end

-- One of them into the world at its spot (HUNTED: its bandit car first). False when the server is full (later).
local function spawnSlot(run: Run, slot: Slot, scale: number): boolean
	local group = slot.group
	local block = group.roadblock
	local point = group.point
	if block and point and not run.barricades[point] then
		run.barricades[point] = (Zombies.barricade(Vector3.new(block.x, World.RoadTop, block.z), Vector3.new(block.ax, 0, block.az), block.lane))
	end
	local z = Zombies.spawn(group.kind, Vector3.new(slot.spot.x, heightOf(run, group), slot.spot.z), run.owner, true)
	if not z then
		return false
	end
	z.leash = leashOf(group.kind)
	z.mission = run.tag
	z.model:SetAttribute("MissionRun", run.tag)
	if group.wave then
		-- HOLD OUT's wave: its spot is the drop (it makes for it) and it goes for whoever holds it from the start.
		z.home = Vector3.new(group.x, run.ground[group.stop] or World.RoadTop, group.z)
		z.alertAt = os.clock()
	end
	if scale > 1 then
		local health = z.humanoid.MaxHealth * scale
		z.humanoid.MaxHealth = health
		z.humanoid.Health = health
	end
	slot.zombie = z
	slot.state = "alive"
	run.alive += 1
	return true
end

-- Where the owner and the crew are (their characters: a seated one rides along with the car).
local function positions(owner: Player, crew: { Player }): { Vector3 }
	local out: { Vector3 } = {}
	local function add(player: Player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(out, root.Position)
		end
	end
	add(owner)
	for _, member in crew do
		if member ~= owner then
			add(member)
		end
	end
	return out
end

-- Every tick of the mission (server/Jobs.luau updatePlayer): the dead counted, the groups near the crew brought in.
-- `crew`: the job's members and riders; `scale`: their health × this (co-op). True when the count changed.
function MissionEnemies.step(owner: Player, crew: { Player }, scale: number): boolean
	local run = runs[owner]
	if not run then
		return false
	end
	local changed = false
	for _, slot in run.slots do
		local z = slot.zombie
		if slot.state == "alive" and z and z.dead then
			slot.zombie = nil
			run.alive -= 1
			if z.killed then
				slot.state = "dead"
				run.killed += 1
				changed = true
			else
				slot.state = "waiting" -- (it only went away: back at its spot, it comes again with the crew)
			end
		end
	end
	local room = math.min(Fixed.Batch, Fixed.MaxAlive - run.alive)
	if room <= 0 or run.killed >= run.plan.total then
		return changed
	end
	local people = positions(owner, crew)
	local near: { { group: MissionPlan.Group, distance: number } } = {}
	for _, group in run.plan.groups do
		local closest = math.huge
		for _, at in people do
			closest = math.min(closest, Vector3.new(at.X - group.x, 0, at.Z - group.z).Magnitude)
		end
		local wave = group.wave
		if (wave and run.released[wave]) or (not wave and closest <= Fixed.SpawnRange) then
			table.insert(near, { group = group, distance = closest })
		end
	end
	table.sort(near, function(a, b)
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		return a.group.id < b.group.id
	end)
	for _, entry in near do
		for _, slot in run.byGroup[entry.group.id] do
			if room <= 0 then
				return changed
			end
			if slot.state == "waiting" then
				if not spawnSlot(run, slot, scale) then
					return changed -- (the server's cap: the next tick)
				end
				room -= 1
			end
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

-- The nearest one left from `from` (alive: where it is; waiting: its spot, HOLD OUT's: the drop) and its group's
-- place in words. nil when none is left.
function MissionEnemies.target(owner: Player, from: Vector3): (Vector3?, string?)
	local run = runs[owner]
	if not run then
		return nil, nil
	end
	local best: Vector3? = nil
	local place: string? = nil
	local bestDistance = math.huge
	for _, slot in run.slots do
		if slot.state == "dead" then
			continue
		end
		local group = slot.group
		local z = slot.zombie
		local at = if slot.state == "alive" and z and z.root.Parent then z.root.Position
			elseif group.wave then Vector3.new(group.x, run.ground[group.stop] or World.RoadTop, group.z)
			else Vector3.new(slot.spot.x, heightOf(run, group), slot.spot.z)
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
