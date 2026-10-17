--!strict
-- 10.x DANGER (the owner: "both: on the easier difficulties only a timer and traps, on the harder ones zombies too"; "it
-- has to be designed to be fun"): a run's danger on the server. What a run holds is planned by shared/DangerRules.luau
-- (pure: the same house at the same difficulty, the same danger); this builds it into the run's house, runs it and
-- tells the party (the Runs remote's { kind = "danger", … }: client/RunDangerUi.luau). The numbers are Config.Runs'
-- (Danger by difficulty, Locks, Search, Rooms, Vault, Hazard, Zombies, Weapon). server/Runs.luau starts it
-- (RunDanger.start), server/Moving.luau calls `begin` at every run's start (Moving.onRunStart) and reads the run's state
-- it keeps on the move's session (s.danger: `sealed`, the vault's pieces nobody picks up; `route`, the doorways and
-- hazards Danny's grid shuts: server/MoveHelper.luau, shared/HouseRoute.luau shut).
--   * Locked rooms: a solid leaf in the doorway with a padlock (the tag RunLock, attribute Open) and its Unlock prompt
--     (E); its key in a searchable piece elsewhere. Every searchable piece has a Search prompt (F, the gamepad's Y,
--     held Search.Hold s): "Nothing in the Dresser." or the key, the party's ("🔑 Bedroom key found by Ann"; the
--     piece tagged RunKey once found). A hiding piece carried off before it was searched lets its key fall out: found
--     by whoever moved it. A locked room's pieces come a tier up (server/Loot.luau boost), and the doorway is a wall on
--     Danny's grid and the zombies' until it opens.
--   * The vault (Normal and up): each of its pieces in a steel and glass case (the model RunVault, attribute Open), Epic
--     or better (Legendary at the difficulty's chance), its Open prompt at the case's lock; its gold key found as the
--     others. Until then its pieces are sealed: no prompt, no pick, Danny never takes one.
--   * Hazards on the floor (the tag RunHazard, attribute Kind), looked at every Hazard.Every s for every party member in
--     the house: a creaky patch (carrying over it: you stumble, the piece drops and takes a knock, more for a fragile
--     one: Moving.runDrop), a puddle (you slide along your walk: the Knock remote, client/ZombieFx.luau), a cracked
--     ceiling (a player near: it shakes Warn s, dust falling, then the plaster drops: damage under it).
--   * Zombies (Hard and up: Config.Runs.Danger Inside, Yard, Wave, Boss, Speed, Kinds), the game's own
--     (server/Zombies.luau): shamblers in the house (resident roamers: they wander, notice you within Zombies.Aggro and
--     walk the house's way to you through its doorways: Zombies.steer) and in the yard (YardAggro: the party arrives
--     unseen), never by a player, the way in or the truck (a run's parked truck is nobody's target); on Insane and
--     Nightmare a wave in the yard once half the clock is gone, marching at the door ("A horde is coming!"); on Nightmare
--     THE LANDLORD by the vault (bigger, much more health, his name over his head). A bite drops what you carry
--     (Zombies.onBite → Moving.runDrop). A kill counts: "Zombies stopped". Their spots and kinds are the run's own dice
--     (DangerRules.dice), never math.random's.
--   * The party hears the run's danger in a line once each (the locks, the vault, the floor, the zombies), the HUD's view
--     whenever it changes, and the events (a key found, a door opened, the vault, a death, the horde, the boss down).
--   * The bat (Hard and up): every party member gets the run's bat (a Tool, Weapon.Name) in their backpack; a click
--     swings it (server/CloseCombat.luau swing: the city's strike); carrying a piece puts it away (and it cannot be
--     taken out while you carry). Gone when the run ends or you leave it; back after a respawn.
--   * A player who dies in a run drops what they carried (Moving) and comes back by the truck (Moving.respawnAt); the
--     party hears it.
--   * 10.4: the host's upgrade tree's Spare keys (UpgradeRules.effect(levels, "startKey")): the first locked room's key
--     is found from the start ("by Spare keys").
--   RunDanger.start(port)          the hooks (Moving.onRunStart, Zombies.steer, Zombies.onBite) and the loop
--   RunDanger.begin(s, port)       a run's danger now (its move's session; Moving's run start listener)
--   RunDanger.step()               one look at every run (the loop's; the tests')
--   RunDanger.stateOf(s) / stateFor(player)   a run's state (the tests')
--   RunDanger.result(host)         the results card's lines: { vault = true / false / nil (none), stopped = kills,
--                                  zombies = the run had any, keys = how many }

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DangerRules = require(Shared.DangerRules)
local HouseRoute = require(Shared.HouseRoute)
local Net = require(Shared.Net)
local SandboxMap = require(Shared.SandboxMap)

local Zombies = require(script.Parent.Zombies)

local RunDanger = {}

local R = Config.Runs
local H = R.Hazard
local Z = R.Zombies

type Rect = HouseRoute.Rect
type Key = { id: string, name: string, spot: number, found: boolean, by: string? }
type Lock = { plan: DangerRules.Lock, key: Key, open: boolean, leaf: BasePart?, parts: { Instance }, prompt: ProximityPrompt?, hinge: CFrame?, swing: number }
type Hazard = {
	plan: DangerRules.Hazard,
	part: BasePart,
	ceiling: BasePart?,
	dust: ParticleEmitter?,
	warnAt: number?,
	readyAt: number,
	again: { [Player]: number }, -- (a creak or a puddle again for that player from then on: os.clock)
	on: { [Player]: boolean },
}
type Case = { spot: number, model: Model, prompt: ProximityPrompt? }
type Vault = { spots: { number }, key: Key, open: boolean, by: string?, cases: { Case }, at: Vector3? }
type Path = { at: number, goal: Vector3, points: { HouseRoute.Point }? }
type State = {
	s: any,
	port: any,
	id: string,
	level: Config.RunDanger,
	plan: DangerRules.Plan,
	folder: Folder,
	keys: { Key },
	locks: { Lock },
	vault: Vault?,
	sealed: { [number]: string },
	route: { walls: { Rect }, floors: { Rect }, key: string },
	hazards: { Hazard },
	searches: { [number]: ProximityPrompt },
	searched: { [number]: boolean },
	zombies: { any },
	stopped: number,
	boss: any?,
	bossAt: Vector3?,
	waved: boolean,
	grid: HouseRoute.Grid?,
	gridAt: number,
	paths: { [any]: Path },
	bats: { [Player]: Tool },
	told: { [Player]: boolean },
	dead: { [Player]: boolean },
	sent: { [Player]: string },
	seen: { [Player]: boolean },
	brief: string, -- (the run's danger in a line: told to every party member once)
	slowAt: number,
	ended: boolean,
	roll: () -> number, -- (its own dice: DangerRules.dice, never math.random's)
}

local states: { [any]: State } = {} -- by the move's session
local done: { [Player]: { [string]: any } } = {} -- a run's results card lines, kept a while after its end (by its host)
local started = false

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- (the run's own dice, a number from a to b)
local function between(st: State, a: number, b: number): number
	return a + st.roll() * (b - a)
end

local function say(player: Player, text: string)
	if player.Parent then
		Net.get("Notice"):FireClient(player, text)
	end
end

local function send(player: Player, message: { [string]: any })
	if player.Parent then
		Net.get("Runs"):FireClient(player, message)
	end
end

-- The party now (the move's members: server/Moving.luau keeps them), the host first.
local function party(st: State): { Player }
	local s = st.s
	local list: { Player } = {}
	if s.owner and s.owner.Parent then
		table.insert(list, s.owner)
	end
	for player in (s.members or {}) :: { [Player]: boolean } do
		if player ~= s.owner and player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

-- An event for the whole party: its line on the danger HUD (and its sound, a banner).
local function tell(st: State, text: string, sound: string?, banner: boolean?)
	for _, player in party(st) do
		send(player, { kind = "danger", event = text, sound = sound, banner = banner })
	end
end

local function nameOf(id: number?): string
	if id == nil then
		return "the party"
	end
	local player = Players:GetPlayerByUserId(id)
	if player then
		return player.DisplayName
	end
	return if id < 0 then Config.MoveHelper.Name else "the party"
end

local function bodyOf(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

-- ── The house's frame ──────────────────────────────────────────────────────

local function worldAt(st: State, x: number, z: number, y: number?): Vector3
	return (st.s.origin :: CFrame) * Vector3.new(x, y or 0, z)
end

local function planAt(st: State, at: Vector3): (number, number, number)
	local p = (st.s.origin :: CFrame):PointToObjectSpace(at)
	return p.X, p.Y, p.Z
end

-- Is `at` in the run's house (its plan's box, floor to ceiling and a little)?
local function inside(st: State, at: Vector3): boolean
	local plan = st.s.plan
	local x, y, z = planAt(st, at)
	local lo, hi = plan.min, plan.max
	if not lo or not hi then
		return false
	end
	return x >= lo.X - 2 and x <= hi.X + 2 and z >= lo.Z - 2 and z <= hi.Z + 2 and y > -6 and y < (tonumber(plan.ceiling) or 12) + 6
end

local function part(st: State, name: string, size: Vector3, frame: CFrame, color: Color3, material: Enum.Material, solid: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = frame
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanQuery = solid == true
	p.CanTouch = false
	p.CastShadow = solid == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = st.folder
	return p
end

local function label(parent: Instance, text: string, color: Color3, lift: number, far: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "RunDangerLabel"
	gui.Size = UDim2.fromOffset(150, 30)
	gui.StudsOffset = Vector3.new(0, lift, 0)
	gui.MaxDistance = far
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	local words = Instance.new("TextLabel")
	words.Size = UDim2.fromScale(1, 1)
	words.BackgroundTransparency = 1
	words.Text = text
	words.TextColor3 = color
	words.TextStrokeTransparency = 0.3
	words.TextScaled = true
	words.Font = Enum.Font.GothamBold
	words.Parent = gui
	gui.Parent = parent
end

-- A prompt only the run's party sees (client/MovingHud.luau's MovePrompt, its MoveOwner: the host).
local function prompt(st: State, parent: Instance, name: string, action: string, object: string, key: Enum.KeyCode, pad: Enum.KeyCode?, hold: number, reach: number): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = key
	if pad then
		p.GamepadKeyCode = pad
	end
	p.HoldDuration = hold
	p.MaxActivationDistance = reach
	p.RequiresLineOfSight = false
	p:SetAttribute("MoveOwner", st.s.owner.UserId)
	CollectionService:AddTag(p, "MovePrompt")
	p.Parent = parent
	return p
end

-- Is `player` on this run, alive, on foot, near `at` (within `reach`), hands free when `free`?
local function canUse(st: State, player: Player, at: Vector3, reach: number, free: boolean): (boolean, string?)
	if st.ended or st.s.ended or not (st.s.members or {})[player] then
		return false, nil
	end
	local character, humanoid, root = bodyOf(player)
	if not character or not humanoid or not root or humanoid.Health <= 0 or humanoid.SeatPart ~= nil then
		return false, nil
	end
	local dx, dz = root.Position.X - at.X, root.Position.Z - at.Z
	if dx * dx + dz * dz > reach * reach then
		return false, nil
	end
	if free and character:GetAttribute("Carrying") ~= nil then
		return false, "Your hands are full: put the piece down first (G)."
	end
	return true, nil
end

-- ── Danny's grid and the zombies' ──────────────────────────────────────────

-- What the run shuts on the house's grids: the locked doorways (walls) and the hazards (floor Danny walks round).
local function updateRoute(st: State)
	local walls: { Rect } = {}
	local names: { string } = {}
	for n, lock in st.locks do
		if not lock.open then
			table.insert(walls, lock.plan.rect)
			table.insert(names, tostring(n))
		end
	end
	local floors: { Rect } = {}
	for _, hazard in st.hazards do
		table.insert(floors, hazard.plan.rect)
	end
	st.route = { walls = walls, floors = floors, key = `{st.s.id}:{table.concat(names, ",")}:{#floors}` }
	local grid = st.grid
	if grid then
		HouseRoute.shut(grid, walls, {}, st.route.key)
	end
end

-- The zombies' grid with the pieces standing now (every Zombies.Block s).
local function blockGrid(st: State, clock: number)
	local grid = st.grid
	if not grid or clock < st.gridAt then
		return
	end
	st.gridAt = clock + Z.Block
	local s = st.s
	local rects: { Rect } = {}
	for _, spot in s.move.order do
		local thing = s.move.things[spot]
		local item = s.items[spot]
		if thing and item and item.root and item.root.Parent and (thing.state == "home" or thing.state == "ground") and inside(st, item.root.Position) then
			local x, _, z = planAt(st, item.root.Position)
			local size = item.root.Size
			table.insert(rects, { x0 = x - size.X / 2, z0 = z - size.Z / 2, x1 = x + size.X / 2, z1 = z + size.Z / 2 })
		end
	end
	HouseRoute.block(grid, rects)
end

-- Zombies.steer: a zombie in a run's house walks its way through the doorways (nil: not in one, straight on).
local function steer(z: any, from: Vector3, goal: Vector3): Vector3?
	for _, st in states do
		local grid = st.grid
		if not grid or st.ended or not inside(st, from) then
			continue
		end
		if not inside(st, goal) then
			return nil
		end
		local fx, _, fz = planAt(st, from)
		local tx, _, tz = planAt(st, goal)
		local clock = os.clock()
		local cache = st.paths[z]
		if not cache or clock - cache.at > Z.Steer or (cache.goal - goal).Magnitude > Z.Again then
			local made: Path = { at = clock, goal = goal, points = HouseRoute.path(grid, fx, fz, tx, tz, 4) }
			st.paths[z] = made
			cache = made
		end
		local points = if cache then cache.points else nil
		if not points then
			return nil
		end
		for _, p in points do
			if (p.x - fx) ^ 2 + (p.z - fz) ^ 2 > 1.44 then
				return worldAt(st, p.x, p.z, from.Y - (st.s.origin :: CFrame).Position.Y)
			end
		end
		return goal
	end
	return nil
end

-- ── The keys and the locks ─────────────────────────────────────────────────

local sendView: (State, boolean?) -> ()

local function found(st: State, key: Key, by: string, how: string?)
	if key.found then
		return
	end
	key.found, key.by = true, by
	local item = st.s.items[key.spot]
	if item and item.model then
		CollectionService:AddTag(item.model, "RunKey")
		item.model:SetAttribute("Key", key.name)
		item.model:SetAttribute("Found", true)
		item.model:SetAttribute("By", by)
		item.model:SetAttribute("MoveOwner", st.s.owner.UserId)
	end
	for _, lock in st.locks do
		if lock.key == key and lock.prompt then
			lock.prompt.ObjectText = `🔑 {lock.plan.name}`
		end
	end
	local vault = st.vault
	if vault and vault.key == key then
		for _, case in vault.cases do
			if case.prompt then
				case.prompt.ObjectText = "🗝 Vault: the key is found"
			end
		end
	end
	tell(st, how or DangerRules.keyText(key.name, by), "task_done")
	sendView(st, true)
end

local function unlock(st: State, lock: Lock, player: Player)
	if lock.open then
		return
	end
	if not lock.key.found then
		say(player, `🔒 The {lock.plan.name} is locked. Its key is hidden in the furniture of another room: search it (F).`)
		send(player, { kind = "danger", sound = "soft_nope" })
		return
	end
	lock.open = true
	local leaf = lock.leaf
	if leaf then
		leaf.CanCollide = false
		leaf.CanQuery = false
		leaf:SetAttribute("Open", true)
		local hinge = lock.hinge
		if hinge then
			local width = math.max(leaf.Size.X, leaf.Size.Z)
			local along = if leaf.Size.X >= leaf.Size.Z then CFrame.new(width / 2, 0, 0) else CFrame.new(0, 0, width / 2)
			local goal = hinge * CFrame.Angles(0, lock.swing, 0) * along
			local okTween = pcall(function()
				local tween = game:GetService("TweenService"):Create(leaf, TweenInfo.new(R.Locks.Swing, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = goal })
				tween:Play()
			end)
			if not okTween then
				leaf.CFrame = goal
			end
		end
	end
	for _, thing in lock.parts do
		thing:Destroy()
	end
	table.clear(lock.parts)
	if lock.prompt then
		lock.prompt:Destroy()
		lock.prompt = nil
	end
	updateRoute(st)
	tell(st, DangerRules.lockText(lock.plan.name, player.DisplayName), "house_door_creak")
	sendView(st, true)
end

local function buildLock(st: State, n: number, lp: DangerRules.Lock)
	local s = st.s
	local plan = s.plan
	local door = plan.doors[lp.door]
	local key: Key = { id = `lock{n}`, name = DangerRules.keyName(lp.room), spot = lp.key, found = false }
	table.insert(st.keys, key)
	local lock: Lock = { plan = lp, key = key, open = false, leaf = nil, parts = {}, prompt = nil, hinge = nil, swing = 0 }
	table.insert(st.locks, lock)
	if not door then
		return
	end
	local origin: CFrame = s.origin
	local tall = (tonumber(plan.doorHeight) or 9) - 0.1
	local thick = (tonumber(plan.wall) or 1) * 0.6
	local width = (tonumber(door.width) or 6) - 0.1
	local alongX = door.axis == "X"
	-- the room behind it: which way it lies (the padlock on the other side, the leaf swings into it)
	local inward = 1
	for _, room in plan.rooms do
		if room.id == lp.room then
			local c = (room.min + room.max) / 2
			inward = if alongX then (if c.Z >= door.at.Z then 1 else -1) else (if c.X >= door.at.X then 1 else -1)
		end
	end
	local L = R.Locks
	local leaf = part(st, "RunLockLeaf", if alongX then Vector3.new(width, tall, thick) else Vector3.new(thick, tall, width),
		origin * CFrame.new(door.at.X, tall / 2, door.at.Z), rgb(L.Leaf), Enum.Material.Wood, true)
	leaf:SetAttribute("Open", false)
	leaf:SetAttribute("Room", lp.name)
	leaf:SetAttribute("Key", key.name)
	leaf:SetAttribute("MoveOwner", s.owner.UserId) -- (whose run: the map shows its party's)
	CollectionService:AddTag(leaf, "RunLock")
	lock.leaf = leaf
	-- its hinge at one jamb; it swings Locks.Open degrees into the room behind (its doorway's rect opens on the grids)
	local open = math.rad(L.Open)
	if alongX then
		lock.hinge = origin * CFrame.new(door.at.X - width / 2, tall / 2, door.at.Z)
		lock.swing = -inward * open
	else
		lock.hinge = origin * CFrame.new(door.at.X, tall / 2, door.at.Z - width / 2)
		lock.swing = inward * open
	end
	-- the padlock and its shackle on the near side, a strap of iron across
	local out = -inward * (thick / 2 + 0.2)
	local lockAt = if alongX then CFrame.new(door.at.X + width * 0.28, 3.6, door.at.Z + out) else CFrame.new(door.at.X + out, 3.6, door.at.Z + width * 0.28)
	local body = part(st, "RunPadlock", if alongX then Vector3.new(0.7, 0.8, 0.35) else Vector3.new(0.35, 0.8, 0.7), origin * lockAt, rgb(L.Brass), Enum.Material.Metal)
	local shackle = part(st, "RunShackle", if alongX then Vector3.new(0.5, 0.45, 0.12) else Vector3.new(0.12, 0.45, 0.5), origin * lockAt * CFrame.new(0, 0.6, 0), rgb(L.Iron), Enum.Material.Metal)
	local strapAt = if alongX then CFrame.new(door.at.X, 3.6, door.at.Z + out * 0.6) else CFrame.new(door.at.X + out * 0.6, 3.6, door.at.Z)
	local strap = part(st, "RunStrap", if alongX then Vector3.new(width, 0.35, 0.1) else Vector3.new(0.1, 0.35, width), origin * strapAt, rgb(L.Iron), Enum.Material.Metal)
	label(body, "🔒", rgb(L.Brass), 1.6, 40)
	table.insert(lock.parts, body)
	table.insert(lock.parts, shackle)
	table.insert(lock.parts, strap)
	local p = prompt(st, body, "RunUnlock", "Unlock", `🔒 {lp.name}`, Enum.KeyCode.E, nil, L.Hold, L.Reach)
	lock.prompt = p
	p.Triggered:Connect(function(player: Player)
		local ok = canUse(st, player, body.Position, L.Reach + 2, false)
		if ok then
			unlock(st, lock, player)
		end
	end)
end

-- A searchable piece's Search prompt: "Nothing in the Dresser." or the key it hides.
local function search(st: State, spot: number, player: Player)
	local s = st.s
	local item = s.items[spot]
	local thing = s.move.things[spot]
	if st.searched[spot] or not item or not thing or thing.state ~= "home" then
		return
	end
	local reach = R.Search.Reach + math.max(thing.size.X, thing.size.Z) / 2 + 2
	local ok, why = canUse(st, player, item.root.Position, reach, true)
	if not ok then
		if why then
			say(player, why)
		end
		return
	end
	st.searched[spot] = true
	local p = st.searches[spot]
	if p then
		p:Destroy()
		st.searches[spot] = nil
	end
	for _, key in st.keys do
		if key.spot == spot then
			found(st, key, player.DisplayName, `{DangerRules.keyText(key.name, player.DisplayName)} (in the {thing.name})`)
			return
		end
	end
	say(player, `🔍 Nothing in the {thing.name}.`)
	send(player, { kind = "danger", sound = "soft_nope" })
end

local function buildSearch(st: State, spot: number)
	local item = st.s.items[spot]
	local thing = st.s.move.things[spot]
	if not item or not thing or not item.root then
		return
	end
	local p = prompt(st, item.root, "RunSearch", "Search", thing.name, Enum.KeyCode.F, Enum.KeyCode.ButtonY, R.Search.Hold, R.Search.Reach)
	p.RequiresLineOfSight = true -- (never through a wall: as the pieces' own prompts)
	st.searches[spot] = p
	p.Triggered:Connect(function(player: Player)
		search(st, spot, player)
	end)
end

-- A hiding piece moved before anybody searched it: its key falls out, found by whoever moved it.
local function watchKeys(st: State)
	local s = st.s
	for _, key in st.keys do
		local thing = s.move.things[key.spot]
		if not key.found and thing and thing.state ~= "home" then
			local by = nameOf(thing.carrier)
			found(st, key, by, `🔑 The {key.name} fell out of the {thing.name}: {by} has it`)
		end
	end
	for spot, p in st.searches do
		local thing = s.move.things[spot]
		p.Enabled = thing ~= nil and thing.state == "home" and not st.searched[spot]
	end
end

-- ── The vault ──────────────────────────────────────────────────────────────

local function openVault(st: State, player: Player)
	local vault = st.vault
	if not vault or vault.open then
		return
	end
	if not vault.key.found then
		say(player, "🗝 The vault needs its gold key: search the furniture (F). It is hidden deep in the house.")
		send(player, { kind = "danger", sound = "soft_nope" })
		return
	end
	vault.open, vault.by = true, player.DisplayName
	local s = st.s
	for _, case in vault.cases do
		st.sealed[case.spot] = nil
		local item = s.items[case.spot]
		local thing = s.move.things[case.spot]
		if item and thing then
			item.pick.Enabled = thing.state == "home" or thing.state == "ground"
		end
		case.model:SetAttribute("Open", true)
		if case.prompt then
			case.prompt:Destroy()
			case.prompt = nil
		end
		for _, d in case.model:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "VaultBase" then
				d.CanCollide = false
				d.CanQuery = false
				local goal = d.CFrame - Vector3.new(0, d.Size.Y + R.Vault.Lid, 0)
				local okTween = pcall(function()
					local tween = game:GetService("TweenService"):Create(d, TweenInfo.new(R.Vault.Sink, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = goal, Transparency = 1 })
					tween:Play()
				end)
				if not okTween then
					d.CFrame = goal
				end
				task.delay(R.Vault.Sink + 0.1, function()
					if d.Parent then
						d:Destroy()
					end
				end)
			elseif d:IsA("BillboardGui") then
				d:Destroy()
			end
		end
	end
	tell(st, DangerRules.vaultText(player.DisplayName), "stored_fanfare")
	sendView(st, true)
end

local function buildVault(st: State, plan: DangerRules.Vault)
	local s = st.s
	local key: Key = { id = "vault", name = DangerRules.keyName(nil), spot = plan.key, found = false }
	table.insert(st.keys, key)
	local vault: Vault = { spots = plan.spots, key = key, open = false, by = nil, cases = {}, at = nil }
	st.vault = vault
	local V = R.Vault
	local steel, glass, gold = rgb(V.Steel), rgb(V.Glass), rgb(V.Gold)
	for _, spot in plan.spots do
		local item = s.items[spot]
		local thing = s.move.things[spot]
		if not item or not item.model or not thing then
			continue
		end
		st.sealed[spot] = `🗝 The {thing.name} is locked in the vault: find its gold key (search the furniture, F).`
		item.pick.Enabled = false
		item.help.Enabled = false
		local frame, size = item.model:GetBoundingBox()
		local hx, hz = size.X / 2 + V.Margin, size.Z / 2 + V.Margin
		local bottom = -size.Y / 2
		local tall = size.Y + V.Lid
		local model = Instance.new("Model")
		model.Name = "RunVaultCase"
		model:SetAttribute("Open", false)
		model:SetAttribute("Spot", spot)
		model:SetAttribute("MoveOwner", s.owner.UserId)
		local function piece(name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: Color3, material: Enum.Material, solid: boolean): Part
			local p = part(st, name, Vector3.new(sx, sy, sz), frame * CFrame.new(x, y, z), color, material, solid)
			p.Parent = model
			return p
		end
		piece("VaultBase", hx * 2 + 0.3, 0.15, hz * 2 + 0.3, 0, bottom + 0.075, 0, steel, Enum.Material.DiamondPlate, false)
		for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			piece("VaultPost", 0.3, tall, 0.3, corner[1] * hx, bottom + tall / 2, corner[2] * hz, steel, Enum.Material.Metal, true)
		end
		piece("VaultLid", hx * 2 + 0.3, 0.2, hz * 2 + 0.3, 0, bottom + tall, 0, steel, Enum.Material.Metal, true)
		for _, side in { -1, 1 } do
			local pane = piece("VaultGlass", hx * 2, tall - 0.2, 0.1, 0, bottom + tall / 2, side * hz, glass, Enum.Material.Glass, true)
			pane.Transparency = 0.6
			local wall = piece("VaultGlass", 0.1, tall - 0.2, hz * 2, side * hx, bottom + tall / 2, 0, glass, Enum.Material.Glass, true)
			wall.Transparency = 0.6
		end
		local lockY = bottom + math.min(tall * 0.5, 2.6)
		local box = piece("VaultLock", 0.9, 1.2, 0.3, 0, lockY, -hz - 0.2, steel, Enum.Material.Metal, false)
		piece("VaultKeyhole", 0.3, 0.3, 0.06, 0, lockY, -hz - 0.38, gold, Enum.Material.Neon, false)
		label(model:FindFirstChild("VaultLid") or box, "🗝 VAULT", gold, 1.2, 45)
		model.Parent = st.folder
		CollectionService:AddTag(model, "RunVault")
		local p = prompt(st, box, "RunVaultOpen", "Open the vault", "🗝 Vault", Enum.KeyCode.E, nil, V.Hold, V.Reach)
		p.Triggered:Connect(function(player: Player)
			local ok = canUse(st, player, box.Position, V.Reach + 2, false)
			if ok then
				openVault(st, player)
			end
		end)
		table.insert(vault.cases, { spot = spot, model = model, prompt = p })
		vault.at = vault.at or item.root.Position
	end
end

-- ── The hazards ────────────────────────────────────────────────────────────

local function buildHazard(st: State, plan: DangerRules.Hazard): Hazard
	local s = st.s
	local origin: CFrame = s.origin
	local at = origin * CFrame.new(plan.x, 0, plan.z)
	local hazard: Hazard
	if plan.kind == "creak" then
		local C = H.Creak
		local patch = part(st, "RunCreak", Vector3.new(plan.sx, 0.08, plan.sz), at * CFrame.new(0, 0.07, 0), rgb(C.Color), Enum.Material.WoodPlanks) -- (over a rug)
		for n = 1, 3 do
			local turn = math.rad(between(st, -70, 70))
			local crack = part(st, "RunCrack", Vector3.new(0.14, 0.04, math.min(plan.sx, plan.sz) * 0.8), at * CFrame.new((n - 2) * plan.sx * 0.25, 0.12, 0) * CFrame.Angles(0, turn, 0),
				rgb(C.Crack), Enum.Material.SmoothPlastic)
			crack.Parent = patch
		end
		hazard = { plan = plan, part = patch, ceiling = nil, dust = nil, warnAt = nil, readyAt = 0, again = {}, on = {} }
	elseif plan.kind == "puddle" then
		local P = H.Puddle
		local patch = part(st, "RunPuddle", Vector3.new(plan.sx, 0.04, plan.sz), at * CFrame.new(0, 0.08, 0), rgb(P.Color), Enum.Material.Glass)
		patch.Transparency = 0.45
		patch.Reflectance = 0.25
		local small = math.min(plan.sx, plan.sz)
		for _, side in { -1, 1 } do
			local off = (math.max(plan.sx, plan.sz) - small) / 2 * side
			local disc = part(st, "RunPuddleDisc", Vector3.new(0.06, small, small),
				at * CFrame.new(if plan.sx >= plan.sz then off else 0, 0.09, if plan.sx >= plan.sz then 0 else off) * CFrame.Angles(0, 0, math.rad(90)), rgb(P.Color), Enum.Material.Glass)
			disc.Shape = Enum.PartType.Cylinder
			disc.Transparency = 0.35
			disc.Reflectance = 0.3
			disc.Parent = patch
		end
		hazard = { plan = plan, part = patch, ceiling = nil, dust = nil, warnAt = nil, readyAt = 0, again = {}, on = {} }
	else
		local P = H.Plaster
		local patch = part(st, "RunPlaster", Vector3.new(plan.sx, 0.05, plan.sz), at * CFrame.new(0, 0.08, 0), rgb(P.Color), Enum.Material.Sand)
		patch.Transparency = 0.3
		local high = (tonumber(s.plan.ceiling) or 10) - 0.15
		local ceiling = part(st, "RunCeilingCrack", Vector3.new(plan.sx * 0.8, 0.25, plan.sz * 0.8), at * CFrame.new(0, high, 0), rgb(P.Color), Enum.Material.Concrete)
		for n = 1, 3 do
			local crack = part(st, "RunCrack", Vector3.new(0.12, 0.05, plan.sz * 0.7), at * CFrame.new((n - 2) * plan.sx * 0.22, high - 0.15, 0) * CFrame.Angles(0, math.rad(between(st, -60, 60)), 0),
				Color3.fromRGB(70, 64, 58), Enum.Material.SmoothPlastic)
			crack.Parent = ceiling
		end
		local dust: ParticleEmitter? = nil
		pcall(function() -- (the dust falling while it shakes: looks only)
			local made = Instance.new("ParticleEmitter")
			made.Name = "Dust"
			made.Enabled = false
			made.Rate = 40
			made.Lifetime = NumberRange.new(1, 1.6)
			made.Speed = NumberRange.new(2, 5)
			made.SpreadAngle = Vector2.new(20, 20)
			made.EmissionDirection = Enum.NormalId.Bottom
			made.Color = ColorSequence.new(rgb(P.Color))
			made.Size = NumberSequence.new(0.35)
			made.Parent = ceiling
			dust = made
		end)
		hazard = { plan = plan, part = patch, ceiling = ceiling, dust = dust, warnAt = nil, readyAt = 0, again = {}, on = {} }
	end
	hazard.part:SetAttribute("Kind", plan.kind)
	hazard.part:SetAttribute("MoveOwner", s.owner.UserId)
	CollectionService:AddTag(hazard.part, "RunHazard")
	return hazard
end

-- The plaster comes down now: a chunk drops onto the patch, everybody under it hurt.
local function dropPlaster(st: State, hazard: Hazard, clock: number)
	local P = H.Plaster
	hazard.warnAt = nil
	hazard.readyAt = clock + P.Rearm
	hazard.part:SetAttribute("Warn", nil)
	if hazard.dust then
		hazard.dust.Enabled = false
	end
	local ceiling = hazard.ceiling
	if ceiling then
		ceiling.CFrame = (st.s.origin :: CFrame) * CFrame.new(hazard.plan.x, (tonumber(st.s.plan.ceiling) or 10) - 0.15, hazard.plan.z)
	end
	local chunk = part(st, "RunPlasterChunk", Vector3.new(P.Chunk[1], P.Chunk[2], P.Chunk[3]), (st.s.origin :: CFrame) * CFrame.new(hazard.plan.x, 0.3, hazard.plan.z),
		rgb(P.Color), Enum.Material.Concrete)
	task.delay(4, function()
		if chunk.Parent then
			chunk:Destroy()
		end
	end)
	local damage = DangerRules.plasterDamage(st.id)
	for _, player in party(st) do
		local _, humanoid, root = bodyOf(player)
		if humanoid and root and humanoid.Health > 0 and inside(st, root.Position) then
			local x, _, z = planAt(st, root.Position)
			if HouseRoute.toRect(x, z, hazard.plan.rect) <= 0.6 then
				pcall(function()
					humanoid:TakeDamage(damage)
				end)
				say(player, "🧱 The plaster came down on you!")
				send(player, { kind = "danger", sound = "heavy_drop" })
			end
		end
	end
end

-- The party's feet in the house (every Hazard.Every s): the creaks, the puddles, the plaster; a death; the bat put
-- away while carrying.
local function watchFeet(st: State, clock: number)
	for _, player in party(st) do
		if not st.seen[player] then
			st.seen[player] = true
			if st.brief ~= "" then
				say(player, st.brief) -- (the run's danger in a line, once)
			end
		end
		local character, humanoid, root = bodyOf(player)
		if not character or not humanoid or not root then
			continue
		end
		if humanoid.Health <= 0 then
			if not st.dead[player] then
				st.dead[player] = true
				tell(st, `💀 {player.DisplayName} is down: back by the truck in a few seconds`, "move_fail")
			end
			continue
		end
		st.dead[player] = nil
		local bat = st.bats[player]
		if bat and bat.Parent == character and character:GetAttribute("Carrying") ~= nil then
			pcall(function()
				humanoid:UnequipTools() -- (carrying puts the bat away)
			end)
		end
		if not inside(st, root.Position) then
			continue
		end
		local x, _, z = planAt(st, root.Position)
		for _, hazard in st.hazards do
			local kind = hazard.plan.kind
			local on = HouseRoute.toRect(x, z, hazard.plan.rect) <= 0
			local was = hazard.on[player] == true
			hazard.on[player] = on
			if kind == "plaster" then
				local dx, dz = x - hazard.plan.x, z - hazard.plan.z
				if not hazard.warnAt and clock >= hazard.readyAt and dx * dx + dz * dz <= H.Plaster.Trigger ^ 2 then
					hazard.warnAt = clock
					hazard.part:SetAttribute("Warn", true)
					if hazard.dust then
						hazard.dust.Enabled = true
					end
					local ceiling = hazard.ceiling
					if ceiling then
						local base = ceiling.CFrame
						task.spawn(function() -- (a shake: looks only)
							for _ = 1, math.floor(H.Plaster.Warn / 0.05) do
								if not ceiling.Parent or not hazard.warnAt then
									break
								end
								ceiling.CFrame = base * CFrame.new(between(st, -0.12, 0.12), between(st, -0.05, 0.05), between(st, -0.12, 0.12))
								task.wait(0.05)
							end
						end)
					end
				end
			elseif on and not was and clock >= (hazard.again[player] or -math.huge) then
				if kind == "creak" then
					if character:GetAttribute("Carrying") ~= nil then
						hazard.again[player] = clock + H.Creak.Rearm
						local dropped = st.port.runDrop(player, "stumble", DangerRules.knock(st.id))
						if dropped then
							say(player, "💥 The boards gave way: you stumbled and dropped it!")
							send(player, { kind = "danger", sound = "grip_slip" })
						end
					else
						hazard.again[player] = clock + 1
						send(player, { kind = "danger", sound = "house_door_creak" }) -- (a creak underfoot: the warning)
					end
				elseif kind == "puddle" then
					local v: Vector3? = (root :: any).AssemblyLinearVelocity
					local flat = if v then Vector3.new(v.X, 0, v.Z) else Vector3.new(0, 0, 0)
					if flat.Magnitude > 3 then
						hazard.again[player] = clock + H.Puddle.Rearm
						Net.get("Knock"):FireClient(player, flat.Unit * H.Puddle.Slide)
						send(player, { kind = "danger", sound = "splash" })
					end
				end
			end
		end
	end
	for _, hazard in st.hazards do
		if hazard.plan.kind == "plaster" and hazard.warnAt and clock - (hazard.warnAt :: number) >= H.Plaster.Warn then
			dropPlaster(st, hazard, clock)
		end
	end
end

-- ── The zombies ────────────────────────────────────────────────────────────

local function farFromParty(st: State, at: Vector3, away: number): boolean
	for _, player in Players:GetPlayers() do
		local _, _, root = bodyOf(player)
		if root and (root.Position - at).Magnitude < away then
			return false
		end
	end
	return true
end

-- A cell of the house for a zombie, the dice's among every one that is: open, Away studs from everybody and the way
-- in, on no hazard, a stud or two from the other zombies of the run; near `center` (Vector3) within `least` … `most`
-- studs when given.
local function insideSpot(st: State, center: Vector3?, least: number?, most: number?): Vector3?
	local grid = st.grid
	if not grid then
		return nil
	end
	local g = grid :: HouseRoute.Grid
	local entry: CFrame = (st.s.origin :: CFrame) * (st.s.plan.entry :: CFrame)
	local others: { Vector3 } = {}
	for _, z in st.zombies do
		if not z.dead and z.root then
			table.insert(others, z.root.Position)
		end
	end
	local cells: { Vector3 } = {}
	for k = 1, g.nx * g.nz do
		if g.open[k] ~= 1 then
			continue
		end
		local i, j = (k - 1) % g.nx, (k - 1) // g.nx
		local x, z = g.x0 + i * g.step, g.z0 + j * g.step
		local at = worldAt(st, x, z, 0)
		if (at - entry.Position).Magnitude < Z.Away or DangerRules.hazardAt(st.plan.hazards, x, z) then
			continue
		end
		if center then
			local d = (Vector3.new(at.X, 0, at.Z) - Vector3.new(center.X, 0, center.Z)).Magnitude
			if d < (least or 0) or d > (most or math.huge) then
				continue
			end
		end
		local crowded = false
		for _, other in others do
			if (Vector3.new(other.X, 0, other.Z) - Vector3.new(at.X, 0, at.Z)).Magnitude < 3 then
				crowded = true
				break
			end
		end
		if not crowded then
			table.insert(cells, at)
		end
	end
	for _ = 1, Z.Tries do
		if #cells == 0 then
			break
		end
		local n = math.clamp(1 + math.floor(st.roll() * #cells), 1, #cells)
		local at = cells[n]
		if farFromParty(st, at, Z.Away) then
			return at
		end
		table.remove(cells, n)
	end
	return nil
end

local function onStream(x: number, z: number): boolean
	for _, stream in SandboxMap.Streams do
		local points = stream.points
		for n = 1, #points - 1 do
			local a, b = points[n], points[n + 1]
			local dx, dz = b.x - a.x, b.z - a.z
			local l2 = dx * dx + dz * dz
			local t = if l2 > 0 then math.clamp(((x - a.x) * dx + (z - a.z) * dz) / l2, 0, 1) else 0
			local px, pz = a.x + dx * t - x, a.z + dz * t - z
			if px * px + pz * pz < (stream.width / 2 + 4) ^ 2 then
				return true
			end
		end
	end
	return false
end

-- A spot in the run's yard for a zombie: in its zone (Edge studs in), off the house, its landmarks and the stream, on
-- the ground, YardAway from everybody and the party's arrival, Truck studs off the truck; `door` with `far`: that far
-- from the door at least.
local function yardSpot(st: State, door: Vector3?, far: number?): Vector3?
	local id = st.s.contract.id
	local zone = SandboxMap.zone(id)
	local house = SandboxMap.house(id)
	if not zone then
		return nil
	end
	local r = zone.rect
	local arrive = Vector3.new(zone.arrive.x, SandboxMap.GroundTop, zone.arrive.z)
	local truck = st.s.truck
	local truckAt: Vector3? = if truck and truck.chassis and truck.chassis.Parent then truck.chassis.Position else nil
	for _ = 1, Z.Tries do
		local x = between(st, r.x0 + Z.Edge, math.max(r.x0 + Z.Edge, r.x1 - Z.Edge))
		local z = between(st, r.z0 + Z.Edge, math.max(r.z0 + Z.Edge, r.z1 - Z.Edge))
		local at = Vector3.new(x, SandboxMap.GroundTop, z)
		local box = house and house.box
		if box and x > box.x0 - 4 and x < box.x1 + 4 and z > box.z0 - 4 and z < box.z1 + 4 then
			continue
		end
		local blocked = false
		for _, mark in SandboxMap.Landmarks do
			if x > mark.x0 - 3 and x < mark.x1 + 3 and z > mark.z0 - 3 and z < mark.z1 + 3 then
				blocked = true
				break
			end
		end
		if blocked or onStream(x, z) or (at - arrive).Magnitude < Z.YardAway or not farFromParty(st, at, Z.YardAway) then
			continue
		end
		if truckAt and (Vector3.new(truckAt.X, at.Y, truckAt.Z) - at).Magnitude < Z.Truck then
			continue
		end
		if door and far and (Vector3.new(door.X, at.Y, door.Z) - at).Magnitude < far then
			continue
		end
		local ok, hit = pcall(function(): RaycastResult?
			return workspace:Raycast(at + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0))
		end)
		if ok and hit and (hit.Material == Enum.Material.Water or hit.Position.Y > SandboxMap.GroundTop + 3) then
			continue
		end
		return at
	end
	return nil
end

local function kindOf(st: State): string
	return DangerRules.pickKind(st.level.Kinds, st.roll())
end

-- A zombie of the run: its speed × the difficulty's, its eyes (Zombies.Aggro in the house, YardAggro in the yard); counted.
local function enlist(st: State, z: any, aggro: number?)
	if not z then
		return
	end
	z.aggro = aggro
	local speed = st.level.Speed
	if speed ~= 1 and type(z.walkSpeed) == "number" then
		z.walkSpeed *= speed
		z.baseSpeed = (z.baseSpeed or z.walkSpeed) * speed
		if z.humanoid and not z.roamer and not z.resident then
			z.humanoid.WalkSpeed = z.walkSpeed -- (a wave's: at its full speed from the start; a roamer's when it wakes)
		end
	end
	if z.model then
		z.model:SetAttribute("RunZombie", st.s.id)
	end
	table.insert(st.zombies, z)
end

local function spawnInside(st: State, count: number)
	for _ = 1, count do
		local at = insideSpot(st, nil, nil, nil)
		if at then
			enlist(st, Zombies.spawn(kindOf(st), at, st.s.owner, false, true, true), Z.Aggro)
		end
	end
end

local function spawnYard(st: State, count: number)
	for _ = 1, count do
		local at = yardSpot(st, nil, nil)
		if at then
			enlist(st, Zombies.spawn(kindOf(st), at, st.s.owner, false, true, true), Z.YardAggro)
		end
	end
end

-- Insane and Nightmare: half the clock gone, a wave in the yard marches at the door.
local function wave(st: State)
	st.waved = true
	local door: Vector3 = st.s.site.door
	local made = 0
	for _ = 1, st.level.Wave do
		local at = yardSpot(st, door, Z.WaveFar) or yardSpot(st, door, Z.WaveFar / 2)
		local z = if at then Zombies.spawn(kindOf(st), at, st.s.owner) else nil
		if z then
			Zombies.march(z, door, "run")
			enlist(st, z, nil)
			made += 1
		end
	end
	if made > 0 then
		tell(st, "🧟 A horde is coming! Get the loot into the truck and hold the door.", "horde_siren", true)
	end
end

-- Nightmare: THE LANDLORD guards the vault (or the middle of the house without one).
local function spawnBoss(st: State)
	local B = Z.Boss
	local center = (st.vault and st.vault.at) or worldAt(st, (st.s.plan.min.X + st.s.plan.max.X) / 2, (st.s.plan.min.Z + st.s.plan.max.Z) / 2, 0)
	local at = insideSpot(st, center, 3, 10) or insideSpot(st, center, 0, 18) or insideSpot(st, nil, nil, nil)
	if not at then
		return
	end
	local z = Zombies.spawn(B.Kind, at, st.s.owner, false, true, true)
	if not z then
		return
	end
	local boss: any = z
	enlist(st, boss, Z.Aggro)
	st.boss = boss
	st.bossAt = Vector3.new(center.X, at.Y, center.Z)
	local humanoid: Humanoid? = boss.humanoid
	if humanoid then
		humanoid.MaxHealth = B.Health
		humanoid.Health = B.Health
	end
	local model: Model? = boss.model
	if model then
		pcall(function()
			model:ScaleTo(B.Scale)
		end)
		model:SetAttribute("RunBoss", B.Name)
		local head = model:FindFirstChild("Head") or model.PrimaryPart
		if head then
			label(head, B.Name, rgb(B.Color), 3, 80)
		end
	end
end

-- The run's zombies: the dead counted (the boss's fall told), the boss kept by the vault while calm, the wave due.
local function watchZombies(st: State, clock: number)
	blockGrid(st, clock)
	for index = #st.zombies, 1, -1 do
		local z = st.zombies[index]
		if z.dead then
			table.remove(st.zombies, index)
			st.paths[z] = nil
			if z.killed then
				st.stopped += 1
				if z == st.boss then
					tell(st, `👑 {Z.Boss.Name} is down!`, "stored_fanfare", true)
				end
			end
			if z == st.boss then
				st.boss = nil
			end
		end
	end
	local boss = st.boss
	local guard = st.bossAt
	if boss and guard and not boss.hunting then
		boss.home = guard
	end
	local move = st.s.move
	if st.level.Wave > 0 and not st.waved and DangerRules.waveDue(move.startedAt, move.seconds, workspace:GetServerTimeNow()) then
		wave(st)
	end
end

-- ── The bat ────────────────────────────────────────────────────────────────

local function makeBat(player: Player): Tool
	local look = Config.Melee.BatLook
	local tool = Instance.new("Tool")
	tool.Name = R.Weapon.Name
	tool.ToolTip = "Click to swing (the run's bat)"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.GripForward = Vector3.new(-1, 0, 0)
	tool.GripRight = Vector3.new(0, 1, 0)
	tool.GripUp = Vector3.new(0, 0, 1)
	tool.GripPos = Vector3.new(0, 0, -look.Length * 0.32)
	tool:SetAttribute("RunWeapon", R.Weapon.Kind)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(look.Barrel, look.Barrel, look.Length)
	handle.Color = rgb(look.Wood)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Parent = tool
	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(look.Barrel + 0.05, look.Barrel + 0.05, look.Length * 0.35)
	grip.CFrame = handle.CFrame * CFrame.new(0, 0, -look.Length * 0.32)
	grip.Color = rgb(look.Grip)
	grip.Material = Enum.Material.Fabric
	grip.CanCollide = false
	grip.CanQuery = false
	grip.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = grip
	weld.Parent = grip
	grip.Parent = tool
	tool.Activated:Connect(function()
		pcall(function()
			require(script.Parent.CloseCombat).swing(player, R.Weapon.Kind, nil, true)
		end)
	end)
	tool.Equipped:Connect(function()
		local character, humanoid = bodyOf(player)
		if character and humanoid and character:GetAttribute("Carrying") ~= nil then
			pcall(function()
				humanoid:UnequipTools()
			end)
			say(player, "🏏 Your hands are full: put the piece down first (G).")
		end
	end)
	return tool
end

-- Every party member alive holds the run's bat (Hard and up); whoever is not on the run any more has none (and no
-- danger line: LEAVE THE RUN).
local function syncBats(st: State)
	local members = st.s.members or {}
	for player in st.seen do
		if player ~= st.s.owner and not members[player] then
			st.seen[player], st.sent[player] = nil, nil
			send(player, { kind = "danger" })
		end
	end
	for player, tool in st.bats do
		if not members[player] or not player.Parent then
			tool:Destroy()
			st.bats[player] = nil
		end
	end
	if not st.level.Weapon then
		return
	end
	for _, player in party(st) do
		local character, humanoid = bodyOf(player)
		local backpack = player:FindFirstChildOfClass("Backpack")
		if not character or not humanoid or humanoid.Health <= 0 or not backpack then
			continue
		end
		local tool = st.bats[player]
		if tool and (tool.Parent == backpack or tool.Parent == character) then
			continue
		end
		if tool then
			tool:Destroy()
		end
		local made = makeBat(player)
		made.Parent = backpack
		st.bats[player] = made
		if not st.told[player] then
			st.told[player] = true
			say(player, "🏏 You got a bat for this run: take it out (1) and click to swing. Picking up a piece puts it away.")
		end
	end
end

-- ── The party's view ───────────────────────────────────────────────────────

local function viewOf(st: State): { [string]: any }
	local keys: { { [string]: any } } = {}
	for _, lock in st.locks do
		table.insert(keys, { name = lock.key.name, room = lock.plan.name, found = lock.key.found, by = lock.key.by, open = lock.open })
	end
	local vault = st.vault
	local alive = 0
	for _, z in st.zombies do
		if not z.dead then
			alive += 1
		end
	end
	local name = st.id
	for _, def in R.Difficulties do
		if def.id == st.id then
			name = def.name
		end
	end
	return {
		kind = "danger",
		house = st.s.contract.id,
		difficulty = st.id,
		name = name,
		keys = keys,
		vault = if vault then { open = vault.open, key = vault.key.found, by = vault.by or vault.key.by, pieces = #vault.spots } else nil,
		zombies = alive,
		stopped = st.stopped,
		boss = if st.boss then Z.Boss.Name else nil,
		weapon = st.level.Weapon,
		hazards = #st.hazards,
	}
end

sendView = function(st: State, force: boolean?)
	local view = viewOf(st)
	local parts: { string } = { tostring(view.zombies), tostring(view.stopped), tostring(view.boss) }
	for _, key in view.keys do
		table.insert(parts, `{key.found}{key.open}`)
	end
	if view.vault then
		table.insert(parts, `{view.vault.open}{view.vault.key}`)
	end
	local key = table.concat(parts, "|")
	for _, player in party(st) do
		if force or st.sent[player] ~= key then
			st.sent[player] = key
			send(player, view)
		end
	end
end

-- ── A run ──────────────────────────────────────────────────────────────────

local function teardown(st: State)
	if st.ended then
		return
	end
	st.ended = true
	local s = st.s
	done[s.owner] = RunDanger.summary(st) -- (read by the results card at once: kept a minute, RunDanger.result)
	for _, z in st.zombies do
		if not z.dead then
			pcall(function()
				Zombies.despawn(z)
			end)
		end
	end
	table.clear(st.zombies)
	for player, tool in st.bats do
		tool:Destroy()
		st.bats[player] = nil
	end
	for player in st.seen do
		send(player, { kind = "danger" }) -- (the HUD's danger line goes)
	end
	st.folder:Destroy()
	states[s] = nil
end

function RunDanger.summary(st: State): { [string]: any }
	local level = st.level
	return { vault = if st.vault then st.vault.open else nil, stopped = st.stopped, zombies = level.Inside + level.Yard + level.Wave > 0 or level.Boss, keys = #st.keys,
		at = os.clock() }
end

function RunDanger.begin(s: any, port: any)
	if not s or states[s] or s.ended or type(s.contract) ~= "table" or not s.contract.difficulty or type(s.plan) ~= "table" then
		return
	end
	local id = DangerRules.difficulty(s.contract.difficulty)
	local plan = DangerRules.plan(s.plan, id)
	local folder = Instance.new("Folder")
	folder.Name = `RunDanger_{s.id}`
	folder.Parent = if s.interior and s.interior.Parent then s.interior.Parent else workspace
	local st: State = {
		s = s,
		port = port,
		id = id,
		level = DangerRules.level(id),
		plan = plan,
		folder = folder,
		keys = {},
		locks = {},
		vault = nil,
		sealed = {},
		route = { walls = {}, floors = {}, key = "" },
		hazards = {},
		searches = {},
		searched = {},
		zombies = {},
		stopped = 0,
		boss = nil,
		bossAt = nil,
		waved = false,
		grid = nil,
		gridAt = 0,
		paths = setmetatable({}, { __mode = "k" }) :: any,
		bats = {},
		told = {},
		dead = {},
		sent = {},
		seen = {},
		brief = "",
		slowAt = 0,
		ended = false,
		roll = DangerRules.dice((tonumber(s.plan.seed) or 0) * 977 + (tonumber(s.id) or 0)),
	}
	states[s] = st
	s.danger = st -- (server/Moving.luau reads `sealed`, server/MoveHelper.luau `route`)
	local made, grid = pcall(HouseRoute.grid, s.plan, Z.Radius, Z.Grid)
	st.grid = if made then grid else nil
	-- the locks and their keys, every searchable piece's Search, the vault, the hazards, the loot lifted
	for n, lp in plan.locks do
		buildLock(st, n, lp)
	end
	for _, spot in plan.searchable do
		buildSearch(st, spot)
	end
	local vaultPlan = plan.vault
	if vaultPlan then
		buildVault(st, vaultPlan)
	end
	for _, hp in plan.hazards do
		table.insert(st.hazards, buildHazard(st, hp))
	end
	local Loot = require(script.Parent.Loot)
	for spot, steps in plan.lifts do
		Loot.boost(s, spot, steps)
	end
	if vaultPlan then
		for spot, floor in vaultPlan.floors do
			Loot.boost(s, spot, 0, floor)
		end
	end
	-- 10.4: the host's upgrade tree's Spare keys: the first locked room's key is the party's from the start
	local first = st.locks[1]
	if first then
		local ok, profile = pcall(function(): any
			return require(script.Parent.PlayerData).get(s.owner)
		end)
		local levels = if ok and type(profile) == "table" then profile.sandboxUpgrades else nil
		if require(Shared.UpgradeRules).effect(levels, "startKey") >= 1 then
			found(st, first.key, "Spare keys", `🔑 Your spare key fits the {first.plan.name}: no need to search for it`)
		end
	end
	updateRoute(st)
	blockGrid(st, os.clock())
	-- the zombies (Hard and up)
	spawnInside(st, st.level.Inside)
	spawnYard(st, st.level.Yard)
	if st.level.Boss then
		spawnBoss(st)
	end
	local brief: { string } = {}
	if #st.locks > 0 then
		table.insert(brief, `🔒 {#st.locks} locked room{if #st.locks == 1 then "" else "s"}: search the furniture (F) for the keys`)
	end
	if st.vault then
		table.insert(brief, "🗝 a vault with its own gold key")
	end
	if #st.hazards > 0 then
		table.insert(brief, "⚠ watch the floor")
	end
	if st.level.Inside + st.level.Yard > 0 then
		table.insert(brief, if st.level.Boss then `🧟 zombies, and {Z.Boss.Name} by the vault` else "🧟 zombies in the house and the yard")
	end
	st.brief = table.concat(brief, " · ")
	sendView(st, true)
end

function RunDanger.step()
	local clock = os.clock()
	for s, st in states do
		if s.ended or not s.interior or not s.interior.Parent then
			teardown(st)
			continue
		end
		watchFeet(st, clock)
		if clock >= st.slowAt then
			st.slowAt = clock + 0.5
			watchKeys(st)
			watchZombies(st, clock)
			syncBats(st)
			sendView(st, false)
		end
	end
end

function RunDanger.stateOf(s: any): State?
	return states[s]
end

-- The state of the run `player` is on (its host or a member), nil none (the tests').
function RunDanger.stateFor(player: Player): State?
	for s, st in states do
		if s.owner == player or (s.members or {})[player] then
			return st
		end
	end
	return nil
end

function RunDanger.result(host: Player): { [string]: any }?
	for s, st in states do
		if s.owner == host then
			return RunDanger.summary(st)
		end
	end
	local kept = done[host]
	if kept and os.clock() - (tonumber(kept.at) or 0) > 60 then
		done[host] = nil
		return nil
	end
	return kept
end

-- A bite on a run's player: what they carry goes down (the bite's knock on it).
local function onBite(player: Player, humanoid: Humanoid, z: any)
	if humanoid.Parent ~= player.Character then
		return -- (a buddy's or Danny's body: their own rules)
	end
	for s, st in states do
		if not st.ended and (s.members or {})[player] then
			local damage = if z and z.def then tonumber(z.def.damage) or 0 else 0
			if st.port.runDrop(player, "bite", damage) then
				say(player, "🧟 Bitten! You dropped what you carried.")
				send(player, { kind = "danger", sound = "grip_slip" })
			end
			return
		end
	end
end

function RunDanger.start(port: any)
	if started then
		return
	end
	started = true
	port.onRunStart(function(s: any, given: any)
		RunDanger.begin(s, given or port)
	end)
	Zombies.steer = steer
	Zombies.onBite = onBite
	task.spawn(function()
		while true do
			task.wait(H.Every)
			local ok, err = pcall(RunDanger.step :: any)
			if not ok then
				warn(`[RunDanger] {err}`)
			end
		end
	end)
end

return RunDanger
