--!strict
-- 6.15, LIVE EVENTS on the server (the owner: "events where working is better for earning, e.g. a Blood Moon"; the
-- rules and the words: shared/LiveEvents.luau, the numbers: Config.LiveEvents). One at a time for the whole server:
--   * The schedule: the first one First minutes after a player came, then one every Every minutes from start to start:
--     the next event of a shuffled deck whose moment it is (the Blood Moon at night, rush hour by day: canStart); none
--     can start: looked at again every Retry s, the deck shuffled anew after MaxWait s. Never in an empty server: an
--     event ends when the last player leaves, and the clock starts over with the next one who comes.
--   * The state for every client: workspace attributes (shared/LiveEvents.luau Attr: the id, when it started and ends in
--     server time, its phase, the crate's or the gate's spot, the drop-off, the carrier, the horde's progress) and a
--     toast for everybody (the Notice remote) when it starts and ends. client/EventBanner.luau plays the sting and
--     shows the banner, client/Weather.luau the Blood Moon's red sky and fog, client/MapView.luau the spot on the maps.
--   * BLOOD MOON: Zombies.roamBoost and Zombies.setFrenzy (every zombie faster but a mission's and the people), the job
--     waves (Jobs.dangerOf asks LiveEvents.waves), the pay (Jobs' payOrder asks LiveEvents.pay); it ends at dawn at the
--     latest.
--   * RUSH HOUR: the pay, and the job board: more offers (Jobs asks LiveEvents.extraOffers), sooner new ones
--     (LiveEvents.refresh), every board made anew when it starts (Jobs.renewBoards); it ends at dusk at the latest.
--   * SUPPLY DROP: a crate on a parachute (native parts, falling slowly on the server's physics), a light beam over its
--     spot and a billboard (a Persistent model: every client has it, near or far), the drop-off pad at the depot; its
--     guards gather (Zombies.march: they hang round the crate, follow it when it is carried, never into the safe zone).
--     Anybody on foot with free hands picks it up (the prompt, checked here: alive, not seated, close, nothing in the
--     hands; a gun in the hand is holstered) and carries it in front of the chest (the character's Carrying attributes
--     as server/Cargo.luau's pieces: no gun, no car, no zip line, the carry's walk); G or the touch PUT DOWN (the PutDown
--     remote) sets it down, the carrier's death, a seat or leaving drops it. The first to come within DeliverRadius of
--     the drop-off with it (checked here every Tick) gets Money and Xp ("SupplyDrop"). Nobody: it is gone at its end.
--   * HORDE AT THE GATES: Count zombies in Bursts from one side, Out studs past the safe zone's edge on its streets,
--     walking to its gates (Zombies.march; Config.LiveEvents.Headroom keeps room for the other players' waves); the kills
--     are counted (Zombies.onKill wrapped); beaten when all came and fell; at its end every killer's share of the reward
--     ("HordeReward", shared/LiveEvents.luau hordeShares) and the rest let go (they roam on).
--   * The daily task (server/Tasks.luau "liveevent": once an event for each player who took part: a job paid with its
--     bonus, the crate brought in, a share of the horde), analytics through PlayerData.track (EventStarted,
--     SupplyDelivered, HordeBeaten; the game never needs it).
--   * 6.15 review: the event's own zombie budget (shared/LiveEvents.luau budget: up to MaxTotal − Headroom, calm
--     roamers far from everybody make room, Zombies.eventReserve holds the roamers back while it still wants some);
--     its zombies leave players on a mission alone (Zombies.eventSpared) and their kills add nothing to a mission's
--     kill bonus; at its end its zombies nobody is near go at once and the rest fall back and go (Linger); the horde
--     is beaten at Beaten of it; the crate lands on the floor (never in a roof or on a car), drops by itself from an
--     idle or stalling carrier and goes back down where it was after a step faster than a walk; `finish` clears the
--     state first and survives an error in an event's end.
--
--   LiveEvents.current()                  the running event's id (nil: none)
--   LiveEvents.pay(player, mission)       a job paid now pays × this (server/Jobs.luau payOrder; the task noted)
--   LiveEvents.waves(mission)             the job waves' multiplier (Jobs.dangerOf)
--   LiveEvents.extraOffers(), refresh(s)  rush hour's board (Jobs' tierOffers, makeBoard)
--   LiveEvents.finish(why)                ends the running event ("time", "dawn", "dusk", "admin", "delivered",
--                                         "beaten", "nobody"): its world goes, its zombies roam on, the horde's shares, the
--                                         toast
--   LiveEvents.adminStart(id)             "bloodmoon" | "rush" | "supply" | "horde" | "end": the admin panel's EVENTS
--                                         (server/Admin.luau); returns the answer for the admin
--   LiveEvents.start()                    the schedule (server/Main.server.luau); it fills Jobs.live with pay, waves,
--                                         extraOffers, refresh and current (server/Jobs.luau cannot require this module:
--                                         this one requires Jobs)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local Rules = require(Shared.LiveEvents)
local DayNight = require(script.Parent.DayNight)
local Jobs = require(script.Parent.Jobs)
local PlayerData = require(script.Parent.PlayerData)
local World = require(script.Parent.World)
local Zombies = require(script.Parent.Zombies)

local LiveEvents = {}

local T = Config.LiveEvents
local A = Rules.Attr
local notice = Net.get("Notice")
local rng = Random.new()

local CRATE = Vector3.new(2.4, 1.7, 1.9) -- the crate (carried in both arms: about a stud and a half deep)
local CANOPY_UP = 8.5 -- the canopy's middle over the crate's
local BEAM_HEIGHT = 320
local CARRY_ATTRIBUTES = { "Carrying", "CarryCount", "CarryHands", "CarryAt", "CarrySize" }

type Running = {
	id: string,
	startedAt: number, -- os.clock()
	endsAt: number, -- os.clock()
	took: { [Player]: boolean }, -- who took part (the daily task: once an event)
}

type Supply = {
	model: Model, -- the crate, its parachute, its beam (Persistent)
	pad: Model, -- the drop-off at the depot (Persistent)
	root: Part, -- the crate (every other part of it welded to it)
	beam: Part,
	fall: { Instance }, -- the parachute and the forces (gone at the landing)
	drift: LinearVelocity,
	yaw: number,
	landY: number,
	landed: boolean,
	fallUntil: number,
	landedAt: number,
	pick: ProximityPrompt?,
	down: ProximityPrompt?,
	carrier: Player?,
	weld: WeldConstraint?,
	hooks: { RBXScriptConnection },
	guards: { Zombies.Zombie },
	nextGuards: number,
	shown: Vector3?, -- the Spot attribute as it was sent
	-- 6.15 review, the carry: its carrier's last checked spot and when (the pace), where they last stood on a floor
	-- (the crate's way back down), since when they stand still and where, their best gap to the drop-off and when
	lastAt: Vector3?,
	lastAtTime: number,
	lastGround: Vector3?,
	stillAt: Vector3?,
	stillSince: number,
	bestGap: number,
	bestAt: number,
}

type Horde = {
	side: string,
	gates: { Rules.Gate },
	bursts: { number },
	burst: number, -- bursts released so far
	due: number, -- zombies released so far
	nextBurst: number,
	spawned: number,
	total: number,
	list: { Zombies.Zombie },
	kills: { [Player]: number },
	done: number,
	goal: number, -- 6.15 review: the kills that beat it (Rules.hordeGoal)
}

local running: Running? = nil
local supply: Supply? = nil
local horde: Horde? = nil
local deck: { string } = {}
local last: string? = nil
local nextAt: number? = nil -- os.clock() of the next event (nil: nobody came yet)
local retryAt = 0
local fading: { { z: Zombies.Zombie, ends: number } } = {} -- 6.15 review: an ended event's zombies falling back
local waitingSince: number? = nil

-- ── Small helpers ──────────────────────────────────────────────────────────

local function set(name: string, value: any)
	if workspace:GetAttribute(name) ~= value then
		workspace:SetAttribute(name, value)
	end
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1] or 220, c[2] or 220, c[3] or 220)
end

local function part(parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = frame
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function weld(to: BasePart, item: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = item
	w.Parent = item
end

-- Once an event, each player who took part: the daily task "liveevent".
local function tookPart(run: Running?, player: Player)
	if not run or run.took[player] or not player.Parent then
		return
	end
	run.took[player] = true
	pcall(function()
		require(script.Parent.Tasks).note(player, "liveevent", 1)
	end)
end

local function playersCount(): number
	return #Players:GetPlayers()
end

-- 6.15 review: the floor under a point, at most `depth` studs down: a ray past the cars (yours, the traffic, the
-- bandits'), the people, the zombies, the animals, the loot and the crate itself. Nil when there is none that close.
local SKIP_FOLDERS = { "Cars", "Traffic", "BanditCars", "Npcs", "Zombies", "Animals", "Loot" }
local function floorBelow(at: Vector3, depth: number, skip: { Instance }): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = table.clone(skip)
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for _, name in SKIP_FOLDERS do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	params.FilterDescendantsInstances = list
	params.IgnoreWater = false
	local hit = workspace:Raycast(at + Vector3.new(0, 1, 0), Vector3.new(0, -(depth + 1), 0), params)
	return if hit then hit.Position.Y else nil
end

-- 6.15 review: how many of the event's `due` zombies may come now (its own budget: shared/LiveEvents.luau budget);
-- calm roamers far from everybody make room for the ones that do not fit.
local function allowance(due: number): number
	local count, short = Rules.budget(#Zombies.all(), due)
	if short > 0 then
		count += Zombies.trimRoamers(short)
	end
	return count
end

-- Is somebody (anywhere, the safe zone too) within `reach` studs of the point?
local function anybodyNear(at: Vector3, reach: number): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local body = character and character:FindFirstChild("HumanoidRootPart")
		if body and body:IsA("BasePart") and (body.Position - at).Magnitude < reach then
			return true
		end
	end
	return false
end

-- 6.15 review: an ended event's zombies: the ones nobody is within Vanish of go at once; the others fall back (away
-- from the safe zone, after nobody) and go once nobody is that close, Linger s at most (fadeStep).
local function letGo(list: { Zombies.Zombie })
	local now = os.clock()
	for _, z in list do
		if z.dead then
			continue
		end
		local at = z.root.Position
		if not anybodyNear(at, T.Vanish) then
			Zombies.despawn(z)
			continue
		end
		local flat = Vector3.new(at.X, 0, at.Z)
		local away = if flat.Magnitude > 1 then flat.Unit else Vector3.new(1, 0, 0)
		Zombies.retreat(z, Vector3.new(at.X, World.RoadTop, at.Z) + away * 220)
		table.insert(fading, { z = z, ends = now + T.Linger })
	end
end

local function fadeStep(now: number)
	for index = #fading, 1, -1 do
		local entry = fading[index]
		local z = entry.z
		if z.dead then
			table.remove(fading, index)
		elseif now >= entry.ends or not anybodyNear(z.root.Position, T.Vanish) then
			Zombies.despawn(z)
			table.remove(fading, index)
		end
	end
end

-- 6.15 review: what the running event still wants to place (the roamers stop that much lower under the cap), and the
-- players its zombies leave alone (on a mission), every step.
local function shareRoom()
	local want = 0
	local h = horde
	if h then
		want += math.max(0, h.total - h.spawned)
	end
	local sup = supply
	if sup then
		want += if sup.landed then math.max(0, T.Supply.Guards.Max - #sup.guards) else T.Supply.Guards.First
	end
	Zombies.eventReserve = want
	table.clear(Zombies.eventSpared)
	if h or sup then
		for _, player in Players:GetPlayers() do
			if Jobs.onMission(player) then
				Zombies.eventSpared[player] = true
			end
		end
	end
end

-- ── The Blood Moon ─────────────────────────────────────────────────────────

-- A mission's zombies keep their own speed (missions are never touched).
local function spared(z: Zombies.Zombie): boolean
	local owner = z.owner
	return owner ~= nil and owner.Parent ~= nil and Jobs.onMission(owner)
end

local function startBloodMoon()
	Zombies.roamBoost = Rules.roamOf("bloodmoon")
	Zombies.setFrenzy(function(speed: number): number
		return Rules.speedOf("bloodmoon", speed)
	end, spared)
end

local function stopBloodMoon()
	Zombies.roamBoost = 1
	Zombies.setFrenzy(nil, nil)
end

-- ── The supply drop: the crate ─────────────────────────────────────────────

-- The crate (olive planks, two straps, a white cross a side, a beacon on the lid), its parachute (a red and white
-- canopy, its skirt, four lines) and the forces that let it down slowly, the beam over its spot and its billboard.
local function buildCrate(x: number, z: number, landY: number, yaw: number, color: Color3): (Model, Part, Part, { Instance }, LinearVelocity)
	local model = Instance.new("Model")
	model.Name = "SupplyDrop"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local top = CFrame.new(x, landY + T.Supply.FallFrom, z) * CFrame.Angles(0, yaw, 0)
	local root = part(model, "Crate", CRATE, top, Color3.fromRGB(92, 98, 62), Enum.Material.WoodPlanks)
	root.Massless = false
	root.CastShadow = true
	root.CanQuery = true
	model.PrimaryPart = root
	local function onCrate(name: string, size: Vector3, offset: CFrame, c: Color3, material: Enum.Material): Part
		local p = part(model, name, size, top * offset, c, material)
		weld(root, p)
		return p
	end
	for _, side in { -1, 1 } do
		onCrate("Strap", Vector3.new(CRATE.X + 0.08, CRATE.Y + 0.08, 0.22), CFrame.new(0, 0, side * CRATE.Z * 0.28), Color3.fromRGB(34, 36, 38), Enum.Material.Metal)
		-- the white cross on both ends
		onCrate("Cross", Vector3.new(0.06, 0.9, 0.24), CFrame.new(side * (CRATE.X / 2 + 0.03), 0, 0), Color3.fromRGB(236, 236, 230), Enum.Material.SmoothPlastic)
		onCrate("Cross", Vector3.new(0.06, 0.24, 0.9), CFrame.new(side * (CRATE.X / 2 + 0.03), 0, 0), Color3.fromRGB(236, 236, 230), Enum.Material.SmoothPlastic)
	end
	onCrate("Lid", Vector3.new(CRATE.X - 0.3, 0.1, CRATE.Z - 0.3), CFrame.new(0, CRATE.Y / 2 + 0.05, 0), Color3.fromRGB(112, 118, 76), Enum.Material.WoodPlanks)
	local beacon = onCrate("Beacon", Vector3.new(0.45, 0.3, 0.45), CFrame.new(0, CRATE.Y / 2 + 0.25, 0), color, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 2
	light.Color = color
	light.Shadows = false
	light.Parent = beacon
	-- The parachute: welded to the crate while it falls, gone at the landing.
	local fall: { Instance } = {}
	local red, white = Color3.fromRGB(200, 54, 48), Color3.fromRGB(236, 232, 222)
	local upright = CFrame.Angles(0, 0, math.rad(90)) -- (a cylinder's axis is its X)
	local canopy = onCrate("Canopy", Vector3.new(0.9, 12, 12), CFrame.new(0, CANOPY_UP, 0) * upright, red, Enum.Material.Fabric)
	canopy.Shape = Enum.PartType.Cylinder
	local crown = onCrate("Crown", Vector3.new(1, 7, 7), CFrame.new(0, CANOPY_UP + 0.6, 0) * upright, white, Enum.Material.Fabric)
	crown.Shape = Enum.PartType.Cylinder
	local cap = onCrate("Cap", Vector3.new(0.6, 2.4, 2.4), CFrame.new(0, CANOPY_UP + 1.2, 0) * upright, red, Enum.Material.Fabric)
	cap.Shape = Enum.PartType.Cylinder
	table.insert(fall, canopy)
	table.insert(fall, crown)
	table.insert(fall, cap)
	for k = 0, 7 do
		local panel = onCrate("Skirt", Vector3.new(4.8, 0.15, 1.6), CFrame.new(0, CANOPY_UP - 0.5, 0) * CFrame.Angles(0, k * math.pi / 4, 0) * CFrame.new(0, 0, -6.2) * CFrame.Angles(math.rad(-35), 0, 0), if k % 2 == 0 then white else red, Enum.Material.Fabric)
		table.insert(fall, panel)
	end
	for _, corner in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		local a = Vector3.new(corner[1] * 4.4, CANOPY_UP - 1.1, corner[2] * 4.4)
		local b = Vector3.new(corner[1] * (CRATE.X / 2 - 0.1), CRATE.Y / 2, corner[2] * (CRATE.Z / 2 - 0.1))
		local length = (a - b).Magnitude
		local line = onCrate("Line", Vector3.new(0.07, 0.07, length), CFrame.lookAt((a + b) / 2, b), white, Enum.Material.SmoothPlastic)
		table.insert(fall, line)
	end
	-- The slow way down: a set velocity (a little drift that sways) and kept upright.
	local attachment = Instance.new("Attachment")
	attachment.Name = "Fall"
	attachment.Parent = root
	local drift = Instance.new("LinearVelocity")
	drift.Attachment0 = attachment
	drift.RelativeTo = Enum.ActuatorRelativeTo.World
	drift.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	drift.VectorVelocity = Vector3.new(0, -T.Supply.FallSpeed, 0)
	drift.MaxForce = math.huge
	drift.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true
	align.CFrame = CFrame.Angles(0, yaw, 0)
	align.Parent = root
	table.insert(fall, attachment)
	table.insert(fall, drift)
	table.insert(fall, align)
	-- The beam over its spot (from the street up: seen from across the town) and the billboard.
	local beam = part(model, "Beam", Vector3.new(BEAM_HEIGHT, 2.2, 2.2), CFrame.new(x, World.RoadTop + BEAM_HEIGHT / 2, z) * upright, color, Enum.Material.Neon)
	beam.Shape = Enum.PartType.Cylinder
	beam.Anchored = true
	beam.Transparency = 0.6
	local board = Instance.new("BillboardGui")
	board.Name = "Label"
	board.Size = UDim2.fromOffset(170, 30)
	board.StudsOffset = Vector3.new(0, 3, 0)
	board.AlwaysOnTop = true
	board.MaxDistance = 4000
	board.LightInfluence = 0
	board.Parent = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 23, 28)
	label.BackgroundTransparency = 0.25
	label.BorderSizePixel = 0
	label.Text = "📦 SUPPLY DROP"
	label.TextColor3 = Color3.fromRGB(242, 242, 240)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = board
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = 1
	stroke.Parent = label
	model.Parent = workspace
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	return model, root, beam, fall, drift
end

-- The drop-off at the depot: a glowing pad and its sign (Persistent, like the depot).
local function buildPad(color: Color3): Model
	local x, z = Rules.dropOff()
	local model = Instance.new("Model")
	model.Name = "SupplyDropOff"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local radius = T.Supply.DeliverRadius
	local pad = part(model, "Pad", Vector3.new(0.12, radius * 2, radius * 2), CFrame.new(x, Map.WalkTop + 0.07, z) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon)
	pad.Shape = Enum.PartType.Cylinder
	pad.Anchored = true
	pad.Transparency = 0.55
	local light = Instance.new("PointLight")
	light.Range = 20
	light.Brightness = 1.5
	light.Color = color
	light.Shadows = false
	light.Parent = pad
	local board = Instance.new("BillboardGui")
	board.Name = "Label"
	board.Size = UDim2.fromOffset(190, 30)
	board.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	board.AlwaysOnTop = true
	board.MaxDistance = 700
	board.LightInfluence = 0
	board.Parent = pad
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 23, 28)
	label.BackgroundTransparency = 0.25
	label.BorderSizePixel = 0
	label.Text = "📦 SUPPLY DROP-OFF"
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = board
	model.Parent = workspace
	return model
end

local function showSpot(s: Supply, at: Vector3)
	local shown = s.shown
	if not shown or (shown - at).Magnitude > 3 then
		s.shown = at
		set(A.Spot, at)
	end
end

local function moveBeam(s: Supply, at: Vector3)
	s.beam.CFrame = CFrame.new(at.X, World.RoadTop + BEAM_HEIGHT / 2, at.Z) * CFrame.Angles(0, 0, math.rad(90))
end

-- ── The supply drop: carrying ──────────────────────────────────────────────

local putDown: (Supply, string, boolean?) -> ()
local deliver: (Supply, Player) -> ()

local function clearHands(character: Model?)
	if character and character:GetAttribute("Carrying") == "crate" then
		for _, name in CARRY_ATTRIBUTES do
			character:SetAttribute(name, nil)
		end
	end
end

-- In the carrier's arms: welded in front of the chest like a cargo piece (server/Cargo.luau stackHeld's numbers).
local function carry(s: Supply, player: Player, character: Model, body: BasePart, humanoid: Humanoid)
	local tune = Config.Cargo
	local offset = Vector3.new(0, tune.CarryLow + CRATE.Y / 2, -(tune.CarryFront + CRATE.Z / 2))
	local crate = s.root
	crate.Anchored = true
	crate.CFrame = body.CFrame * CFrame.new(offset)
	crate.CanCollide = false
	crate.Massless = true
	local w = Instance.new("WeldConstraint")
	w.Part0 = body
	w.Part1 = crate
	w.Parent = crate
	crate.Anchored = false
	s.weld = w
	s.carrier = player
	character:SetAttribute("Carrying", "crate")
	character:SetAttribute("CarryCount", 1)
	character:SetAttribute("CarryHands", 2)
	character:SetAttribute("CarryAt", offset)
	character:SetAttribute("CarrySize", CRATE)
	local pick = s.pick
	if pick then
		pick.Enabled = false
	end
	local down = Instance.new("ProximityPrompt")
	down.ActionText = "Put down"
	down.ObjectText = "Supply crate"
	down.KeyboardKeyCode = Enum.KeyCode.G
	down.GamepadKeyCode = Enum.KeyCode.ButtonB
	down.HoldDuration = 0
	down.MaxActivationDistance = 4 -- (only for the one holding it)
	down.RequiresLineOfSight = false
	-- (6.15 review: tagged like a job's prompt, client/CargoPrompts.luau shows it to its carrier only)
	down:SetAttribute("CargoOwner", player.UserId)
	game:GetService("CollectionService"):AddTag(down, Config.Cargo.PromptTag)
	down.Parent = crate
	s.down = down
	table.insert(s.hooks, down.Triggered:Connect(function(by: Player)
		if by == player and supply == s and s.carrier == player then
			putDown(s, "put")
		end
	end))
	-- It drops when the carrier dies, sits down or leaves (their body goes).
	local function drop()
		if supply == s and s.carrier == player then
			putDown(s, "lost")
		end
	end
	table.insert(s.hooks, humanoid.Died:Connect(drop))
	table.insert(s.hooks, humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		if humanoid.SeatPart ~= nil then
			drop()
		end
	end))
	table.insert(s.hooks, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			drop()
		end
	end))
	set(A.Phase, "carried")
	set(A.Carrier, player.DisplayName)
	-- (6.15 review: the carry's checks start here: the pace, standing still, getting nearer the drop-off)
	local now = os.clock()
	local dx, dz = Rules.dropOff()
	s.lastAt, s.lastAtTime, s.lastGround = body.Position, now, body.Position
	s.stillAt, s.stillSince = body.Position, now
	s.bestGap, s.bestAt = Vector3.new(body.Position.X - dx, 0, body.Position.Z - dz).Magnitude, now
end

-- The crate set down where it is (on the floor under it); `why` "put" (G, PUT DOWN: on the drop-off it counts as
-- brought in), "lost" (a death, a seat, the body gone), "left", "end", 6.15 review "idle", "stall", "pace". `back`:
-- where its carrier last stood on a floor (a step faster than a walk: back there).
putDown = function(s: Supply, why: string, back: boolean?)
	local player = s.carrier
	if not player then
		return
	end
	s.carrier = nil
	for _, hook in s.hooks do
		hook:Disconnect()
	end
	table.clear(s.hooks)
	if s.weld then
		s.weld:Destroy()
		s.weld = nil
	end
	if s.down then
		s.down:Destroy()
		s.down = nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	clearHands(character)
	local crate = s.root
	local at = crate.Position
	-- 6.15 review: on the floor in front of a carrier who stands on one (a step down at most), else where they last
	-- stood (in the air over a roof, off a car, dead, after a step too fast); never buried, never on a car
	local floor: number? = nil
	if not back and humanoid and humanoid.Health > 0 and humanoid.FloorMaterial ~= Enum.Material.Air then
		floor = floorBelow(at, T.Supply.Drop + CRATE.Y, { s.model })
	end
	local stood = s.lastGround
	if not floor and stood then
		at = stood
		floor = floorBelow(stood, 12, { s.model })
	end
	floor = floor or World.RoadTop
	local yaw = select(2, crate.CFrame:ToOrientation())
	crate.Anchored = true
	crate.Massless = false
	crate.CanCollide = true
	crate.CFrame = CFrame.new(at.X, (floor :: number) + CRATE.Y / 2, at.Z) * CFrame.Angles(0, yaw, 0)
	local pick = s.pick
	if pick then
		pick.Enabled = true
	end
	set(A.Phase, "ground")
	set(A.Carrier, nil)
	if why == "put" and running and Rules.delivered(at.X, at.Z) then
		deliver(s, player)
	end
end

local function pickUp(s: Supply, player: Player)
	if supply ~= s or not s.landed or s.carrier ~= nil or not running then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local body = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not body or not body:IsA("BasePart") then
		return
	end
	if humanoid.SeatPart ~= nil or humanoid.Sit then
		notice:FireClient(player, "Get out first: the crate goes in your arms.")
		return
	end
	if character:GetAttribute("Carrying") ~= nil or character:GetAttribute("Pushing") ~= nil then
		notice:FireClient(player, "Your hands are full: put down what you carry first (G).")
		return
	end
	local gap = Vector3.new(body.Position.X - s.root.Position.X, 0, body.Position.Z - s.root.Position.Z)
	if gap.Magnitude > T.Supply.Pickup + 3 then
		return
	end
	pcall(function()
		require(script.Parent.Hand).holster(player, true) -- (no gun in the hand with a crate in your arms)
	end)
	carry(s, player, character, body, humanoid)
	notice:FireClient(player, "📦 You have the supply crate! Bring it to the depot's drop-off (G puts it down).")
end

-- ── The supply drop: its course ────────────────────────────────────────────

-- The guards: a few at the landing, more as time goes, round the crate (on the roads; never in the safe zone).
local function spawnGuards(s: Supply, count: number)
	local center = s.root.Position
	if World.isSafe(center) then
		return
	end
	local g = T.Supply.Guards
	for _ = 1, allowance(count) do -- (6.15 review: the event's own budget)
		local spot = Zombies.findSpot(center, nil, g.Near, g.Far)
		local made = if spot then Zombies.spawn(Economy.pickKind(T.Supply.Kinds, rng:NextNumber()), spot, nil, false, false, false) else nil
		if made then
			Zombies.march(made, center, "supply")
			table.insert(s.guards, made)
		end
	end
end

local function land(s: Supply, now: number)
	s.landed = true
	s.landedAt = now
	for _, item in s.fall do
		item:Destroy()
	end
	table.clear(s.fall)
	local at = s.root.Position
	s.root.Anchored = true
	s.root.CanCollide = true
	s.root.CFrame = CFrame.new(at.X, s.landY, at.Z) * CFrame.Angles(0, s.yaw, 0)
	local pick = Instance.new("ProximityPrompt")
	pick.ActionText = "Pick up"
	pick.ObjectText = "Supply crate"
	pick.KeyboardKeyCode = Enum.KeyCode.E
	pick.HoldDuration = T.Supply.Hold
	pick.MaxActivationDistance = T.Supply.Pickup
	pick.RequiresLineOfSight = false
	pick.Parent = s.root
	pick.Triggered:Connect(function(player: Player)
		pickUp(s, player)
	end)
	s.pick = pick
	set(A.Phase, "ground")
	showSpot(s, s.root.Position)
	spawnGuards(s, T.Supply.Guards.First)
	s.nextGuards = now + T.Supply.Guards.Every
end

local function startSupply(): (boolean, string?)
	local x: number?, z: number? = nil, nil
	for _ = 1, 30 do
		x, z = Rules.supplySpot(rng:NextNumber(), rng:NextNumber(), rng:NextNumber())
		if x and z then
			break
		end
	end
	if not x or not z then
		return false, nil
	end
	local color = rgb(Rules.color("supply"))
	local landY = World.RoadTop + CRATE.Y / 2
	local yaw = rng:NextNumber(0, math.pi * 2)
	local model, root, beam, fall, drift = buildCrate(x, z, landY, yaw, color)
	local now = os.clock()
	supply = {
		model = model,
		pad = buildPad(color),
		root = root,
		beam = beam,
		fall = fall,
		drift = drift,
		yaw = yaw,
		landY = landY,
		landed = false,
		fallUntil = now + T.Supply.FallFrom / math.max(1, T.Supply.FallSpeed) + 8,
		landedAt = now,
		pick = nil,
		down = nil,
		carrier = nil,
		weld = nil,
		hooks = {},
		guards = {},
		nextGuards = math.huge,
		shown = nil,
		lastAt = nil,
		lastAtTime = now,
		lastGround = nil,
		stillAt = nil,
		stillSince = now,
		bestGap = math.huge,
		bestAt = now,
	}
	local dx, dz = Rules.dropOff()
	set(A.Goal, Vector3.new(dx, Map.WalkTop, dz))
	set(A.Spot, Vector3.new(x, landY, z))
	set(A.Phase, "falling")
	local where = if math.abs(x) >= math.abs(z) then (if x > 0 then "in the east" else "in the west") else (if z > 0 then "in the south" else "in the north")
	return true, where
end

deliver = function(s: Supply, player: Player)
	local run = running
	if supply ~= s or not run then
		return
	end
	if s.carrier == player then
		putDown(s, "end")
	end
	local money, xp = Rules.supplyReward(PlayerData.level(player))
	PlayerData.addMoney(player, money, "SupplyDrop")
	PlayerData.addXp(player, xp)
	tookPart(run, player)
	local seconds = math.floor(os.clock() - s.landedAt + 0.5)
	PlayerData.track("event", player, "SupplyDelivered", seconds, PlayerData.level(player)) -- (a no-op without Analytics)
	notice:FireClient(player, `📦 SUPPLY DROP brought in! +{Rules.money(money)} · +{xp} XP`)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			notice:FireClient(other, `📦 {player.DisplayName} brought the supply drop in.`)
		end
	end
	LiveEvents.finish("delivered")
end

local function supplyStep(s: Supply, now: number)
	if not s.landed then
		local at = s.root.Position
		-- (it lands on the step before it would sink under the street: no pop up out of the road)
		if at.Y <= s.landY + T.Supply.FallSpeed * T.Tick or now >= s.fallUntil then
			land(s, now)
			return
		end
		-- (a gentle sway under the canopy)
		s.drift.VectorVelocity = Vector3.new(math.sin(now * 0.7) * 1.4, -T.Supply.FallSpeed, math.cos(now * 0.55) * 1.1)
		showSpot(s, Vector3.new(at.X, s.landY, at.Z))
		return
	end
	local carrier = s.carrier
	if carrier then
		local character = carrier.Character
		local body = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if carrier.Parent ~= Players or not body or not body:IsA("BasePart") then
			putDown(s, "lost")
		else
			local at = body.Position
			local last = s.lastAt or at
			local walk = carrier:GetAttribute("AdminSpeed")
			if not Rules.paceOk(Vector3.new(at.X - last.X, 0, at.Z - last.Z).Magnitude, now - s.lastAtTime, if type(walk) == "number" then walk else 1) then
				-- 6.15 review: a step faster than a walk (a teleport): no carry, the crate goes back where it was (quietly)
				putDown(s, "pace", true)
			elseif Rules.delivered(at.X, at.Z) then
				deliver(s, carrier)
				return
			else
				s.lastAt, s.lastAtTime = at, now
				if humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
					s.lastGround = at
				end
				-- 6.15 review: no hostage: standing still Idle s, or no StallGain studs nearer the drop-off in Stall s
				local still = s.stillAt or at
				if Vector3.new(at.X - still.X, 0, at.Z - still.Z).Magnitude > 4 then
					s.stillAt, s.stillSince = at, now
				end
				local dx, dz = Rules.dropOff()
				local gap = Vector3.new(at.X - dx, 0, at.Z - dz).Magnitude
				if gap < s.bestGap - T.Supply.StallGain then
					s.bestGap, s.bestAt = gap, now
				end
				if now - s.stillSince >= T.Supply.Idle then
					putDown(s, "idle")
					notice:FireClient(carrier, "📦 You stood still too long: the crate is on the ground for anybody.")
				elseif now - s.bestAt >= T.Supply.Stall then
					putDown(s, "stall")
					notice:FireClient(carrier, "📦 The depot is the other way: the crate is on the ground for anybody.")
				end
			end
		end
	end
	local at = s.root.Position
	showSpot(s, at)
	moveBeam(s, at)
	-- The guards follow the crate (never into the safe zone: they wait where they are), more of them now and then.
	for index = #s.guards, 1, -1 do
		local z = s.guards[index]
		if z.dead or z.march == nil then
			table.remove(s.guards, index)
		elseif not World.isSafe(at) then
			z.march = at
		end
	end
	if now >= s.nextGuards then
		s.nextGuards = now + T.Supply.Guards.Every
		spawnGuards(s, math.min(T.Supply.Guards.Batch, T.Supply.Guards.Max - #s.guards))
	end
end

local function stopSupply()
	local s = supply
	if not s then
		return
	end
	supply = nil
	if s.carrier then
		putDown(s, "end")
	end
	s.model:Destroy()
	s.pad:Destroy()
	letGo(s.guards) -- (6.15 review: they go, or fall back and go)
end

-- ── The horde at the gates ─────────────────────────────────────────────────

local function startHorde(): string
	local side = Rules.Sides[rng:NextInteger(1, #Rules.Sides)]
	local gates = Rules.gates(side)
	horde = {
		side = side,
		gates = gates,
		bursts = Rules.bursts(T.Horde.Count, T.Horde.Bursts),
		burst = 0,
		due = 0,
		nextBurst = os.clock() + 4,
		spawned = 0,
		total = T.Horde.Count,
		list = {},
		kills = {},
		done = 0,
		goal = Rules.hordeGoal(T.Horde.Count),
	}
	local x, z = 0, 0
	for _, gate in gates do
		x += gate.x / #gates
		z += gate.z / #gates
	end
	set(A.Side, side)
	set(A.Spot, Vector3.new(x, World.RoadTop, z))
	set(A.Total, Rules.hordeGoal(T.Horde.Count)) -- (6.15 review: the banner counts to the kills that beat it)
	set(A.Done, 0)
	set(A.Phase, "coming")
	return side
end

local function hordeStep(h: Horde, now: number)
	if h.burst < #h.bursts and now >= h.nextBurst then
		h.burst += 1
		h.due += h.bursts[h.burst]
		h.nextBurst = now + T.Horde.BurstEvery
	end
	-- What is due comes, a few a step, in the event's own budget (6.15 review: calm roamers make room; else later).
	local budget = if h.spawned < h.due and #h.gates > 0 then allowance(h.due - h.spawned) else 0
	while h.spawned < h.due and budget > 0 and #h.gates > 0 do
		budget -= 1
		local gate = h.gates[h.spawned % #h.gates + 1]
		local x, z = Rules.hordeSpot(gate, rng:NextNumber(), rng:NextNumber())
		local made = Zombies.spawn(Economy.pickKind(T.Horde.Kinds, rng:NextNumber()), Vector3.new(x, World.RoadTop, z), nil, false, false, false)
		if not made then
			break
		end
		h.spawned += 1
		Zombies.march(made, Vector3.new(gate.x, World.RoadTop, gate.z), "horde")
		table.insert(h.list, made)
	end
	local done = 0
	for _, z in h.list do
		if z.dead then
			done += 1
		end
	end
	if done ~= h.done then
		h.done = done
		set(A.Done, done)
	end
	if h.spawned >= h.total then
		set(A.Phase, "gate")
		if done >= h.goal then
			LiveEvents.finish("beaten") -- (6.15 review: Beaten of it; a straggler never holds it up)
		end
	end
end

-- Its end: every killer's share (beaten: the whole pool; else the share of the horde that fell), the rest let go.
-- Returns true when everybody was told (the toasts are its own).
local function stopHorde(run: Running, why: string): boolean
	local h = horde
	if not h then
		return false
	end
	horde = nil
	letGo(h.list) -- (6.15 review: whoever is left goes, or falls back and goes)
	if why == "nobody" then
		return true
	end
	local beaten = why == "beaten"
	local kills: { [Player]: number } = {}
	for player, n in h.kills do
		if player.Parent == Players then
			kills[player] = n
		end
	end
	local shares = Rules.hordeShares(kills, h.done, h.goal, beaten, function(player: Player): number
		return PlayerData.level(player)
	end)
	local head = if beaten then "🧟 HORDE BEATEN!" else "🧟 The horde falls back."
	for _, player in Players:GetPlayers() do
		local share = shares[player]
		if share then
			PlayerData.addMoney(player, share.money, "HordeReward")
			PlayerData.addXp(player, share.xp)
			tookPart(run, player)
			PlayerData.track("event", player, "HordeBeaten", share.kills, if beaten then "beaten" else "time") -- (a no-op without Analytics)
			notice:FireClient(player, `{head} Your {share.kills} {if share.kills == 1 then "kill" else "kills"}: +{Rules.money(share.money)} · +{share.xp} XP`)
		else
			notice:FireClient(player, `{head} {math.min(h.done, h.goal)} of {h.goal} fell; kill some next time for a share.`)
		end
	end
	return true
end

local function onKill(player: Player, z: Zombies.Zombie)
	local h = horde
	if h and z.event == "horde" then
		h.kills[player] = (h.kills[player] or 0) + 1
	end
end

-- ── Start and end ──────────────────────────────────────────────────────────

-- Starts the event now (nothing else may run). False when it cannot (no street spot for a crate).
local function begin(id: string): boolean
	if running or not Rules.def(id) then
		return false
	end
	local extra: string? = nil
	if id == "supply" then
		local ok, where = startSupply()
		if not ok then
			return false
		end
		extra = where
	elseif id == "horde" then
		extra = startHorde()
	elseif id == "bloodmoon" then
		startBloodMoon()
	elseif id == "rush" then
		Jobs.renewBoards() -- (the boards made anew at the next second, with the extra offers)
	end
	local seconds = Rules.seconds(id)
	local now = os.clock()
	running = { id = id, startedAt = now, endsAt = now + seconds, took = {} }
	local serverNow = workspace:GetServerTimeNow()
	set(A.Started, serverNow)
	set(A.Ends, serverNow + seconds)
	set(A.Id, id) -- (last: a client sees the times with it)
	notice:FireAllClients(Rules.startText(id, extra))
	local first = Players:GetPlayers()[1]
	if first then
		PlayerData.track("event", first, "EventStarted", playersCount(), id) -- (a no-op without Analytics)
	end
	return true
end

-- Ends the running event (`why`: "time", "dawn", "dusk", "admin", "delivered", "beaten", "nobody"): its world goes, the
-- zombies roam on, the rewards, the attributes cleared, the toast.
function LiveEvents.finish(why: string)
	local run = running
	if not run then
		return
	end
	running = nil
	last = run.id
	-- (6.15 review: the state goes first, so an error in an event's end never leaves the banner and the markers up)
	for _, name in Rules.AttrNames do
		set(name, nil)
	end
	Zombies.eventReserve = 0
	table.clear(Zombies.eventSpared)
	local told = why == "delivered" or why == "nobody"
	local ok, err: any = pcall(function()
		if run.id == "bloodmoon" then
			stopBloodMoon()
		elseif run.id == "supply" then
			stopSupply()
		elseif run.id == "horde" then
			told = stopHorde(run, why) or told
		end
	end)
	if not ok then
		warn(`[LiveEvents] the end of {run.id} failed: {err}`)
		supply, horde = nil, nil
		pcall(stopBloodMoon)
	end
	if not told then
		notice:FireAllClients(Rules.endText(run.id, why))
	end
end

-- The deck's next event whose moment it is, when its time came.
local function canNow(id: string): boolean
	return (Rules.canStart(id, DayNight.hour(), playersCount()))
end

local function schedule(now: number)
	if playersCount() == 0 then
		nextAt = nil -- (the clock starts over with the next one who comes)
		waitingSince = nil
		return
	end
	local due = nextAt
	if not due then
		nextAt = now + Rules.gap(rng:NextNumber(), true)
		return
	end
	if not T.Enabled or now < due or now < retryAt then
		return
	end
	retryAt = now + T.Retry
	if #deck == 0 then
		deck = Rules.deck(function(): number
			return rng:NextNumber()
		end, last)
	end
	local id, index = Rules.pick(deck, canNow)
	if id and index then
		table.remove(deck, index)
		if begin(id) then
			nextAt = now + Rules.gap(rng:NextNumber(), false)
			waitingSince = nil
		end
		return
	end
	local since = waitingSince or now
	waitingSince = since
	if now - since >= T.MaxWait then
		-- (its moment did not come: a new deck, the always-ready events in it)
		deck = Rules.deck(function(): number
			return rng:NextNumber()
		end, last)
		waitingSince = now
	end
end

local function step()
	local now = os.clock()
	fadeStep(now) -- (6.15 review: an ended event's zombies falling back)
	local run = running
	if not run then
		schedule(now)
		return
	end
	shareRoom() -- (6.15 review: its budget's hold on the roamers, the players its zombies leave alone)
	if playersCount() == 0 then
		LiveEvents.finish("nobody")
		return
	end
	if now >= run.endsAt then
		LiveEvents.finish("time")
		return
	end
	if run.id == "bloodmoon" and not DayNight.isNight() then
		LiveEvents.finish("dawn")
		return
	elseif run.id == "rush" and DayNight.isNight() then
		LiveEvents.finish("dusk") -- (only by day: an admin's clock may bring the night early)
		return
	end
	local s = supply
	if s then
		supplyStep(s, now)
	end
	local h = horde
	if h then
		hordeStep(h, now)
	end
end

-- ── The API ────────────────────────────────────────────────────────────────

function LiveEvents.current(): string?
	local run = running
	return if run then run.id else nil
end

-- A job paid now (server/Jobs.luau payOrder): × this on its pay (1 without an event that pays, or for a mission); the
-- one paid took part (the daily task).
function LiveEvents.pay(player: Player, mission: boolean): number
	local run = running
	local multiplier = Rules.payOf(if run then run.id else nil, mission)
	if multiplier > 1 then
		tookPart(run, player)
	end
	return multiplier
end

-- The job waves' multiplier (Jobs.dangerOf): the Blood Moon's, never a mission's.
function LiveEvents.waves(mission: boolean): number
	return Rules.wavesOf(LiveEvents.current(), mission)
end

-- Rush hour's board: more ordinary offers, the next ones sooner.
function LiveEvents.extraOffers(): number
	return Rules.extraOffers(LiveEvents.current())
end

function LiveEvents.refresh(seconds: number): number
	return Rules.refreshOf(LiveEvents.current(), seconds)
end

-- The admin panel's EVENTS (server/Admin.luau checks the admin; `id` is checked here): an event now (the running one
-- ends first; the Blood Moon turns the clock to the night, rush hour to the morning), or "end". The answer to show.
function LiveEvents.adminStart(id: any): string
	if id == "end" then
		if not running then
			return "ADMIN: no live event is running."
		end
		LiveEvents.finish("admin")
		return "ADMIN: the live event ended."
	end
	local def = if type(id) == "string" then Rules.def(id) else nil
	if type(id) ~= "string" or not def then
		return "ADMIN: no such live event."
	end
	if running then
		LiveEvents.finish("admin")
	end
	if id == "bloodmoon" and not canNow(id) then
		DayNight.setClock(Config.DayNight.NightFrom + 0.1)
	elseif id == "rush" and not canNow(id) then
		DayNight.setClock(Config.DayNight.NightTo + 2)
	end
	if not begin(id) then
		return `ADMIN: the {def.name} could not start.`
	end
	nextAt = os.clock() + Rules.gap(rng:NextNumber(), false)
	return `ADMIN: {def.name} started ({def.minutes} min).`
end

function LiveEvents.start()
	for _, name in Rules.AttrNames do
		set(name, nil)
	end
	Jobs.live = {
		joined = function(player: Player) -- (6.15 review: a crew member paid with the event's bonus took part too)
			tookPart(running, player)
		end,
		pay = LiveEvents.pay,
		waves = LiveEvents.waves,
		extraOffers = LiveEvents.extraOffers,
		refresh = LiveEvents.refresh,
		current = LiveEvents.current,
	}
	-- The horde's kills (Main wired Zombies.onKill before this: the jobs' kills go on as they were).
	local before = Zombies.onKill
	Zombies.onKill = function(player: Player, z: Zombies.Zombie)
		-- (6.15 review: an event's zombie adds nothing to a mission's kill bonus: missions are never touched)
		if not (z.event and Jobs.onMission(player)) then
			before(player, z)
		end
		onKill(player, z)
	end
	-- The touch PUT DOWN (server/Cargo.luau and server/Equipment.luau hear it too: they hold nothing of the crate).
	Net.get("PutDown").OnServerEvent:Connect(function(player: Player)
		local s = supply
		if s and s.carrier == player and Net.limit(player, "CrateDown", Config.Robust.Limits.CrateDown) then
			putDown(s, "put")
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local s = supply
		if s and s.carrier == player then
			putDown(s, "left")
		end
		local h = horde
		if h then
			h.kills[player] = nil
		end
		local run = running
		if run then
			run.took[player] = nil
		end
	end)
	task.spawn(function()
		while true do
			task.wait(T.Tick)
			local ok, err: any = pcall(step)
			if not ok then
				warn(`[LiveEvents] {err}`)
			end
		end
	end)
end

return LiveEvents
