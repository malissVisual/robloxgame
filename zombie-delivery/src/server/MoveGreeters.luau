--!strict
-- 7.0, the greeters (the owner: "there will be NPCs who sort of welcome you"): the people who welcome a moving crew, on
-- the server and cheap (server/Npcs.luau's bodies, looks, gestures and speech bubbles; their words shared/
-- MoveStory.luau's greeter section, at most Config.MoveStory.Limits.Bubble characters; the numbers
-- Config.MoveGreeters; tests/movegreeters_runtime_test.luau runs the real module on the moving runtime's fakes):
--   * The client on the porch (a contract whose chapter has a `greeter`: the prologue's Marge, dressed as the depot's
--     dispatcher). From the move's start (its first tick) she stands on the porch of the house beside the front door
--     (Porch: off the path to the kerb, clear of the packed boxes). The first crew member within Hello studs: she turns
--     to them, waves and says her hello lines LineGap s apart, then holds a hand out to the open door ("give"; the
--     "Enter house" prompt is live all along: the door is never locked). Then she reacts now and then, each line Gap s
--     at least after her last: a ★ thing carried within Star studs of her ("Careful with that!": each ★ thing once,
--     StarAgain s apart), the horde (once), the loaded truck driving off (it stood within Leave.Near of the door, then
--     went past Leave.Far with something in it: her thanks, also as the crew's notice: they drive away from her;
--     LeaveAgain s apart). Nothing goes after her: she is no Zombies.extraTargets entry (the zombies go after the
--     players, their cars and those only) and the people's collision group lets zombies pass; she goes at the move's
--     end.
--   * The soldier at the Wall (Soldier): one NPC by the checkpoint's booth (north of its sandbags, off the bay and the
--     people's walk line), always there (the loop makes his body, again if it goes); a move delivered with its truck
--     within Soldier.Greet of the drop-off: he turns to the truck, waves and says MoveStory.Wall.welcome.
--   * Marge at the Moving contracts kiosk: the tutorial's dispatcher (server/Tutorial.luau: the person with the
--     attribute Dispatcher, found by it, so never a second Marge at the depot). A player on foot and on no move who
--     comes within Kiosk.Near of the kiosk's corkboard: she turns to them and says her kiosk line (MoveStory.kioskLine,
--     in turn), her bubble seen from Kiosk.Hear studs (she stands by the job board, across the yard), and the player
--     gets the words as a notice; on coming up to it only, and once per player every Kiosk.Again s. 7.1 review: never into
--     her first day: not to a player whose tutorial is still ahead (the player attribute TutorialPhase, server/
--     Tutorial.luau), nor while her own tutorial bubble or talk is going (her attribute TutorialTalk: the os.clock it
--     lasts until; a player still by the kiosk when it is over gets the line then).
-- server/Moving.luau calls MoveGreeters.start(board) once, MoveGreeters.sync(s) in every tick of a move and
-- MoveGreeters.done(s) in its cleanup; the greeters' own loop (Config.MoveGreeters.Tick) does the kiosk, the soldier's
-- body and any porch left behind by a move that ended.
--   MoveGreeters.start(board)   the loop (board: the kiosk's corkboard, the part Moving hangs its prompt on)
--   MoveGreeters.sync(s)        a move's tick: its client on the porch (made the first time), her lines and reactions
--   MoveGreeters.done(s)        the move ended: she goes; delivered at the Wall: the soldier's welcome
--   MoveGreeters.step()         one step of the loop (the runtime tests call it)
--   MoveGreeters.find(s)        a move's porch greeter (her state: the tests); MoveGreeters.soldier(): his body
--   7.x farm move: Walt greets at his farmhouse's door (NpcLooks.person: his own look, the hat, the check shirt, the
--   moustache); a ★ piece has its own line when the chapter gives one (MoveStory.starLine: "Easy with Thunder's
--   saddle!"); the van counts as by the house at any of the site's doors (a farm's barn doors too).
--   7.x van moves: MoveGreeters.delivered(s)   a trip delivered at the Wall: the soldier's welcome (every trip)
--   8.0 SANDBOX (design/sandbox/KONTRAKT.md): MoveGreeters.start(nil, false): no Wall, so no soldier (his body is never
--   made, no welcome), no kiosk (no board given: the plots' boards have no Marge); the sandbox house has no chapter, so
--   nobody waits on its porch either (MoveStory.greeterOf: nil). Kept light: nothing of the greeters runs there.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cast = require(Shared.Cast)
local Config = require(Shared.Config)
local Map = require(Shared.Map)
local MoveStory = require(Shared.MoveStory)
local Net = require(Shared.Net)
local NpcLooks = require(Shared.NpcLooks)
local Npcs = require(script.Parent.Npcs)

local G = Config.MoveGreeters
local MoveGreeters = {}

-- A line waiting its turn: said at `at` or later (Gap s after the last), with a gesture, turned toward a point.
type Line = { text: string, gesture: string?, toward: Vector3?, at: number, range: number?, notify: boolean? }

export type Porch = {
	s: any, -- server/Moving.luau's Session (read only: contract, site, move, items, truck, members, ended)
	lines: MoveStory.Greeter?, -- nil: nobody greets at this contract's house
	model: Model?,
	spot: Vector3, -- her feet
	facing: Vector3, -- out to the street (the way she stands)
	retryAt: number, -- no body (it went, or could not be made): the next try
	greeted: boolean,
	queue: { Line },
	lastSaid: number,
	said: { string }, -- what she said, in order (the tests)
	starSeen: { [number]: boolean }, -- the ★ things she spoke of
	starAt: number,
	horde: boolean,
	truckNear: boolean, -- the truck stood by the house (its leaving counts after that)
	leaveAt: number,
}

local porches: { [any]: Porch } = {} -- by the move's session
local soldierBody: Model? = nil
local soldierTried = -math.huge -- os.clock of the last try to make his body
local soldierSaid = -math.huge
local dispatcher: Model? = nil -- the tutorial's Marge (server/Tutorial.luau)
local dispatcherLooked = -math.huge
local kioskPart: BasePart? = nil
local nearKiosk: { [Player]: boolean } = {}
local kioskAt: { [Player]: number } = {} -- the player's last kiosk greeting (os.clock)
local kioskCount = 0
local notice = Net.get("Notice")
local started = false
local wall = true -- 8.0 SANDBOX: false: no Wall, no soldier (MoveGreeters.start's second argument)

-- ── Small helpers ──────────────────────────────────────────────────────────

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- A player's living body: its root, or nil.
local function bodyRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function alive(model: Model?): boolean
	return model ~= nil and model.Parent ~= nil
end

-- A person standing with their feet at `feet`, facing along `face` (flat), or nil when the body could not be made.
local function spawnPerson(look: NpcLooks.Look, feet: Vector3, face: Vector3): Model?
	local flatFace = Vector3.new(face.X, 0, face.Z)
	local frame = if flatFace.Magnitude > 0.01 then CFrame.lookAt(feet, feet + flatFace.Unit) else CFrame.new(feet)
	local ok, made = pcall(Npcs.spawn, look, frame)
	if not ok or typeof(made) ~= "Instance" then
		warn(`[MoveGreeters] {look.name} could not be made: {made}`)
		return nil
	end
	return made :: Model
end

-- A line now: turned toward a point for a moment, a gesture with it, the bubble (seen from `range` studs; nil: the
-- people's usual).
local function speak(model: Model, text: string, gesture: string?, toward: Vector3?, range: number?)
	if toward then
		Npcs.glance(model, toward)
	end
	if gesture then
		Npcs.act(model, gesture)
	end
	Npcs.say(model, text, nil, range)
end

-- ── The client on the porch ────────────────────────────────────────────────

-- Where she stands: Porch { x, z } in the door's frame (+X right, -Z out to the street), and the way out.
local function porchSpot(s: any): (Vector3, Vector3)
	local door: Vector3 = s.site.door
	local facing: Vector3 = s.site.facing
	local right = Vector3.new(-facing.Z, 0, facing.X)
	return door + right * G.Porch[1] - facing * G.Porch[2], facing
end

-- The contract's client as their chapter has them (Marge dressed as the depot's dispatcher; 7.x farm move: Walt as
-- himself), the address under the name.
local function clientLook(s: any): NpcLooks.Look
	local chapter = MoveStory.forContract(s.contract.id)
	local person = if chapter then Cast.find(chapter.clientId) else nil
	local name = if person then person.name else tostring(s.contract.client)
	local title = `Client · {s.site.home.address}`
	if person then
		return NpcLooks.person(person.id, person.look, name, title)
	end
	return NpcLooks.look("townsperson", name, title)
end

-- 7.x farm move: how far a point is from the nearest door of the move's site (a farm's barn doors too).
local function fromDoors(s: any, at: Vector3): number
	local best = flat(at, s.site.door)
	for _, door in (if type(s.site.doors) == "table" then s.site.doors else {}) :: { any } do
		best = math.min(best, flat(at, door.door))
	end
	return best
end

local function newPorch(s: any): Porch
	local spot, facing = porchSpot(s)
	return {
		s = s,
		lines = MoveStory.greeterOf(s.contract.id),
		model = nil,
		spot = spot,
		facing = facing,
		retryAt = -math.huge,
		greeted = false,
		queue = {},
		lastSaid = -math.huge,
		said = {},
		starSeen = {},
		starAt = -math.huge,
		horde = false,
		truckNear = false,
		leaveAt = -math.huge,
	}
end

local function queue(p: Porch, line: Line)
	if #p.queue < 6 then -- (never a pile of old news)
		table.insert(p.queue, line)
	end
end

-- The next line in her queue, when it is due (and Gap s after her last one).
local function pump(p: Porch, model: Model, clock: number)
	local line = p.queue[1]
	if not line or clock < line.at or clock - p.lastSaid < G.Gap then
		return
	end
	table.remove(p.queue, 1)
	p.lastSaid = clock
	table.insert(p.said, line.text)
	speak(model, line.text, line.gesture, line.toward, line.range)
	if line.notify then
		for player in p.s.members do
			if player.Parent then
				notice:FireClient(player, `💬 {model.Name}: {line.text}`)
			end
		end
	end
end

-- Her hello to the first crew member within Hello studs: a wave at them, the lines LineGap s apart, the last one with a
-- hand out to the open door.
local function hello(p: Porch, lines: MoveStory.Greeter, clock: number)
	local s = p.s
	local seen: Vector3? = nil
	for player in s.members do
		local root = bodyRoot(player)
		if root and flat(root.Position, p.spot) <= G.Hello then
			seen = root.Position
			break
		end
	end
	if not seen then
		return
	end
	p.greeted = true
	local count = #lines.hello
	for index, text in lines.hello do
		local last = index == count and count > 1
		queue(p, {
			text = text,
			gesture = if index == 1 then "wave" elseif last then "give" else nil,
			toward = if last then s.site.door else seen,
			at = clock + (index - 1) * G.LineGap,
		})
	end
end

-- What she reacts to: a ★ thing carried past her and the loaded truck driving off (after her hello: Danny may carry
-- one out before the crew came to her), the horde.
local function react(p: Porch, lines: MoveStory.Greeter, clock: number)
	local s = p.s
	local move = s.move
	if p.greeted and clock - p.starAt >= G.StarAgain then
		for _, spot in move.order do
			local thing = move.things[spot]
			local item = s.items[spot]
			if thing.star and thing.state == "carried" and not p.starSeen[spot] and item and flat(item.root.Position, p.spot) <= G.Star then
				p.starSeen[spot] = true
				p.starAt = clock
				queue(p, { text = MoveStory.starLine(lines, thing.item), toward = item.root.Position, at = clock }) -- (7.x: its own line)
				break
			end
		end
	end
	if move.phase == "horde" and not p.horde then
		p.horde = true
		queue(p, { text = lines.horde, gesture = "wave", at = clock })
	end
	local truck = s.truck
	local chassis: BasePart? = if truck and not truck.wrecked then truck.chassis else nil
	if chassis and chassis.Parent then
		local away = fromDoors(s, chassis.Position) -- (7.x farm move: by any of its doors)
		if away <= G.Leave.Near then
			p.truckNear = true
		elseif away >= G.Leave.Far and p.truckNear then
			p.truckNear = false
			local loaded = false
			for _, spot in move.order do
				if move.things[spot].state == "truck" then
					loaded = true
					break
				end
			end
			if loaded and p.greeted and clock - p.leaveAt >= G.LeaveAgain then
				p.leaveAt = clock
				queue(p, { text = lines.leave, gesture = "wave", toward = chassis.Position, at = clock, range = G.Leave.Far + 40, notify = true })
			end
		end
	end
end

-- A move's tick (server/Moving.luau, after its crew was synced): its client on the porch, made the first time.
function MoveGreeters.sync(s: any)
	if s.ended then
		MoveGreeters.done(s)
		return
	end
	local p = porches[s]
	if not p then
		p = newPorch(s)
		porches[s] = p
	end
	local porch = p :: Porch
	local lines = porch.lines
	if not lines then
		return
	end
	local clock = os.clock()
	local model = porch.model
	if not alive(model) then
		porch.model = nil
		if clock < porch.retryAt then
			return
		end
		porch.retryAt = clock + G.Respawn
		local made = spawnPerson(clientLook(s), porch.spot, porch.facing)
		if not made then
			return
		end
		made:SetAttribute("MoveGreeter", "porch")
		made:SetAttribute("MoveGreeterOf", s.owner.UserId)
		porch.model = made
		model = made
	end
	if not porch.greeted then
		hello(porch, lines, clock)
	end
	react(porch, lines, clock)
	pump(porch, model :: Model, clock)
end

-- ── The soldier at the Wall ─────────────────────────────────────────────────

local function dropOffAt(): Vector3
	local d = Config.Moving.DropOff
	return Vector3.new(Map.Depot.x + d[1], Map.WalkTop, Map.Depot.z + d[2])
end

-- His body, made (again) when there is none, at most every Respawn s.
local function keepSoldier(clock: number)
	if not wall or alive(soldierBody) or clock - soldierTried < G.Respawn then
		return
	end
	soldierTried = clock
	local drop = dropOffAt()
	local at = drop + Vector3.new(G.Soldier.At[1], 0, G.Soldier.At[2])
	local made = spawnPerson(NpcLooks.look("soldier", G.Soldier.Name, G.Soldier.Title), at, drop - at)
	if made then
		made:SetAttribute("MoveGreeter", "soldier")
	end
	soldierBody = made
end

-- The move ended (server/Moving.luau's cleanup): its client goes; delivered with the truck at the Wall: the soldier
-- turns to it, waves and welcomes it (one welcome at a time: two trucks in together get one).
function MoveGreeters.done(s: any)
	local p = porches[s]
	porches[s] = nil
	if p and p.model then
		Npcs.remove(p.model)
		p.model = nil
	end
	local phase = if type(s.move) == "table" then s.move.phase else nil
	if phase ~= "done" and phase ~= "late" then
		return
	end
	local body = soldierBody
	local truck = s.truck
	local chassis: BasePart? = if truck then truck.chassis else nil
	if not body or not alive(body) or not chassis or flat(chassis.Position, dropOffAt()) > G.Soldier.Greet then
		return
	end
	local clock = os.clock()
	if clock - soldierSaid < G.Gap then
		return
	end
	soldierSaid = clock
	speak(body, MoveStory.Wall.welcome, "wave", chassis.Position, nil)
end

-- 7.x van moves: a trip delivered at the Wall (server/Moving.luau, the move goes on): the soldier turns to the van, waves
-- and welcomes it (one welcome a Gap at most).
function MoveGreeters.delivered(s: any)
	local body = soldierBody
	local truck = s.truck
	local chassis: BasePart? = if truck then truck.chassis else nil
	if not body or not alive(body) or not chassis or flat(chassis.Position, dropOffAt()) > G.Soldier.Greet then
		return
	end
	local clock = os.clock()
	if clock - soldierSaid < G.Gap then
		return
	end
	soldierSaid = clock
	speak(body, MoveStory.Wall.welcome, "wave", chassis.Position, nil)
end

-- ── Marge at the kiosk ─────────────────────────────────────────────────────

-- The tutorial's Marge (the person with the attribute Dispatcher), looked for again at most every Respawn s.
local function findDispatcher(clock: number): Model?
	local found = dispatcher
	if found and alive(found) then
		return found
	end
	dispatcher = nil
	if clock - dispatcherLooked < G.Respawn then
		return nil
	end
	dispatcherLooked = clock
	local folder = workspace:FindFirstChild("Npcs")
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") and child:GetAttribute("Dispatcher") == true then
				dispatcher = child
				return child
			end
		end
	end
	return nil
end

-- A player on foot and on no move who comes up to the kiosk: her line (once per player every Kiosk.Again s).
local function kiosk(clock: number)
	local board = kioskPart
	if not board or not board.Parent then
		return
	end
	local center = board.Position
	for player in nearKiosk do
		if not player.Parent then
			nearKiosk[player] = nil
		end
	end
	for _, player in Players:GetPlayers() do
		local root = bodyRoot(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local near = root ~= nil and humanoid ~= nil and humanoid.SeatPart == nil and flat(root.Position, center) <= G.Kiosk.Near
		local was = nearKiosk[player] == true
		if near then
			nearKiosk[player] = true
		else
			nearKiosk[player] = nil
		end
		if not near or was or not root or player:GetAttribute("MoveWith") ~= nil then
			continue
		end
		if player:GetAttribute("TutorialPhase") ~= nil then
			continue -- (7.1 review: their first day with her is on: no moving pitch into it)
		end
		if clock - (kioskAt[player] or -math.huge) < G.Kiosk.Again then
			continue
		end
		local marge = findDispatcher(clock)
		if marge and (tonumber(marge:GetAttribute("TutorialTalk")) or -math.huge) > clock then
			nearKiosk[player] = nil -- (7.1 review: her tutorial talk goes on: asked again next step while they stay)
			continue
		end
		if marge then
			kioskAt[player] = clock
			kioskCount += 1
			local text = MoveStory.kioskLine(kioskCount)
			speak(marge, text, "wave", root.Position, G.Kiosk.Hear)
			notice:FireClient(player, `💬 {marge.Name}: {text}`)
		end
	end
end

-- ── The loop ───────────────────────────────────────────────────────────────

function MoveGreeters.step()
	local clock = os.clock()
	keepSoldier(clock)
	kiosk(clock)
	local ended: { any } = {}
	for s in porches do
		if s.ended then
			table.insert(ended, s)
		end
	end
	for _, s in ended do
		MoveGreeters.done(s)
	end
end

function MoveGreeters.find(s: any): Porch?
	return porches[s]
end

function MoveGreeters.soldier(): Model?
	return soldierBody
end

-- `withWall` false (8.0 SANDBOX): no soldier at the Wall (nil: the city's, he stands there).
function MoveGreeters.start(board: BasePart?, withWall: boolean?)
	kioskPart = board
	wall = withWall ~= false
	if started then
		return
	end
	started = true
	Players.PlayerRemoving:Connect(function(player: Player)
		nearKiosk[player] = nil
		kioskAt[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(G.Tick)
			local ok, err = pcall(function()
				MoveGreeters.step()
			end)
			if not ok then
				warn(`[MoveGreeters] {err}`)
			end
		end
	end)
end

return MoveGreeters
