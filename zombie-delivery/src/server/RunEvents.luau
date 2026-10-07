--!strict
-- 5.7, life on a run on foot or by bike (Config.Jobs.FootEvents; the picks and the words in shared/FootEvents.luau).
-- server/Jobs.luau calls it for its foot and bike jobs (never the tutorial's delivery or a mission):
--
--   RunEvents.begin(player, mode, tutorial, mission)   a run starts: its event picked (about one run in four)
--   RunEvents.step(player, position, stop, index, step)   every Jobs tick (0.2 s): the seconds out of the safe zone,
--                                          the event once they reach its time, the event going on, and the walkers
--                                          rolled once at every drop you come near (`stop`: the current stop)
--   RunEvents.finish(player)               the run is over (or the player left): the survivor and the gate go
--
-- The events: a runner zombie comes after you (Zombies.spawn, owned by you); a survivor calls for help by the sidewalk
-- ahead (an R15 person from server/Npcs.luau): walk up to them and they tip you (PlayerData.addMoney); a locked gate
-- (a small anchored model: two posts, a chain-link panel, a padlock and a sign) stands across the sidewalk ahead, on
-- your side of the road: go round by the road, it goes after GateTime s. "Ahead" is toward the stop you head for.
-- No spot for it now (the safe zone, too close to the stop): tried again after Retry s, Tries times.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local FootEvents = require(Shared.FootEvents)
local Zombies = require(script.Parent.Zombies)
local Npcs = require(script.Parent.Npcs)
local PlayerData = require(script.Parent.PlayerData)

local RunEvents = {}

type StopLike = { kind: string, park: Vector3, pile: Vector3 }

type Run = {
	kind: string?, -- the event still to come (FootEvents.Kinds), nil: none (or done)
	at: number, -- seconds out of the safe zone before it comes
	out: number, -- seconds out of the safe zone so far
	tries: number,
	retryAt: number, -- (out) the next try after a miss
	state: string?, -- "waving" (a survivor waits), "gate" (a gate stands)
	untilAt: number, -- os.clock(): the survivor gives up / the gate goes
	spot: Vector3?, -- the survivor's feet
	name: string,
	tip: number,
	npc: Model?,
	gate: Model?,
	rolled: { [number]: boolean }, -- the drops whose walkers were rolled
}

local runs: { [Player]: Run } = {}
local rng = Random.new()
local notice: RemoteEvent? = nil
local ALIVE_MAX = 6 -- no new walkers at a drop while this many of yours are about

local function tell(player: Player, text: string)
	if text == "" then
		return
	end
	local remote = notice or Net.get("Notice")
	notice = remote
	remote:FireClient(player, text)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

-- The ground under (x, z): the first solid floor looking down from 10 studs over the sidewalk.
local function ground(x: number, z: number): Vector3
	local skip: { Instance } = {}
	for _, name in { "Cars", "Zombies", "Npcs", "Cargo", "Effects" } do
		local child = workspace:FindFirstChild(name)
		if child then
			table.insert(skip, child)
		end
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(skip, other.Character)
		end
	end
	groundParams.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(Vector3.new(x, Map.WalkTop + 10, z), Vector3.new(0, -16, 0), groundParams)
	return Vector3.new(x, if hit and hit.Normal.Y > 0.6 then hit.Position.Y else Map.WalkTop, z)
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function clearUp(run: Run)
	local npc = run.npc
	run.npc = nil
	if npc then
		task.delay(3, function()
			Npcs.remove(npc)
		end)
	end
	local gate = run.gate
	run.gate = nil
	if gate then
		gate:Destroy()
	end
	run.state = nil
end

-- ── The events ─────────────────────────────────────────────────────────────

local function runner(player: Player, position: Vector3): boolean
	local band = Config.Jobs.FootEvents.RunnerDistance
	local spot = Zombies.findSpot(position, nil, band[1], band[2])
	if not spot or Map.isSafe(spot.X, spot.Z) or not Zombies.spawn("runner", spot, player, false) then
		return false
	end
	tell(player, FootEvents.notice("runner"))
	return true
end

-- A point `ahead` studs from `position` toward the stop, or nil when the stop is nearly there.
local function aheadOf(position: Vector3, stop: StopLike, ahead: number): Vector3?
	local to = Vector3.new(stop.park.X - position.X, 0, stop.park.Z - position.Z)
	if to.Magnitude < ahead + 25 then
		return nil
	end
	return position + to.Unit * ahead
end

local function survivor(player: Player, run: Run, position: Vector3, stop: StopLike): boolean
	local tuning = Config.Jobs.FootEvents
	local ahead = aheadOf(position, stop, tuning.SurvivorAhead)
	if not ahead then
		return false
	end
	local x, z, dx, dz, width = Map.nearestRoad(ahead.X, ahead.Z)
	local gx, gz, _, _, sx, sz = FootEvents.gate(x, z, dx, dz, width, position.X, position.Z)
	-- (on the sidewalk, a step in from the kerb: the gate's middle is GateWidth / 2 in, the survivor 3 in)
	local edge = Vector3.new(gx - sx * (tuning.GateWidth / 2 - 3), 0, gz - sz * (tuning.GateWidth / 2 - 3))
	if Map.isSafe(edge.X, edge.Z) or flat(edge, stop.pile) < 25 then
		return false
	end
	local spot = ground(edge.X, edge.Z)
	local names = tuning.SurvivorNames
	run.name = names[rng:NextInteger(1, #names)]
	run.tip = FootEvents.tip(rng:NextNumber())
	run.spot = spot
	run.state = "waving"
	run.untilAt = os.clock() + tuning.SurvivorWait
	local facing = Vector3.new(-sx, 0, -sz) -- (toward the road)
	task.spawn(function()
		local ok, npc = pcall(Npcs.spawn, Npcs.look("townsperson", run.name, "Needs help"), CFrame.lookAt(spot, spot + facing))
		if not ok or not npc then
			return
		end
		if runs[player] ~= run or run.state ~= "waving" then
			Npcs.remove(npc)
			return
		end
		run.npc = npc
		Npcs.say(npc, FootEvents.say("survivor"))
		Npcs.gesture(npc)
	end)
	tell(player, FootEvents.notice("survivor", run.name, run.tip))
	return true
end

-- The locked gate: posts at both ends, a chain-link panel between, a padlock and a LOCKED sign.
local function buildGate(cx: number, cz: number, ax: number, az: number, sx: number, sz: number): Model
	local tuning = Config.Jobs.FootEvents
	local base = ground(cx, cz)
	local model = Instance.new("Model")
	model.Name = "LockedGate"
	-- (the gate's face looks along the kerb, ax / az: its X axis runs across the sidewalk, sx / sz)
	local frame = CFrame.lookAt(base, base + Vector3.new(ax, 0, az))
	if frame.RightVector:Dot(Vector3.new(sx, 0, sz)) < 0 then
		frame = CFrame.lookAt(base, base - Vector3.new(ax, 0, az))
	end
	local function part(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material, transparency: number?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = frame * CFrame.new(offset)
		p.Anchored = true
		p.CanCollide = true
		p.CanTouch = false
		p.Color = color
		p.Material = material
		p.Transparency = transparency or 0
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local width, height = tuning.GateWidth, 7
	local steel = Color3.fromRGB(96, 100, 104)
	for _, side in { -1, 1 } do
		part("Post", Vector3.new(0.5, height + 0.5, 0.5), Vector3.new(side * width / 2, (height + 0.5) / 2, 0), steel, Enum.Material.Metal)
	end
	part("TopRail", Vector3.new(width, 0.25, 0.25), Vector3.new(0, height, 0), steel, Enum.Material.Metal)
	part("BottomRail", Vector3.new(width, 0.25, 0.25), Vector3.new(0, 0.4, 0), steel, Enum.Material.Metal)
	part("Mesh", Vector3.new(width - 0.5, height - 0.6, 0.08), Vector3.new(0, height / 2 + 0.1, 0), Color3.fromRGB(150, 156, 160), Enum.Material.DiamondPlate, 0.35)
	part("Chain", Vector3.new(0.6, 1.4, 0.3), Vector3.new(0, height * 0.55, 0.12), Color3.fromRGB(70, 70, 72), Enum.Material.Metal)
	part("Padlock", Vector3.new(0.5, 0.6, 0.35), Vector3.new(0, height * 0.55 - 0.9, 0.2), Color3.fromRGB(196, 160, 60), Enum.Material.Metal)
	local sign = part("Sign", Vector3.new(3.2, 1.3, 0.12), Vector3.new(0, height * 0.75, 0.14), Color3.fromRGB(214, 72, 64), Enum.Material.SmoothPlastic)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "LOCKED · KEEP OUT"
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = gui
		gui.Parent = sign
	end
	local folder = workspace:FindFirstChild("Effects")
	model.Parent = folder or workspace
	return model
end

local function gate(player: Player, run: Run, position: Vector3, stop: StopLike): boolean
	local tuning = Config.Jobs.FootEvents
	local ahead = aheadOf(position, stop, tuning.GateAhead)
	if not ahead then
		return false
	end
	local x, z, dx, dz, width = Map.nearestRoad(ahead.X, ahead.Z)
	if width > Map.RoadWidth + 1 then
		return false -- (a highway's edge has no sidewalk to block)
	end
	local cx, cz, ax, az, sx, sz = FootEvents.gate(x, z, dx, dz, width, position.X, position.Z)
	local middle = Vector3.new(cx, 0, cz)
	if Map.isSafe(cx, cz) or flat(middle, stop.pile) < 25 or flat(middle, stop.park) < 25 or flat(middle, position) < 10 then
		return false
	end
	run.gate = buildGate(cx, cz, ax, az, sx, sz)
	run.state = "gate"
	run.untilAt = os.clock() + tuning.GateTime
	tell(player, FootEvents.notice("gate"))
	return true
end

-- A survivor waits for you; a gate stands its time.
local function ongoing(player: Player, run: Run, position: Vector3)
	local tuning = Config.Jobs.FootEvents
	local now = os.clock()
	if run.state == "gate" then
		if now > run.untilAt then
			clearUp(run)
		end
		return
	end
	local spot = run.spot
	if run.state ~= "waving" or not spot then
		return
	end
	local gap = flat(position, spot)
	if gap <= tuning.SurvivorReach then
		PlayerData.addMoney(player, run.tip)
		tell(player, `{run.name}: "Thank you, courier!" +${run.tip} tip`)
		local npc = run.npc
		if npc then
			Npcs.say(npc, "Thank you! Stay safe out there!")
		end
		clearUp(run)
	elseif now > run.untilAt or gap > tuning.SurvivorAhead * 3 then
		if now > run.untilAt then
			tell(player, `{run.name} gave up waiting.`)
		end
		clearUp(run)
	end
end

-- About one drop in five: a few walkers wait by it (rolled once, as you come near).
local function dropGroup(player: Player, run: Run, position: Vector3, stop: StopLike, index: number)
	local tuning = Config.Jobs.FootEvents
	if stop.kind ~= "drop" or run.rolled[index] or flat(position, stop.pile) > tuning.GroupNear then
		return
	end
	run.rolled[index] = true
	local count = FootEvents.group(rng:NextNumber(), rng:NextNumber())
	if count <= 0 or Map.isSafe(stop.pile.X, stop.pile.Z) or Zombies.countFor(player) >= ALIVE_MAX then
		return
	end
	local band = tuning.GroupDistance
	local made = 0
	for _ = 1, count do
		local spot = Zombies.findSpot(stop.pile, nil, band[1], band[2])
		if spot and not Map.isSafe(spot.X, spot.Z) and Zombies.spawn("walker", spot, player, false) then
			made += 1
		end
	end
	if made > 0 then
		tell(player, `🧟 {made} walkers are hanging round your drop. Watch yourself.`)
	end
end

-- ── The API ────────────────────────────────────────────────────────────────

function RunEvents.begin(player: Player, mode: string, tutorial: boolean?, mission: string?)
	RunEvents.finish(player)
	if not FootEvents.applies(mode, tutorial, mission) then
		return
	end
	runs[player] = {
		kind = FootEvents.pick(rng:NextNumber(), rng:NextNumber()),
		at = FootEvents.after(rng:NextNumber()),
		out = 0,
		tries = 0,
		retryAt = 0,
		state = nil,
		untilAt = 0,
		spot = nil,
		name = "",
		tip = 0,
		npc = nil,
		gate = nil,
		rolled = {},
	}
end

function RunEvents.step(player: Player, position: Vector3, stop: StopLike?, index: number, step: number)
	local run = runs[player]
	if not run or not player.Parent then
		return
	end
	if run.state then
		ongoing(player, run, position)
	end
	if not stop then
		return
	end
	dropGroup(player, run, position, stop, index)
	local kind = run.kind
	if not kind or run.state or Map.isSafe(position.X, position.Z) then
		return
	end
	run.out += step
	if run.out < math.max(run.at, run.retryAt) then
		return
	end
	local started = if kind == "runner" then runner(player, position)
		elseif kind == "survivor" then survivor(player, run, position, stop)
		else gate(player, run, position, stop)
	if started then
		run.kind = nil
		return
	end
	local tuning = Config.Jobs.FootEvents
	run.tries += 1
	run.retryAt = run.out + tuning.Retry
	if run.tries >= tuning.Tries then
		run.kind = nil
	end
end

function RunEvents.finish(player: Player)
	local run = runs[player]
	if run then
		runs[player] = nil
		clearUp(run)
	end
end

return RunEvents
