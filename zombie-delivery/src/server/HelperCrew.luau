--!strict
-- 10.1 THE HELPERS' CREW (Config.Crew; the owner: "you'll be able to get different employees who can do something
-- different. There don't have to be many, but Danny will be the base, so I'd cancel having to buy him. Because you'll
-- have to get them somehow. And maybe when one dies, then … something"). The rules are shared/CrewRules.luau's
-- (tests/crewrules_test.luau); this keeps every player's crew (profile.crew, saved by server/PlayerData.luau) and runs
-- what happens to it; tests/crew_runtime_test.luau runs it with the real Moving and MoveHelper.
--   * Danny is free and every player's from the start (no hire any more). A run's helper is its host's pick of their
--     crew (CrewRules.comes: Danny by default; the pick in hospital: the first ready one instead, said so): one helper a
--     run, as Danny was one a move, so the NPCs stay few. Each kind is a server/MoveHelper.luau helper with its own
--     name, look, name tag ("Strong · ZDC Moving"), health, walk and carry, through the hooks below (MoveHelper calls
--     them; it is passed in as a Port of its own functions once: no require loop):
--       Danny the mover (as ever), Bruno the strong one (carries a piece for two alone, slowly: Moving.helperTake's 10.1
--       hook reads his body's CrewSolo), Zip the quick one (one-hand and small pieces, fast; none heavy, none for two),
--       Gus the guard (carries nothing: walks with his boss, goes after a zombie near him or his boss within his leash,
--       hits it every Guard.Every s with server/Zombies.luau's damage, cause "melee", by nobody: his kills pay nobody;
--       the zombies go after him as after any helper, so he pulls them off you), Lucy the finder (small pieces; while
--       she is in a run every party player and the run's inside carry the attribute CrewSense: her Sense studs, within
--       which client/LootOutline.luau draws the Epic and Legendary pieces through walls and the map shows the keys and
--       the vault sooner). The crew's refusals (a piece he may not carry) say why and name who can.
--   * Your helper waits at your warehouse in the lobby (Config.Crew.Lobby: beside its door, facing the plaza, the one
--     who would come into your next run; nobody while you are in a run or all are in hospital), his "Crew" prompt (only
--     yours: MoveOwner) opens the CREW window (client/CrewUi.luau; his card's 👥 CREW too, client/MoveHelperCard.luau).
--   * The rescue: at a run's start (its first look) a helper is trapped in the house with the odds of its difficulty
--     (CrewRules.rescueChance): the kind the most of the party lack (CrewRules.rescueKind; nobody lacks one: any, the
--     bonus for all), tied to a chair in a room away from the way in (the room farthest from it whose open cell his way
--     reaches: shared/HouseRoute.luau's grid, the pieces standing), sitting, roped, "Help!" now and then while a party
--     player is near; tagged RunRescue (CollectionService) with his CrewKind on the model, so the map shows him. Holding
--     E Rescue.Hold s ("Untie <name>") frees him: he says his line, joins the crew of EVERY party player who lacks him
--     (saved soon; the whole party carried the run together, and nobody races a friend to the prompt), the others get
--     the bonus money instead (CrewRescue). 10.3 (the owner: "why does the yellow one I freed walk after me? Let him
--     stay home, not bother me"): he never follows the party; he says he'll wait at your warehouse and, Rescue.Leave s
--     later, fades away (Rescue.Fade s): he is home, in the CREW window.
--   * Down in a run: a helper at 0 health lies down (MoveHelper's fall) and stays down Down.Seconds: a ProximityPrompt
--     on him ("Revive <name>", E held Down.Revive s, any party player), his model tagged CrewDown with its
--     CrewDownUntil (the server time: client/CrewUi.luau's ring and countdown over him). Revived: up where he lies
--     with half his health (Down.Health), on with his work. Nobody did: he is out of the run (fades away, his body gone, no comeback this run) and in
--     hospital (CrewRules.toHospital: the host's crew, saved soon) for Hospital.Seconds; the CREW window shows the time
--     left and can discharge him early for money (CrewDischarge). Danny too: nobody is ever lost for good. Outside a
--     run (the city's moves) a fall is as before (back at the van Respawn s later); in the lobby nothing hurts them.
--   * The Crew remote (Config.Robust.Limits.Crew): { kind = "state" } (the window's rows), { kind = "pick", id } (who
--     comes into your runs; saved), { kind = "discharge", id } (out of hospital now, paid); the server sends the state
--     after every change and { kind = "open" } from his prompt.
--   HelperCrew.start()                  the remote, the lobby's stands, the loop (server/SandboxBoot.luau)
--   HelperCrew.step(dt)                 one look at the runs' rescues and the stands (the loop's; the tests')
--   HelperCrew.crewOf(player)           a player's crew (profile.crew, made when missing)
--   HelperCrew.sendState(player)        the CREW window's state to them
--   For server/MoveHelper.luau: wire(port), kindFor(s), name(kind), look(kind), health(h), dress(h, model), pace(h),
--   lifts(h), classFor(h, class), refuse(h, thing), line(h, key), helloText(h), fallText(h), downed(h, body, clock),
--   guard(h, body, dt, clock), joined(h), left(h), sync(s, h)
--   For the tests: rescueOf(s), free(s, player), revive(h, player), random (a function: 0 … 1, math.random)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local CrewRules = require(Shared.CrewRules)
local Route = require(Shared.HouseRoute)
local Rules = require(Shared.MovingRules)
local Npcs = require(script.Parent.Npcs)
local PlayerData = require(script.Parent.PlayerData)
local Zombies = require(script.Parent.Zombies)

local HelperCrew = {}

local C = Config.Crew
local H = Config.MoveHelper
local TAG = "RunRescue"
local DOWN = "CrewDown" -- (a helper down in a run: client/CrewUi.luau's ring over him)
local SIT = "rbxassetid://2506281703" -- Roblox's R15 sit (server/MoveHelper.luau's, server/Buddy.luau's)
local ROPE = Color3.fromRGB(176, 140, 88)
local WOOD = Color3.fromRGB(122, 84, 52)

-- MoveHelper's own functions (HelperCrew.wire): his walk, his words, his body.
export type Port = {
	go: (h: any, body: any, goal: Vector3, inside: boolean, near: number, speed: number, dt: number, clock: number, walk: boolean?) -> boolean,
	inside: (h: any, at: Vector3) -> boolean,
	place: (h: any, at: Vector3, face: Vector3?, why: string?) -> (),
	say: (h: any, key: string, clock: number, force: boolean?) -> boolean,
	setDoing: (h: any, action: string, spot: number?) -> (),
	tellCrew: (h: any) -> (),
	tell: (h: any, text: string) -> (),
	remove: (h: any) -> (),
	halt: (body: any) -> (),
	fade: (body: any, out: boolean, seconds: number) -> (),
}

-- A helper's own state here (by MoveHelper's helper): down since, his revive prompt, out of the run, Gus's next hit.
type State = { downAt: number?, prompt: ProximityPrompt?, out: boolean, hitAt: number }
-- A run's trapped helper: his kind, model, chair, prompt, ropes, sit, freed (by whom), his calls and looks.
type Rescue = {
	kind: string,
	model: Model,
	chair: Model,
	prompt: ProximityPrompt?,
	ropes: { Instance },
	sit: AnimationTrack?,
	freed: boolean,
	by: Player?,
	helpAt: number,
	leaveAt: number, -- 10.3 when the freed one fades away home (math.huge: not freed yet)
	fading: { [BasePart]: number }?, -- 10.3 his parts' own transparency while he fades (the step's clock drives it)
	gone: boolean,
}
-- A move seen (sync): its helper, its rescue (decided once), the players given CrewSense, said "nobody comes".
type Run = { h: any, decided: boolean, rescue: Rescue?, sensed: { [Player]: boolean }, told: boolean }

local port: Port? = nil
local states: { [any]: State } = {}
local runs: { [any]: Run } = {}
local stands: { [Player]: { kind: string, model: Model } } = {}
local remote: RemoteEvent? = nil
local started = false
local notice = Net.get("Notice")

HelperCrew.random = function(): number
	return math.random()
end

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function say(player: Player, text: string)
	if player.Parent then
		notice:FireClient(player, text)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function isRun(s: any): boolean
	return type(s.contract) == "table" and s.contract.difficulty ~= nil
end

local function stateOf(h: any): State
	local st = states[h]
	if not st then
		st = { downAt = nil, prompt = nil, out = false, hitAt = 0 }
		states[h] = st
	end
	return st
end

local function defOf(kind: any): Config.CrewKind
	return CrewRules.def(kind) or C.Kinds[C.Default]
end

-- ── The crews ──────────────────────────────────────────────────────────────

function HelperCrew.crewOf(player: Player): CrewRules.Saved
	local profile = PlayerData.get(player) :: any
	if type(profile) ~= "table" then
		return CrewRules.empty() -- (no profile yet: a new player's crew, kept nowhere)
	end
	local crew = profile.crew
	if type(crew) ~= "table" or type(crew.have) ~= "table" or type(crew.hospital) ~= "table" or type(crew.pick) ~= "string" then
		crew = CrewRules.clean(crew)
		profile.crew = crew
	end
	return crew :: CrewRules.Saved
end

local function saveSoon(player: Player)
	pcall(function()
		PlayerData.saveSoon(player)
	end)
end

function HelperCrew.sendState(player: Player)
	local r = remote
	if not r or not player.Parent then
		return
	end
	local crew = HelperCrew.crewOf(player)
	local now = os.time()
	CrewRules.heal(crew, now)
	local comes, instead = CrewRules.comes(crew, now)
	local profile = PlayerData.get(player) :: any
	r:FireClient(player, { kind = "state", rows = CrewRules.view(crew, now), pick = crew.pick, comes = comes, instead = instead,
		money = if type(profile) == "table" and type(profile.money) == "number" then profile.money else 0 })
end

-- ── For server/MoveHelper.luau ─────────────────────────────────────────────

function HelperCrew.wire(given: Port)
	port = given
end

-- The kind that comes with this move: its owner's (the run's host's) pick, else the first ready one; nil: nobody (said
-- once: they are all in hospital).
function HelperCrew.kindFor(s: any): string?
	local owner: Player = s.owner
	local crew = HelperCrew.crewOf(owner)
	local now = os.time()
	local kind, instead = CrewRules.comes(crew, now)
	local run = runs[s]
	if not run then
		run = { h = nil, decided = false, rescue = nil, sensed = {}, told = false }
		runs[s] = run
	end
	if not run.told and isRun(s) then
		local picked = defOf(crew.pick)
		if not kind then
			run.told = true
			say(owner, `🏥 Your whole crew is in hospital: nobody comes into this run (discharge one in the CREW window at your warehouse).`)
		elseif instead then
			run.told = true
			say(owner, `🏥 {picked.Name} is in hospital ({CrewRules.clock(CrewRules.hospitalLeft(crew, crew.pick, now))} left): {defOf(kind).Name} comes instead.`)
		end
	end
	return kind
end

function HelperCrew.name(kind: any): string
	return defOf(kind).Name
end

function HelperCrew.look(kind: any): any
	return CrewRules.look(kind)
end

function HelperCrew.health(h: any): number
	return CrewRules.health(h.kind)
end

-- His body just made: what the map, the clients and Moving read off it.
function HelperCrew.dress(h: any, model: Model)
	model:SetAttribute("CrewKind", h.kind)
	model:SetAttribute("CrewSolo", if CrewRules.solo(h.kind) then true else nil)
end

-- × his walk: his kind's (Bruno with a piece for two alone: × Solo too).
function HelperCrew.pace(h: any): number
	local solo = false
	if CrewRules.solo(h.kind) then
		local move = h.s.move
		local spot, role = Rules.holding(move, h.id)
		local thing = if spot then move.things[spot] else nil
		solo = role == "carrier" and thing ~= nil and thing.class == "pair"
	end
	return CrewRules.pace(h.kind, solo)
end

function HelperCrew.lifts(h: any): boolean
	return CrewRules.lifts(h.kind)
end

-- A piece of his list as his brain sees it: a piece for two is one he carries alone (Bruno), never one he waits at.
function HelperCrew.classFor(h: any, class: string): string
	return if class == "pair" and CrewRules.solo(h.kind) then "both" else class
end

-- A piece the crew gives him that he may not carry: the notice that says why (nil: he may).
function HelperCrew.refuse(h: any, thing: any): string?
	local ok, why = CrewRules.mayCarry(h.kind, thing.class, thing.weight)
	if ok then
		return nil
	end
	local def = defOf(h.kind)
	local him = CrewRules.him(h.kind)
	if why == "nothing" then
		return `{def.Icon} {def.Name} carries nothing: {CrewRules.he(h.kind)} guards you and fights the zombies.`
	elseif why == "pair" then
		return `{def.Icon} {def.Name} can't take the {thing.name}: it's a piece for two (lift it with a friend; Danny or Bruno can).`
	end
	return `{def.Icon} {def.Name} can't take the {thing.name}: it's too heavy for {him} (Danny or Bruno can).`
end

local PUNCH = { "Back off!", "Not today!", "Stay behind me!" }

-- His own words for `key` (nil: MoveHelperBrain's lines, the same for every kind).
function HelperCrew.line(h: any, key: string): string?
	local def = CrewRules.def(h.kind)
	if not def then
		return nil
	elseif key == "hello" and h.kind ~= C.Default then
		return def.Hello
	elseif key == "revived" then
		return def.Up
	elseif key == "punch" then
		return PUNCH[math.random(1, #PUNCH)]
	end
	return nil
end

-- What the crew is told when he comes with a move.
function HelperCrew.helloText(h: any): string
	local def = defOf(h.kind)
	local how = if Config.Sandbox.On then `give {CrewRules.him(h.kind)} pieces with your clipboard ({H.Clipboard.Key})` else `pick a piece for {CrewRules.him(h.kind)}`
	if not CrewRules.mayCarry(h.kind, "hand", 1) then
		return `{def.Icon} {def.Name} is with you: {string.lower(string.sub(def.Ability, 1, 1)) .. string.sub(def.Ability, 2)}.`
	end
	return `{def.Icon} {def.Name} is with you: {how}. {def.Ability}.`
end

-- His fall in a run (nil: the city's words: back at the van soon).
function HelperCrew.fallText(h: any): string?
	if not isRun(h.s) then
		return nil
	end
	local him = CrewRules.him(h.kind)
	return `🆘 {h.name} is down! Hold E by {him} within {C.Down.Seconds} s to get {him} up, or {CrewRules.he(h.kind)}'s out of the run.`
end

-- ── Down in a run ──────────────────────────────────────────────────────────

local function clearDown(h: any, st: State)
	local prompt = st.prompt
	st.prompt = nil
	if prompt then
		prompt:Destroy()
	end
	local body = h.body
	if body then
		body.model:SetAttribute("CrewDownUntil", nil)
		CollectionService:RemoveTag(body.model, DOWN)
	end
end

local function hospital(h: any)
	local owner: Player = h.s.owner
	local crew = HelperCrew.crewOf(owner)
	CrewRules.toHospital(crew, h.kind, os.time())
	saveSoon(owner)
	HelperCrew.sendState(owner)
end

-- Out of the run: he fades away (his body gone a moment later, no comeback this run) and goes to hospital.
local function goOut(h: any, st: State, clock: number)
	local p = port
	st.out = true
	clearDown(h, st)
	local body = h.body
	if body and p then
		p.fade(body, true, 1)
		task.delay(1.1, function()
			if h.body == body then
				p.remove(h)
			end
		end)
	end
	hospital(h)
	if p then
		local he = CrewRules.he(h.kind)
		p.tell(h, `🏥 Nobody got {h.name} up in time: {he}'s out of the run and in hospital for {CrewRules.clock(C.Hospital.Seconds)} (the CREW window can discharge {CrewRules.him(h.kind)} early).`)
		p.setDoing(h, "out", nil)
		p.tellCrew(h)
	end
	local _ = clock
end

-- A party player's revive (the prompt held Down.Revive s): up where he lies with half his health. True when he got up.
function HelperCrew.revive(h: any, player: Player): boolean
	local st = states[h]
	local body = h.body
	local p = port
	if not st or st.out or st.downAt == nil or not h.dead or h.s.ended or not h.s.members[player] or not body or not p then
		return false
	end
	clearDown(h, st)
	st.downAt = nil
	local hp = CrewRules.reviveHealth(h.kind)
	h.health = hp
	body.humanoid.Health = hp
	h.dead = false
	body.root.Anchored = false
	p.place(h, body.root.Position, nil, "revive") -- (on his feet where he lay)
	h.thinkAt, h.waited, h.dropping, h.fleeing = 0, 0, false, false
	local clock = os.clock()
	p.say(h, "revived", clock, true)
	p.tell(h, `🆘 {player.DisplayName} got {h.name} back on {CrewRules.his(h.kind)} feet!`)
	p.setDoing(h, "wait", nil)
	p.tellCrew(h)
	return true
end

-- MoveHelper's step while he is down: nil (not a run: the city's rules, back at the van soon), "down" (lying there,
-- the revive prompt on him) or "out" (out of the run: no comeback).
function HelperCrew.downed(h: any, body: any, clock: number): string?
	local s = h.s
	if not isRun(s) or s.ended then
		return nil
	end
	local st = stateOf(h)
	if st.out then
		return "out"
	end
	local downAt = st.downAt
	if downAt == nil then
		downAt = clock
		st.downAt = clock
		if body and body.model.Parent then
			body.root.Anchored = true -- (lying still: no getting up by itself)
			body.model:SetAttribute("CrewDownUntil", workspace:GetServerTimeNow() + C.Down.Seconds)
			CollectionService:AddTag(body.model, DOWN) -- (client/CrewUi.luau's ring finds him by it)
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "RevivePrompt"
			prompt.ActionText = `Revive {h.name}`
			prompt.ObjectText = "🆘 Down!"
			prompt.HoldDuration = C.Down.Revive
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.MaxActivationDistance = C.Down.Reach
			prompt.RequiresLineOfSight = false
			prompt.Parent = body.root
			prompt.Triggered:Connect(function(player: Player)
				HelperCrew.revive(h, player)
			end)
			st.prompt = prompt
		end
	end
	if CrewRules.downLeft(downAt :: number, clock) <= 0 then
		goOut(h, st, clock)
		return "out"
	end
	return "down"
end

-- ── Gus ────────────────────────────────────────────────────────────────────

-- Whom he walks with: the move's owner while alive and on it, else the nearest of its crew.
local function bossOf(h: any, here: Vector3): BasePart?
	local s = h.s
	local owner: Player = s.owner
	local root = if s.members[owner] then rootOf(owner) else nil
	if root then
		return root
	end
	local best: BasePart? = nil
	local far = math.huge
	for player in s.members do
		local r = rootOf(player)
		if r and (r.Position - here).Magnitude < far then
			best, far = r, (r.Position - here).Magnitude
		end
	end
	return best
end

-- Gus's own step (MoveHelper's, before his brain's: true when it moved him): a zombie within Guard.Range of him or his
-- boss and Guard.Leash of the boss: after it, a hit every Guard.Every s within Reach; else he walks behind his boss.
function HelperCrew.guard(h: any, body: any, dt: number, clock: number): boolean
	local g = defOf(h.kind).Guard
	local p = port
	if not g or not p then
		return false
	end
	local st = stateOf(h)
	local here: Vector3 = body.root.Position
	local boss = bossOf(h, here)
	local center = if boss then boss.Position else here
	local target: any = nil
	local targetAt: Vector3? = nil
	local best = math.huge
	for _, z in Zombies.all() do
		local root = z.root
		if z.dead or not root or not root.Parent then
			continue
		end
		local at = root.Position
		local near = math.min(flat(at, here), flat(at, center))
		if near <= g.Range and flat(at, center) <= g.Leash and math.abs(at.Y - here.Y) < 20 and near < best then
			best, target, targetAt = near, z, at
		end
	end
	local walk = Config.Movement.Walk * H.Speed
	if target and targetAt then
		h.action, h.spot = "fight", nil
		if flat(here, targetAt) <= g.Reach then
			p.halt(body)
			Npcs.face(body.model, targetAt, 0.15)
			if clock >= st.hitAt then
				st.hitAt = clock + g.Every
				Npcs.act(body.model, "knock")
				local away = Vector3.new(targetAt.X - here.X, 0, targetAt.Z - here.Z)
				Zombies.damage(target, g.Damage, nil, { cause = "melee", push = if away.Magnitude > 0.05 then away.Unit else nil })
				p.say(h, "punch", clock)
			end
		else
			p.go(h, body, targetAt, p.inside(h, targetAt), g.Reach * 0.8, walk * H.Sprint, dt, clock, true)
		end
		p.setDoing(h, "fight", nil)
		return true
	end
	if not boss then
		return false
	end
	local at = boss.Position
	local inside = p.inside(h, at)
	h.action, h.spot = "guard", nil
	if flat(here, at) > g.Follow or p.inside(h, here) ~= inside then
		p.go(h, body, at, inside, g.Follow, walk * (if flat(here, at) > g.Follow * 3 then H.Sprint else 1.15), dt, clock)
	else
		p.halt(body)
	end
	p.setDoing(h, "guard", nil)
	return true
end

-- ── The rescue ─────────────────────────────────────────────────────────────

-- A piece's footprint in the plan's frame (as server/MoveHelper.luau's).
local function footprint(s: any, item: any, thing: any): Route.Rect
	local frame = (s.origin :: CFrame):ToObjectSpace(item.root.CFrame)
	local _, yaw = frame:ToOrientation()
	return Route.footprint(frame.Position.X, frame.Position.Z, thing.size.X, thing.size.Z, yaw)
end

-- Where the chair stands: a frame in the plan (facing the way in), in the room farthest from the way in whose open cell
-- (the walls, the fixtures and the pieces standing: HouseRoute's grid) Rescue.Away studs or more from it his way
-- reaches; a plan without walls (a test's): the farthest room's middle. Nil: no room.
local function chairSpot(s: any): CFrame?
	local plan = s.plan
	local rooms = if type(plan) == "table" and type(plan.rooms) == "table" then plan.rooms else {}
	local entry: CFrame = if typeof(plan.entry) == "CFrame" then plan.entry else CFrame.new()
	local ex, ez = entry.Position.X, entry.Position.Z
	local made, grid = pcall(Route.grid, plan, nil, nil, nil)
	if not made then
		grid = nil
	end
	if grid then
		local list: { Route.Rect } = {}
		for _, spot in s.move.order do
			local thing = s.move.things[spot]
			local item = s.items[spot]
			if thing and item and item.root.Parent and (thing.state == "home" or thing.state == "ground") then
				table.insert(list, footprint(s, item, thing))
			end
		end
		Route.block(grid, list)
	end
	local order: { any } = table.clone(rooms)
	local function middle(room: any): (number, number)
		return (room.min.X + room.max.X) / 2, (room.min.Z + room.max.Z) / 2
	end
	table.sort(order, function(a: any, b: any): boolean
		local ax, az = middle(a)
		local bx, bz = middle(b)
		return (ax - ex) ^ 2 + (az - ez) ^ 2 > (bx - ex) ^ 2 + (bz - ez) ^ 2
	end)
	local margin = 2
	for _, room in order do
		local mx, mz = middle(room)
		local y = room.min.Y
		if not grid then
			if (mx - ex) ^ 2 + (mz - ez) ^ 2 >= C.Rescue.Away ^ 2 then
				return CFrame.lookAt(Vector3.new(mx, y, mz), Vector3.new(ex, y, ez))
			end
			continue
		end
		local g = grid :: Route.Grid
		local found: Vector3? = nil
		local bestGap = -1
		local x = room.min.X + margin
		while x <= room.max.X - margin do
			local z = room.min.Z + margin
			while z <= room.max.Z - margin do
				if Route.open(g, x, z) and (x - ex) ^ 2 + (z - ez) ^ 2 >= C.Rescue.Away ^ 2 then
					local gap = Route.gap(g, x - 0.01, z, x + 0.01, z) -- (the most room round him: the room's middle, off the walls)
					if gap > bestGap and Route.path(g, ex, ez, x, z) ~= nil then
						found, bestGap = Vector3.new(x, y, z), gap
					end
				end
				z += 2
			end
			x += 2
		end
		if found then
			return CFrame.lookAt(found, Vector3.new(ex, y, ez))
		end
	end
	return nil
end

local function part(parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = frame
	p.Color = color
	p.Material = Enum.Material.Wood
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = parent
	return p
end

-- The chair at `at` (its feet's middle on the floor, facing along it): a seat, a back, four legs.
local function buildChair(parent: Instance, at: CFrame): Model
	local chair = Instance.new("Model")
	chair.Name = "RescueChair"
	part(chair, "Seat", Vector3.new(2.4, 0.3, 2.2), at * CFrame.new(0, 1.65, 0), WOOD)
	part(chair, "Back", Vector3.new(2.4, 2.6, 0.3), at * CFrame.new(0, 3.1, 1.05), WOOD)
	for _, c in { { -1, -0.95 }, { 1, -0.95 }, { -1, 0.95 }, { 1, 0.95 } } do
		part(chair, "Leg", Vector3.new(0.3, 1.5, 0.3), at * CFrame.new(c[1], 0.75, c[2]), WOOD)
	end
	chair.Parent = parent
	return chair
end

-- A rope round him (welded to his root: cosmetic, no mass, no collisions).
local function rope(model: Model, root: BasePart, y: number, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = "Rope"
	p.Size = size
	p.Color = ROPE
	p.Material = Enum.Material.Fabric
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = root.CFrame * CFrame.new(0, y, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

local function sitDown(model: Model): AnimationTrack?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local ok, track = pcall(function(): AnimationTrack
		local animation = Instance.new("Animation")
		animation.AnimationId = SIT
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0)
	return track
end

-- The run's trapped helper: decided at its first look (the odds of its difficulty), the kind the party lacks most.
local function decide(s: any, run: Run)
	run.decided = true
	if not CrewRules.rescueRoll(s.contract.difficulty, HelperCrew.random()) then
		return
	end
	local missing: { [string]: number } = {}
	for player in s.members do
		local crew = HelperCrew.crewOf(player)
		for _, id in CrewRules.kinds() do
			if not CrewRules.has(crew, id) then
				missing[id] = (missing[id] or 0) + 1
			end
		end
	end
	local kind = CrewRules.rescueKind(missing, HelperCrew.random())
	local spot = chairSpot(s)
	if not spot then
		return
	end
	local origin: CFrame = s.origin
	local at = origin * spot
	local chair = buildChair(s.interior or workspace, at)
	local ok, made = pcall(Npcs.spawn, CrewRules.look(kind), at * CFrame.new(0, 0.9, 0.2))
	if not ok or typeof(made) ~= "Instance" then
		chair:Destroy()
		warn(`[HelperCrew] no trapped helper: {made}`)
		return
	end
	local model = made :: Model
	local root = model.PrimaryPart :: BasePart
	model:SetAttribute("CrewKind", kind)
	model:SetAttribute("RunRescue", true)
	model:SetAttribute("Busy", true) -- (Npcs' greeting leaves him alone: he is tied up)
	CollectionService:AddTag(model, TAG)
	local ropes: { Instance } = {}
	if root then
		root.Anchored = true
		table.insert(ropes, rope(model, root, 0.4, Vector3.new(2.5, 0.35, 1.6)))
		table.insert(ropes, rope(model, root, -0.6, Vector3.new(2.5, 0.35, 1.6)))
	end
	local def = defOf(kind)
	local rescue: Rescue = { kind = kind, model = model, chair = chair, prompt = nil, ropes = ropes, sit = sitDown(model), freed = false, by = nil,
		helpAt = 0, leaveAt = math.huge, fading = nil, gone = false }
	if root then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RescuePrompt"
		prompt.ActionText = `Untie {def.Name}`
		prompt.ObjectText = `{def.Icon} {def.Name} · tied up`
		prompt.HoldDuration = C.Rescue.Hold
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = C.Rescue.Reach
		prompt.RequiresLineOfSight = false
		prompt.Parent = root
		prompt.Triggered:Connect(function(player: Player)
			HelperCrew.free(s, player)
		end)
		rescue.prompt = prompt
	end
	run.rescue = rescue
end

-- `player` of the run held Untie: he is free, says his line, joins every party player's crew who lacks him (the
-- others: the bonus), and heads home (10.3: he fades away Rescue.Leave s later, never follows). True when freed now.
function HelperCrew.free(s: any, player: Player): boolean
	local run = runs[s]
	local rescue = run and run.rescue
	if not rescue or rescue.freed or s.ended or not s.members[player] then
		return false
	end
	rescue.freed, rescue.by = true, player
	local kind = rescue.kind
	local def = defOf(kind)
	local model = rescue.model
	if rescue.prompt then
		rescue.prompt:Destroy()
		rescue.prompt = nil
	end
	for _, r in rescue.ropes do
		r:Destroy()
	end
	table.clear(rescue.ropes)
	local track = rescue.sit
	rescue.sit = nil
	if track then
		pcall(function()
			track:Stop(0.3)
		end)
	end
	pcall(function()
		CollectionService:RemoveTag(model, TAG)
	end)
	model:SetAttribute("RunRescue", nil)
	model:SetAttribute("RunFreed", true)
	local root = model.PrimaryPart
	if root then
		local up = root.CFrame * CFrame.new(-2.2, 0.6, 0)
		model:PivotTo(up)
	end
	Npcs.say(model, def.Freed, 5)
	rescue.leaveAt = os.clock() + C.Rescue.Leave -- 10.3: home, not after the party
	local bonus = CrewRules.rescueBonus(s.contract.difficulty)
	local him = CrewRules.him(kind)
	for member in s.members do
		if not member.Parent then
			continue
		end
		local crew = HelperCrew.crewOf(member)
		if CrewRules.add(crew, kind) then
			say(member, `🎉 {def.Icon} {def.Name} joined your crew! {def.Ability}. {CrewRules.he(kind)}'ll wait at your warehouse: pick {him} in the CREW window to bring {him} into runs.`)
			saveSoon(member)
			HelperCrew.sendState(member)
		else
			PlayerData.addMoney(member, bonus, "CrewRescue", kind)
			say(member, `🙏 {def.Name} thanks you: {CrewRules.he(kind)}'s in your crew already, so here's {CrewRules.money(bonus)} instead.`)
		end
		if member ~= player then
			say(member, `🔓 {player.DisplayName} untied {def.Name}!`)
		end
	end
	return true
end

-- 10.3 the freed one goes home: Rescue.Leave s after his line he fades away (Rescue.Fade s), his body gone; he waits
-- at your warehouse (the CREW window), never after the party.
local function leave(rescue: Rescue, clock: number)
	if rescue.gone or clock < rescue.leaveAt then
		return
	end
	local model = rescue.model
	local fading = rescue.fading
	if not fading then
		Npcs.stop(model)
		local parts: { [BasePart]: number } = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				parts[d] = d.Transparency
			end
		end
		rescue.fading = parts
		fading = parts
	end
	local k = math.clamp((clock - rescue.leaveAt) / C.Rescue.Fade, 0, 1)
	for part, was in fading :: { [BasePart]: number } do
		if part.Parent then
			part.Transparency = was + (1 - was) * k
		end
	end
	if k >= 1 then
		rescue.gone = true
		Npcs.remove(model)
	end
end

local function endRun(s: any, run: Run)
	local rescue = run.rescue
	run.rescue = nil
	if rescue then
		pcall(function()
			CollectionService:RemoveTag(rescue.model, TAG)
		end)
		Npcs.remove(rescue.model)
		rescue.chair:Destroy()
	end
	for player in run.sensed do
		if player.Parent then
			player:SetAttribute("CrewSense", nil)
		end
	end
	table.clear(run.sensed)
	runs[s] = nil
end

-- Lucy in the run (not out): every party player and the run's inside carry her Sense (CrewSense); else none.
local function sense(s: any, run: Run)
	local h = run.h
	local st = if h then states[h] else nil
	local range = if h and isRun(s) and not (st and st.out) then defOf(h.kind).Sense else 0
	local value: number? = if range > 0 then range else nil
	for player in s.members do
		if player.Parent and player:GetAttribute("CrewSense") ~= value then
			player:SetAttribute("CrewSense", value)
		end
		if value then
			run.sensed[player] = true
		else
			run.sensed[player] = nil
		end
	end
	for player in run.sensed do
		if not s.members[player] then
			run.sensed[player] = nil
			if player.Parent then
				player:SetAttribute("CrewSense", nil)
			end
		end
	end
	local interior: Instance? = s.interior
	if interior and interior.Parent and interior:GetAttribute("CrewSense") ~= value then
		interior:SetAttribute("CrewSense", value)
	end
end

-- MoveHelper's helper of a move came / went.
function HelperCrew.joined(h: any)
	local run = runs[h.s]
	if not run then
		run = { h = nil, decided = false, rescue = nil, sensed = {}, told = false }
		runs[h.s] = run
	end
	run.h = h
	stateOf(h)
end

function HelperCrew.left(h: any)
	local run = runs[h.s]
	if run and run.h == h then
		run.h = nil
	end
	local st = states[h]
	if st then
		clearDown(h, st)
		states[h] = nil
	end
end

-- MoveHelper's sync (every move's tick): a run's rescue decided once, Lucy's sense.
function HelperCrew.sync(s: any, h: any)
	if s.ended then
		return
	end
	local run = runs[s]
	if not run then
		run = { h = h, decided = false, rescue = nil, sensed = {}, told = false }
		runs[s] = run
	end
	if h then
		run.h = h
	end
	if isRun(s) and not run.decided then
		local ok, err = pcall(decide :: any, s, run)
		if not ok then
			run.decided = true
			warn(`[HelperCrew] the rescue: {err}`)
		end
	end
	sense(s, run)
end

function HelperCrew.rescueOf(s: any): Rescue?
	local run = runs[s]
	return if run then run.rescue else nil
end

-- ── The lobby's stands ─────────────────────────────────────────────────────

local function dropStand(player: Player)
	local stand = stands[player]
	stands[player] = nil
	if stand then
		Npcs.remove(stand.model)
	end
end

local function standAt(player: Player): CFrame?
	local ok, plot = pcall(function(): any
		return require(script.Parent.SandboxPlots).of(player)
	end)
	if not ok or type(plot) ~= "table" or type(plot.door) ~= "table" then
		return nil
	end
	local L = C.Lobby
	local at = Vector3.new(plot.door.x + L.Stand[1], require(Shared.SandboxMap).GroundTop, plot.door.z + L.Stand[2])
	return CFrame.lookAt(at, at + Vector3.new(0, 0, 1))
end

-- On a move (in the sandbox every move is a run: server/Moving.luau's MoveWith, the owner's UserId on every member).
local function inRun(player: Player): boolean
	return player:GetAttribute("MoveWith") ~= nil
end

-- Your helper by your warehouse (the one who would come into your next run), his Crew prompt yours only.
local function keepStand(player: Player)
	local crew = HelperCrew.crewOf(player)
	local kind = CrewRules.comes(crew, os.time())
	local at = if kind and not inRun(player) then standAt(player) else nil
	local stand = stands[player]
	if not kind or not at then
		dropStand(player)
		return
	end
	if stand and stand.kind == kind and stand.model.Parent then
		return
	end
	dropStand(player)
	local ok, made = pcall(Npcs.spawn, CrewRules.look(kind), at :: CFrame)
	if not ok or typeof(made) ~= "Instance" then
		return
	end
	local model = made :: Model
	model:SetAttribute("CrewKind", kind)
	model:SetAttribute("CrewStand", player.UserId)
	local root = model.PrimaryPart
	if root then
		local def = defOf(kind)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CrewPrompt"
		prompt.ActionText = "Crew"
		prompt.ObjectText = `{def.Icon} {def.Name} · your crew`
		prompt.HoldDuration = 0
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = C.Lobby.Reach
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("MoveOwner", player.UserId) -- (client/CargoPrompts.luau: the others never see it)
		CollectionService:AddTag(prompt, "MovePrompt")
		prompt.Parent = root
		prompt.Triggered:Connect(function(who: Player)
			if who == player then
				HelperCrew.open(player)
			end
		end)
	end
	stands[player] = { kind = kind, model = model }
end

-- The CREW window opens on `player`'s screen (his prompt, his card's CREW).
function HelperCrew.open(player: Player)
	local r = remote
	if r and player.Parent then
		HelperCrew.sendState(player)
		r:FireClient(player, { kind = "open" })
	end
end

-- ── The remote ─────────────────────────────────────────────────────────────

local function onRequest(player: Player, message: any)
	if type(message) ~= "table" or not Net.limit(player, "Crew", Config.Robust.Limits.Crew) then
		return
	end
	local kind = message.kind
	local crew = HelperCrew.crewOf(player)
	if kind == "state" then
		HelperCrew.sendState(player)
	elseif kind == "open" then
		HelperCrew.open(player)
	elseif kind == "pick" then
		local verdict = CrewRules.pickCheck(crew, message.id)
		if verdict == "ok" then
			crew.pick = message.id
			saveSoon(player)
			local def = defOf(message.id)
			local left = CrewRules.hospitalLeft(crew, message.id, os.time())
			say(player, if left > 0 then `{def.Icon} {def.Name} is your pick: {CrewRules.he(message.id)} comes into your runs once out of hospital ({CrewRules.clock(left)}).`
				else `{def.Icon} {def.Name} comes into your runs now.`)
			keepStand(player)
		elseif verdict == "locked" then
			say(player, `🔒 Rescue {defOf(message.id).Name} in a run first: a trapped helper waits in some houses.`)
		end
		HelperCrew.sendState(player)
	elseif kind == "discharge" then
		local id = message.id
		local left = CrewRules.hospitalLeft(crew, id, os.time())
		if type(id) == "string" and CrewRules.has(crew, id) and left > 0 then
			local price = CrewRules.dischargePrice(left)
			local def = defOf(id)
			if PlayerData.spend(player, price, "CrewDischarge", id) then
				crew.hospital[id] = nil
				saveSoon(player)
				say(player, `🏥 {def.Name} is out of hospital and ready (-{CrewRules.money(price)}).`)
				keepStand(player)
			else
				say(player, `Not enough money: discharging {def.Name} costs {CrewRules.money(price)}.`)
			end
		end
		HelperCrew.sendState(player)
	end
end

-- ── The loop ───────────────────────────────────────────────────────────────

local lastStands = 0

function HelperCrew.step(_dt: number)
	local clock = os.clock()
	for s, run in runs do
		if s.ended then
			endRun(s, run)
			continue
		end
		local rescue = run.rescue
		if not rescue then
			continue
		end
		if rescue.freed then
			leave(rescue, clock)
		elseif clock >= rescue.helpAt then
			-- "Help!" now and then while a party player is near (the house is quiet otherwise)
			rescue.helpAt = clock + C.Rescue.Help
			local root = rescue.model.PrimaryPart
			if root then
				for player in s.members do
					local r = rootOf(player)
					if r and (r.Position - root.Position).Magnitude <= C.Rescue.Call then
						Npcs.say(rescue.model, "Help! Over here!", 3)
						break
					end
				end
			end
		end
	end
	if started and clock - lastStands >= C.Lobby.Every then
		lastStands = clock
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(keepStand :: any, player)
			if not ok then
				warn(`[HelperCrew] {player.Name}'s stand: {err}`)
			end
		end
	end
end

function HelperCrew.start()
	if started then
		return
	end
	started = true
	remote = Net.get("Crew")
	;(remote :: RemoteEvent).OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(function(player: Player)
		dropStand(player)
	end)
	task.spawn(function()
		while true do
			local dt = task.wait(0.25)
			local ok, err = pcall(HelperCrew.step :: any, dt or 0.25)
			if not ok then
				warn(`[HelperCrew] {err}`)
			end
		end
	end)
end

return HelperCrew
