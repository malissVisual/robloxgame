--!strict
-- 7.0 prototype, MOVES (the owner's rework, design/rework/NAVRH.md): one house move, run on the server. The rules are
-- shared/MovingRules.luau's (pure, tests/moving_test.luau), the numbers Config.Moving's, the client's side
-- client/MovingHud.luau (and client/Fade.luau). The old game stays as it was beside it.
--
--   * The contract: the depot's "Moving contracts" board (Config.Moving.Board) or the admin panel opens the contract
--     card (the Moving remote's "contract": the house, its ★ things, the pay, the time); its START (checked here: the
--     card was opened within CardFor s, near the board or by an admin; no job, no other move, a free interior slot)
--     builds the house's interior far away (server/HouseInterior.luau build at its slot(n), the plan shared/
--     HouseLayout.luau's, the furniture shared/FurnitureLooks.luau's: found by name when first needed, see artNow) and
--     lends the company's Moving Truck (Config.Moving.Truck) right next to the owner, who sits in it; the GPS shows
--     the house (the prologue: Marge's, 155 Willow Ln, Config.Moving.Contracts).
--   * The crew: the owner's crew (server/Crew.luau Crew.members) is on the move with them, joining or leaving any time
--     (the player attribute MoveWith = the owner's UserId while you are; client/MovingHud.luau shows only the prompts
--     of your own move: the tag MovePrompt with MoveOwner / MoveOnly / MoveSkip).
--   * The door: "Enter house" at the contract's front door (one prompt: it takes you into YOUR move's interior) fades
--     out (the "fade" message), streams the interior in (RequestStreamAroundAsync), moves you (and what you carry, and
--     the other end of a pair thing) to the plan's entry and fades in; "Leave house" by the door inside the other way.
--   * The things: "Pick up" (hand, both) / "Lift" (pair) on every thing, "Help lift" on a pair thing somebody lifted,
--     "Put down" / "Let go" (G, or the touch PUT DOWN: the PutDown remote) for whoever holds it. In the hands it is
--     welded in front of the chest like a cargo piece (the character attributes Carrying, CarryCount, CarryHands,
--     CarryAt, CarrySize, CarrySpeed and MoveCarry = the spot: client/CameraRig.luau walks at CarrySpeed with
--     MoveCarry, client/ArmPose.luau reaches for it); a pair thing alone is dragged low in front, slowly. Its condition
--     drops when its carrier falls from a height, is bitten, dies (it drops), and in the truck when the truck is hit;
--     its helper too far from it for Grace s, it goes down. Moving faster than the carry allows (a teleport) puts it
--     down where its carrier was.
--   * The truck: "Load" (E) at its open back puts what you hold onto the bed (MovingRules' packer: first-fit, turned
--     90° when that fits, stacked flat; "No room — unload something or bring a bigger truck"), welded in the box where
--     it is seen through the open back; "Unload" (Z) takes the last one in that nothing rests on back into your hands.
--     The back is the owner's and the crew's (Vehicles.backAllowed, BackCrew); its own prompt waits while Load shows
--     (one E at a time).
--   * The clock: Config.Moving.Time; at HordeAt left the horde (Zombies.spawn + Zombies.march to the door, in bursts);
--     a few roaming zombies round the house while somebody is outside near it; none inside (the crew on a move is
--     "hunted" like a job's: no ordinary roamers come round them anywhere). The truck within DropRadius of the
--     depot's drop-off (the Wall) with a load ends the move: the pay (MovingRules.result) split among the crew within
--     Present studs (Economy.crewSplit, "MovePay"), XP, the result card ("result"), analytics (MoveDone). At 0:00 it
--     ends late (the load paid at LateShare). GIVE UP (the owner) or the owner leaving calls it off; a wrecked or lost
--     truck loses it.
--   * The edges: whoever leaves, dies, sits down or leaves the crew drops what they hold where they are (inside: on the
--     floor); somebody inside an interior that goes is brought out to the door; every prompt and request is checked
--     here (who, how far, the state), the remote is rate limited (Config.Robust.Limits.Moving).
--   Moving.start()            builds the board, the drop-off and the doors, wires the hooks (after Main's own)
--   Moving.admin(player, arg) the admin panel's MOVES buttons: "card" | "start" | "house" | "horde" | "time" | "deliver"
--                             | "end"; returns what to say
--   Moving.useArt(art)        the art modules given (a test or a fallback), instead of finding them by name
--   Moving.step()             one tick of every move (the loop's; tests/moving_runtime_test.luau runs the real module)
--   Moving.helperTake / helperDrop / helperLoad / helperHurt   7.0: the depot's helper's hands (server/MoveHelper.luau:
--                             Danny joins a crew of one; MoveHelper.sync in the tick)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local Rules = require(Shared.MovingRules)
local Crew = require(script.Parent.Crew)
local MoveHelper = require(script.Parent.MoveHelper) -- 7.0: the depot's helper (Danny) for a crew of one
local PlayerData = require(script.Parent.PlayerData)
local Vehicles = require(script.Parent.Vehicles)
local Zombies = require(script.Parent.Zombies)

local T = Config.Moving
local Moving = {}

local remote = Net.get("Moving")
local notice = Net.get("Notice")
local TAG = "MovePrompt" -- client/MovingHud.luau shows a tagged prompt only to the players it is for
local CARRY_ATTRIBUTES = { "Carrying", "CarryCount", "CarryHands", "CarryAt", "CarrySize", "CarrySpeed", "MoveCarry" }

-- The art (another branch builds it): shared/FurnitureLooks.luau (Items, build), shared/HouseLayout.luau (plan),
-- server/HouseInterior.luau (build, slot, destroy).
export type Art = { looks: any, layout: any, interior: any }
type Contract = { id: string, name: string, client: string, icon: string, home: string, seed: number, kind: string, blurb: string }

type Site = {
	contract: Contract,
	home: Map.Home,
	door: Vector3, -- the front door's foot, outside
	facing: Vector3, -- out of the door
	outside: CFrame, -- where you come out
	model: Model,
}

type Item = {
	spot: number,
	model: Model,
	root: BasePart,
	home: CFrame, -- where it stood in the interior
	pick: ProximityPrompt,
	help: ProximityPrompt,
	down: { ProximityPrompt }, -- the holders' G
	weld: WeldConstraint?,
	hooks: { RBXScriptConnection },
	health: { [Player]: number }, -- its holders' health a moment ago (a bite takes a share)
	lastAt: Vector3?, -- the pace check: its carrier's last place …
	lastTime: number, -- … and when
	apartSince: number?, -- its helper too far since
	fallFrom: number?, -- its carrier is falling from this high
}

type Session = {
	id: number,
	owner: Player,
	contract: Contract,
	site: Site,
	move: Rules.Move,
	plan: any,
	origin: CFrame,
	slot: number,
	interior: Model?,
	items: { [number]: Item },
	exit: BasePart?,
	truck: Vehicles.Car?,
	load: ProximityPrompt?,
	unload: ProximityPrompt?,
	horde: { Zombies.Zombie },
	roam: { Zombies.Zombie },
	nextRoam: number,
	bursts: number,
	nextBurst: number,
	members: { [Player]: boolean },
	inside: { [Player]: boolean },
	dirty: boolean,
	sentAt: number,
	ended: boolean,
	emptyWarned: number,
}

local art: Art? = nil
local sessions: { [Player]: Session } = {} -- by owner
local slots: { [number]: Session } = {}
local sites: { [string]: Site } = {}
local armed: { [Player]: { at: number, admin: boolean } } = {} -- the contract card was opened (START is good a while)
local traveling: { [Player]: boolean } = {}
local folder: Folder? = nil
local boardPart: BasePart? = nil
local nextId = 0
local jobs: any = nil -- server/Jobs.luau (required in start: Jobs.active)

-- ── Small helpers ──────────────────────────────────────────────────────────

local function now(): number
	return workspace:GetServerTimeNow()
end

local function say(player: Player, text: string)
	if player.Parent then
		notice:FireClient(player, text)
	end
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- A player's living body on foot or seated: (character, humanoid, root) or nils.
local function bodyOf(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

-- The same for a player who may be nil.
local function bodyOrNil(player: Player?): (Model?, Humanoid?, BasePart?)
	if not player then
		return nil, nil, nil
	end
	return bodyOf(player)
end

local function contractById(id: any): Contract?
	for _, contract in T.Contracts do
		if contract.id == id then
			return contract
		end
	end
	return nil
end

local function moduleNamed(parent: Instance, name: string): ModuleScript?
	local found = parent:FindFirstChild(name)
	return if found and found:IsA("ModuleScript") then found else nil
end

-- The art modules, found by name the first time they are needed (nil: not in this place yet: no move starts).
local function artNow(): Art?
	if art then
		return art
	end
	local looksModule = moduleNamed(Shared, "FurnitureLooks")
	local layoutModule = moduleNamed(Shared, "HouseLayout")
	local interiorModule = moduleNamed(script.Parent, "HouseInterior")
	if not looksModule or not layoutModule or not interiorModule then
		return nil
	end
	local ok, loaded = pcall(function(): Art
		return { looks = require(looksModule) :: any, layout = require(layoutModule) :: any, interior = require(interiorModule) :: any }
	end)
	if not ok then
		warn(`[Moving] the house art failed to load: {loaded}`)
		return nil
	end
	art = loaded
	return loaded
end

function Moving.useArt(given: Art)
	art = given
end

-- The furniture as MovingRules' defs (FurnitureLooks.Items; a Vector3 size as plain numbers).
local function defsOf(a: Art): { [string]: Rules.ItemDef }
	local defs: { [string]: Rules.ItemDef } = {}
	for key, item in (a.looks.Items :: { [string]: any }) do
		local size = item.size
		if typeof(size) ~= "Vector3" then
			continue
		end
		local id = if type(item.id) == "string" then item.id else key
		defs[key] = {
			id = id,
			name = if type(item.name) == "string" then item.name else id,
			icon = if type(item.icon) == "string" then item.icon else "📦",
			size = { X = size.X, Y = size.Y, Z = size.Z },
			class = if type(item.class) == "string" then item.class else "both",
			weight = tonumber(item.weight) or 5,
			value = tonumber(item.value) or 0,
			fragile = item.fragile == true,
			room = if type(item.room) == "string" then item.room else "",
		}
	end
	return defs
end

local function spotsOf(plan: any): { Rules.Spot }
	local list: { Rules.Spot } = {}
	for _, spot in (plan.spots :: { any }) do
		if type(spot.id) == "number" and type(spot.item) == "string" then
			table.insert(list, { id = spot.id, item = spot.item, room = tostring(spot.room), star = spot.star == true })
		end
	end
	return list
end

-- The session this player works on: their own, or their crew's owner's.
local function sessionOf(player: Player): Session?
	local own = sessions[player]
	if own and not own.ended then
		return own
	end
	local owner = Crew.ownerOf(player)
	local theirs = if owner then sessions[owner] else nil
	return if theirs and not theirs.ended then theirs else nil
end

local function membersOf(s: Session): { Player }
	local list: { Player } = { s.owner }
	for _, member in Crew.members(s.owner) do
		table.insert(list, member)
	end
	return list
end

-- Everybody on the move now or at the last tick (server/Crew.luau may have broken the crew up already when its owner
-- leaves: they still hear the end).
local function everyone(s: Session): { Player }
	local list = membersOf(s)
	for player in s.members do
		if player.Parent and not table.find(list, player) then
			table.insert(list, player)
		end
	end
	return list
end

local function tellAll(s: Session, text: string)
	for _, player in everyone(s) do
		say(player, text)
	end
end

-- ── MoveStory hook (7.0 story, shared/MoveStory.luau) ───────────────────────────────────────────────────────────────
-- Marge's texts on the crew's phones (the Tutorial remote's "message": client/Phone.luau's MESSAGES): at START her
-- word on the ★ things (`how` nil), at the end her debrief for the outcome (`how`: the phase, `stars`: the rating).
-- A contract without a chapter says nothing. Called twice: startMove and finish.
local MoveStory = require(Shared.MoveStory)
local function storyText(s: Session, how: string?, stars: number?)
	local text = if how then MoveStory.debriefText(s.contract.id, how, stars) else MoveStory.dispatchText(s.contract.id)
	if text then
		for _, player in everyone(s) do
			Net.get("Tutorial"):FireClient(player, "message", { from = MoveStory.Sender, text = text })
		end
	end
end
-- ── (end of the MoveStory hook) ──────────────────────────────────────────────────────────────────────────────────────

local function playerById(id: number?): Player?
	return if id then Players:GetPlayerByUserId(id) else nil
end

local function labelOf(thing: Rules.Thing): string
	return `{thing.icon} {thing.name}{if thing.star then " ★" else ""}`
end

local function tag(prompt: ProximityPrompt, owner: Player)
	prompt:SetAttribute("MoveOwner", owner.UserId)
	CollectionService:AddTag(prompt, TAG)
end

local function newPrompt(parent: Instance, action: string, object: string, key: Enum.KeyCode, hold: number, reach: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = key
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = reach
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

local function invisible(name: string, size: Vector3, frame: CFrame, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = frame
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Parent = parent
	return part
end

-- ── The places: the board, the drop-off, the houses' doors ─────────────────
-- (their art: server/MoveSites.luau, shared/MoveSiteLooks.luau; the prompts and the rules stay here)

local function dropOffAt(): Vector3
	return Vector3.new(Map.Depot.x + T.DropOff[1], Map.WalkTop, Map.Depot.z + T.DropOff[2])
end

local function buildBoard(parent: Instance)
	-- the "MovingBoard" kiosk (server/MoveSites.luau, Persistent, facing the yard: the corkboard with the houses' photos
	-- and the notices, its lamp, the ZDC logo); the prompt hangs on its corkboard
	local _, board = require(script.Parent.MoveSites).board(parent)
	local prompt = newPrompt(board, "Moving contracts", "ZDC Moving", Enum.KeyCode.E, 0, T.Reach.Board)
	prompt.Triggered:Connect(function(player: Player)
		local _, _, root = bodyOf(player)
		if root and flat(root.Position, board.Position) <= T.Reach.Board + 4 then
			Moving.openCard(player, nil, false)
		end
	end)
	boardPart = board
end

-- The drop-off at the depot ("the Wall"): the army's checkpoint round its bay (server/MoveSites.luau, Persistent: the
-- bay's orange outline as before, the gantry's SAFE ZONE sign, the Wall's stubs, the booth, the raised barrier, the
-- floodlights, the army truck; nothing in the truck's way in from Bone St), and with it the rework's dressing (the
-- depot's ZDC MOVING & EVACUATION banner, the evacuation spots in the city).
local function buildDropOff(parent: Instance)
	local sites = require(script.Parent.MoveSites)
	sites.dropOff(parent)
	sites.dressing(parent)
end

local onEnter: (Player, string) -> ()

-- A contract's house: the "Enter house" prompt at its front door and its moving-day dress-up outside (the rest of the
-- house stays as server/World.luau built it).
local function buildSite(contract: Contract, parent: Instance): Site?
	local home = Map.home(contract.home)
	if not home then
		warn(`[Moving] {contract.id}: no home {contract.home} on the map`)
		return nil
	end
	local facing = Vector3.new(home.facing.x, 0, home.facing.z)
	local door = Vector3.new(home.door.x, Map.WalkTop, home.door.z)
	local model = Instance.new("Model")
	model.Name = `Move_{contract.id}`
	local up = Vector3.new(0, 3.5, 0)
	local spot = invisible("EnterDoor", Vector3.new(4, 6, 1), CFrame.lookAt(door + facing * 0.9 + up, door + facing * 3 + up), model)
	local prompt = newPrompt(spot, "Enter house", `{contract.icon} {contract.name}`, Enum.KeyCode.E, 0, T.Reach.Door)
	prompt.Triggered:Connect(function(player: Player)
		onEnter(player, contract.id)
	end)
	-- (server/MoveSites.luau: the ZDC MOVING yard sign left of the path, boxes by the door, MOVING DAY over it, cones at
	-- the truck's kerb, the EVACUATED realtor's sign; nothing solid, nothing on the path to the kerb)
	model.PrimaryPart = require(script.Parent.MoveSites).house(model, contract.name, home)
	model.Parent = parent
	local out = door + facing * 4 + Vector3.new(0, 0.1, 0)
	return {
		contract = contract,
		home = home,
		door = door,
		facing = facing,
		outside = CFrame.lookAt(out, out + facing),
		model = model,
	}
end

-- ── The carry ──────────────────────────────────────────────────────────────

local function clearHands(player: Player?)
	local character = player and player.Character
	if character and character:GetAttribute("MoveCarry") ~= nil then
		for _, name in CARRY_ATTRIBUTES do
			character:SetAttribute(name, nil)
		end
	end
end

-- Where a thing sits from its carrier's root: in front of the chest (MovingRules' mode "drag": low, a step ahead).
local function holdOffset(thing: Rules.Thing, mode: string, root: BasePart, humanoid: Humanoid): CFrame
	local size = thing.size
	local tune = Config.Cargo
	if mode == "drag" then
		local feet = -(root.Size.Y / 2 + humanoid.HipHeight)
		return CFrame.new(0, feet + size.Y / 2 + 0.2, -(tune.CarryFront + 1.2 + size.Z / 2))
	end
	return CFrame.new(0, tune.CarryLow + size.Y / 2, -(tune.CarryFront + size.Z / 2))
end

local function setParts(model: Model, anchored: boolean, carried: boolean, root: BasePart)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = anchored
			part.Massless = carried
			if part == root then
				part.CanCollide = not carried
			elseif carried then
				part.CanCollide = false
			end
		end
	end
end

local function unweld(item: Item)
	local weld = item.weld
	if weld then
		weld:Destroy()
		item.weld = nil
	end
end

-- Welds the thing to `holder` at `frame` (its middle), carried (massless, not colliding).
local function weldTo(item: Item, holder: BasePart, frame: CFrame)
	unweld(item)
	setParts(item.model, true, true, item.root)
	item.model:PivotTo(frame)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = holder
	weld.Part1 = item.root
	weld.Parent = item.root
	item.weld = weld
	setParts(item.model, false, true, item.root)
end

-- The holders' attributes for the thing now (its mode: the walk, the hands).
local function setHands(s: Session, item: Item)
	local thing = s.move.things[item.spot]
	local mode = Rules.mode(thing)
	local speed = Rules.carrySpeed(Config.Movement.Walk, mode, thing.weight)
	local carrier = playerById(thing.carrier)
	local _, humanoid, root = bodyOrNil(carrier)
	local character = carrier and carrier.Character
	if character and humanoid and root then
		character:SetAttribute("Carrying", if mode == "hand" then "crate" else "furniture")
		character:SetAttribute("CarryCount", 1)
		character:SetAttribute("CarryHands", Rules.hands(mode))
		character:SetAttribute("CarryAt", holdOffset(thing, mode, root, humanoid).Position)
		character:SetAttribute("CarrySize", Vector3.new(thing.size.X, thing.size.Y, thing.size.Z))
		character:SetAttribute("CarrySpeed", speed)
		character:SetAttribute("MoveCarry", item.spot)
	end
	local helper = playerById(thing.helper)
	local helperBody = helper and helper.Character
	if helperBody then
		helperBody:SetAttribute("Carrying", "furniture")
		helperBody:SetAttribute("CarryCount", 1)
		helperBody:SetAttribute("CarryHands", 2)
		helperBody:SetAttribute("CarryAt", nil)
		helperBody:SetAttribute("CarrySize", nil)
		helperBody:SetAttribute("CarrySpeed", speed)
		helperBody:SetAttribute("MoveCarry", item.spot)
	end
end

local hurtThing: (Session, number, number) -> ()
local release: (Session, Player, string) -> ()

-- The holders' hooks and G prompts made again (after any change of who holds it).
local function rewire(s: Session, item: Item)
	for _, hook in item.hooks do
		hook:Disconnect()
	end
	table.clear(item.hooks)
	for _, prompt in item.down do
		prompt:Destroy()
	end
	table.clear(item.down)
	table.clear(item.health)
	local thing = s.move.things[item.spot]
	item.pick.Enabled = thing.state == "home" or thing.state == "ground"
	item.help.Enabled = thing.state == "carried" and thing.class == "pair" and thing.helper == nil
	item.help:SetAttribute("MoveSkip", thing.carrier)
	if thing.state ~= "carried" then
		return
	end
	for _, id in { thing.carrier, thing.helper } do
		local player = playerById(id)
		local character, humanoid, root = bodyOrNil(player)
		if not player or not character or not humanoid or not root then
			continue
		end
		local holder: Player = player
		local isCarrier = id == thing.carrier
		local down = newPrompt(item.root, if isCarrier then "Put down" else "Let go", labelOf(thing), Enum.KeyCode.G, 0, 6)
		down.GamepadKeyCode = Enum.KeyCode.ButtonB
		down:SetAttribute("MoveOnly", holder.UserId)
		tag(down, s.owner)
		table.insert(item.down, down)
		table.insert(item.hooks, down.Triggered:Connect(function(by: Player)
			if by == holder then
				release(s, holder, "put")
			end
		end))
		local function lost(why: string)
			if not s.ended and (thing.carrier == holder.UserId or thing.helper == holder.UserId) then
				release(s, holder, why)
			end
		end
		table.insert(item.hooks, humanoid.Died:Connect(function()
			lost("died")
		end))
		table.insert(item.hooks, humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			if humanoid.SeatPart ~= nil then
				lost("seat")
			end
		end))
		table.insert(item.hooks, character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(workspace) then
				lost("gone")
			end
		end))
		-- a bite (any health lost) knocks it
		item.health[holder] = humanoid.Health
		table.insert(item.hooks, humanoid.HealthChanged:Connect(function(health: number)
			local before = item.health[holder] or health
			item.health[holder] = health
			if health < before and health > 0 then
				hurtThing(s, item.spot, Rules.hitDamage(before - health, thing.fragile))
			end
		end))
		if isCarrier then
			-- a fall from a height jolts it (the highest point of the fall: the tick keeps it)
			table.insert(item.hooks, humanoid.StateChanged:Connect(function(_, state: Enum.HumanoidStateType)
				if state == Enum.HumanoidStateType.Freefall then
					item.fallFrom = root.Position.Y
				elseif state == Enum.HumanoidStateType.Landed or state == Enum.HumanoidStateType.Running then
					local from = item.fallFrom
					item.fallFrom = nil
					if from then
						hurtThing(s, item.spot, Rules.fallDamage(from - root.Position.Y, thing.fragile))
					end
				end
			end))
		end
	end
end

-- Into the carrier's arms (or dragged), welded to their root.
local function carry(s: Session, item: Item)
	local thing = s.move.things[item.spot]
	local carrier = playerById(thing.carrier)
	local _, humanoid, root = bodyOrNil(carrier)
	if not carrier or not humanoid or not root then
		return
	end
	local mode = Rules.mode(thing)
	item.model.Parent = folder -- (out of the interior's model: it goes where its carrier goes)
	weldTo(item, root, root.CFrame * holdOffset(thing, mode, root, humanoid))
	item.lastAt, item.lastTime, item.apartSince, item.fallFrom = nil, 0, nil, nil
	setHands(s, item)
	rewire(s, item)
	pcall(function()
		require(script.Parent.Hand).holster(carrier, true) -- (no gun in the hand with a thing in your arms)
	end)
end

-- Set down on the floor under where it is now (its turn kept); returns how far it fell onto it. No floor under it (out
-- of the world): back at its spot in the house.
local function settle(item: Item, thing: Rules.Thing, at: CFrame): number
	unweld(item)
	setParts(item.model, true, false, item.root)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { item.model }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(at.Position + Vector3.new(0, 1, 0), Vector3.new(0, -80, 0), params)
	if not hit then
		item.model:PivotTo(item.home)
		return 0
	end
	local bottom = at.Position.Y - thing.size.Y / 2
	local floor = hit.Position.Y
	local _, yaw = at:ToOrientation()
	item.model:PivotTo(CFrame.new(at.X, floor + thing.size.Y / 2, at.Z) * CFrame.Angles(0, yaw, 0))
	return bottom - floor
end

-- `player` lets go of what they hold. why: "put" (G), "died", "seat", "gone" (left), "apart" (the pair too far
-- apart), "pace" (too fast), "left" (out of the crew), "end". The carrier sets it down (the helper's end too); a helper
-- lets go of their end only (the carrier drags it on), but a pair torn apart goes down whole.
release = function(s: Session, player: Player, why: string)
	local spot, role = Rules.holding(s.move, player.UserId)
	if not spot then
		return
	end
	local item = s.items[spot]
	local thing = s.move.things[spot]
	local apart = why == "apart"
	if role == "helper" and not apart then
		Rules.release(s.move, player.UserId)
		clearHands(player)
		if item then
			local carrier = playerById(thing.carrier)
			if carrier and why ~= "end" then
				say(carrier, `{player.DisplayName} let go: you drag the {thing.name} alone now.`)
			end
			carry(s, item) -- (dragged again: the carrier's weld and walk)
		end
		s.dirty = true
		return
	end
	local carrier = playerById(thing.carrier)
	local helper = playerById(thing.helper)
	local at = if item then item.root.CFrame else nil
	if why == "pace" and item and item.lastAt then
		at = CFrame.new(item.lastAt) * (if at then at.Rotation else CFrame.identity)
	end
	Rules.release(s.move, thing.carrier or player.UserId)
	clearHands(carrier)
	clearHands(helper)
	if item and at then
		for _, hook in item.hooks do
			hook:Disconnect()
		end
		table.clear(item.hooks)
		local fell = settle(item, thing, at)
		rewire(s, item)
		if why == "died" then
			hurtThing(s, spot, Rules.deathDamage(thing.fragile))
		elseif why == "put" then
			hurtThing(s, spot, Rules.fallDamage(fell, thing.fragile))
		end
	end
	if apart then
		for _, who in { carrier, helper } do
			if who then
				say(who, `Too far apart: the {thing.name} went down. Stay close when you carry it together.`)
			end
		end
	elseif why == "pace" and carrier then
		say(carrier, `Too fast with the {thing.name}: it went down where you were.`)
	end
	s.dirty = true
end

hurtThing = function(s: Session, spot: number, share: number)
	local thing = s.move.things[spot]
	if not thing or share <= 0 or s.ended then
		return
	end
	local before = thing.condition
	local broke = Rules.hurt(thing, share)
	s.dirty = true
	if broke then
		tellAll(s, `💥 The {thing.name} broke! It pays nothing now.`)
	elseif before - thing.condition >= 0.1 then
		local holder = playerById(thing.carrier)
		if holder then
			say(holder, `⚠ The {thing.name} took a knock: {math.floor(thing.condition * 100 + 0.5)}% left.`)
		end
	end
end

-- ── The truck ──────────────────────────────────────────────────────────────

local function truckOk(s: Session): Vehicles.Car?
	local truck = s.truck
	if truck and not truck.wrecked and truck.model.Parent and Vehicles.get(s.owner) == truck then
		return truck
	end
	return nil
end

-- The bed's place in the truck's chassis frame: (its middle at the floor, from MovingRules.where's numbers).
local function bedFrame(truck: Vehicles.Car, x: number, y: number, z: number, turned: boolean): CFrame
	local slots = Vehicles.cargoSlots(truck)
	local floor = if slots[1] then slots[1].Position.Y else 0.6
	local turn = if turned then CFrame.Angles(0, math.rad(90), 0) else CFrame.identity
	return truck.chassis.CFrame * CFrame.new(T.Bed.Center[1] + x, floor + y, T.Bed.Center[2] + z) * turn
end

local function stow(s: Session, item: Item, at: Rules.Placement)
	local truck = truckOk(s)
	if not truck then
		return
	end
	local x, y, z = Rules.where(s.move.packing, at)
	for _, hook in item.hooks do
		hook:Disconnect()
	end
	table.clear(item.hooks)
	weldTo(item, Vehicles.cargoHolder(truck), bedFrame(truck, x, y, z, at.turned))
	rewire(s, item)
end

-- Near the truck's open back, on foot, the truck standing: (ok, what to say).
local function atBack(s: Session, player: Player): (boolean, string?)
	local truck = truckOk(s)
	local door = truck and Vehicles.cargoDoor(truck)
	local _, humanoid, root = bodyOf(player)
	if not truck or not door or not humanoid or not root then
		return false, nil
	end
	if humanoid.SeatPart then
		return false, "Get out first."
	elseif flat(root.Position, door.WorldPosition) > T.Reach.Truck + 3 then
		return false, nil
	elseif not Vehicles.backOpen(truck) then
		return false, `Open the back first (E): {Vehicles.backVerb(truck, true)}.`
	elseif Vehicles.speed(truck) > Config.Cargo.MaxCarSpeed then
		return false, "Stop the truck first."
	end
	return true, nil
end

local function onLoad(s: Session, player: Player)
	if s.ended or sessionOf(player) ~= s then
		return
	end
	local ok, why = atBack(s, player)
	if not ok then
		if why then
			say(player, why)
		end
		return
	end
	local spot = Rules.holding(s.move, player.UserId)
	local thing = if spot then s.move.things[spot] else nil
	local helper = if thing then playerById(thing.helper) else nil
	local at, refused = Rules.load(s.move, player.UserId)
	if not at or not spot or not thing then
		say(player, Rules.whyText(refused))
		return
	end
	clearHands(player)
	clearHands(helper)
	local item = s.items[spot]
	if item then
		stow(s, item, at)
	end
	local c = Rules.counts(s.move)
	say(player, `{labelOf(thing)} loaded · {c.out}/{c.total} out · truck {math.floor(Rules.fill(s.move.packing) * 100 + 0.5)}% full`)
	s.dirty = true
end

local function onUnload(s: Session, player: Player)
	if s.ended or sessionOf(player) ~= s then
		return
	end
	local ok, why = atBack(s, player)
	if not ok then
		if why then
			say(player, why)
		end
		return
	end
	local spot, refused = Rules.unload(s.move, player.UserId)
	if not spot then
		say(player, Rules.whyText(refused))
		return
	end
	local item = s.items[spot]
	if item then
		carry(s, item)
	end
	s.dirty = true
end

local function truckPrompts(s: Session)
	local truck = truckOk(s)
	local door = truck and Vehicles.cargoDoor(truck)
	if not truck or not door then
		return
	end
	local load = newPrompt(door, "Load", "Moving truck", Enum.KeyCode.E, 0.25, T.Reach.Truck)
	local unload = newPrompt(door, "Unload", "Moving truck", Enum.KeyCode.Z, 0.4, T.Reach.Truck)
	unload.GamepadKeyCode = Enum.KeyCode.ButtonY
	load.Enabled, unload.Enabled = false, false
	tag(load, s.owner)
	tag(unload, s.owner)
	load.Triggered:Connect(function(player: Player)
		onLoad(s, player)
	end)
	unload.Triggered:Connect(function(player: Player)
		onUnload(s, player)
	end)
	s.load, s.unload = load, unload
end

-- The truck's prompts as things stand: Load while somebody of the crew carries a thing (the back's own E waits
-- then), Unload while one may come out; the back for the crew too (BackCrew).
local function refreshTruck(s: Session)
	local truck = truckOk(s)
	local load, unload = s.load, s.unload
	if not truck or not load or not unload then
		return
	end
	local open = Vehicles.backOpen(truck)
	local carried: Rules.Thing? = nil
	local carriers = 0
	for _, spot in s.move.order do
		local thing = s.move.things[spot]
		if thing.state == "carried" and playerById(thing.carrier) then -- (7.0 helper: not what Danny carries)
			carriers += 1
			carried = thing
		end
	end
	local fill = math.floor(Rules.fill(s.move.packing) * 100 + 0.5)
	load.Enabled = open and carriers > 0
	load.ActionText = if carriers == 1 and carried then `Load {carried.name}` else "Load"
	load.ObjectText = `Moving truck · {fill}% full`
	local out = Rules.lastOut(s.move)
	unload.Enabled = open and out ~= nil
	unload.ActionText = if out then `Unload {s.move.things[out].name}` else "Unload"
	unload.ObjectText = `Moving truck · {fill}% full`
	local back = Vehicles.backPrompt(truck)
	if back then
		back.Enabled = not load.Enabled
	end
	local ids: { string } = {}
	for _, member in Crew.members(s.owner) do
		table.insert(ids, tostring(member.UserId))
	end
	local crew = if #ids > 0 then table.concat(ids, ",") else nil
	if truck.model:GetAttribute("BackCrew") ~= crew then
		truck.model:SetAttribute("BackCrew", crew)
	end
end

-- ── 7.0: the depot's helper's hands (server/MoveHelper.luau) ──────────────
-- Danny ("Danny from the depot", an NPC for a crew of one) does what a player's hands do through these, with the same
-- rules, welds and damage. `npc` is his body; its attribute MoveHelper is his id in the rules (a negative number: no
-- player has it, so the player-only paths above leave him alone: no G prompt, no pace or apart check, no Load prompt).
-- Server/MoveHelper.luau checks how near he is; these check the rules.

local function helperIdOf(npc: Model): number?
	local id = npc:GetAttribute("MoveHelper")
	return if type(id) == "number" then id else nil
end

-- A holder's name for the list: a player's, or the helper's.
local function holderName(id: number?): string?
	local player = playerById(id)
	if player then
		return player.DisplayName
	end
	return MoveHelper.nameOf(id)
end

-- He takes `spot`: a one-hand thing into his arms (in front of his chest, like a player's), or the other end of a pair
-- thing a player lifted (their walk: two people's now). Never a "both" thing, never a pair thing alone. (ok, why)
function Moving.helperTake(s: Session, spot: number, npc: Model): (boolean, string?)
	local who = helperIdOf(npc)
	local item = s.items[spot]
	local thing = s.move.things[spot]
	local root = npc.PrimaryPart
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if s.ended or not who or not item or not thing or not root or not humanoid then
		return false, "gone"
	end
	if thing.class == "pair" then
		local ok, why = Rules.help(s.move, spot, who)
		if not ok then
			return false, why
		end
		carry(s, item) -- (carried now, not dragged: the carrier's weld and walk change)
		local carrier = playerById(thing.carrier)
		if carrier then
			say(carrier, `{npc.Name} took the other end of the {thing.name}: walk together.`)
		end
		s.dirty = true
		return true, nil
	elseif thing.class ~= "hand" then
		return false, "single"
	end
	local ok, why = Rules.pick(s.move, spot, who)
	if not ok then
		return false, why
	end
	item.model.Parent = folder
	weldTo(item, root, root.CFrame * holdOffset(thing, "hand", root, humanoid))
	item.lastAt, item.lastTime, item.apartSince, item.fallFrom = nil, 0, nil, nil
	rewire(s, item)
	s.dirty = true
	return true, nil
end

-- He lets go. why: "put" (set down gently where he is), "died" (it falls: knocked), "apart" (his end of a pair thing:
-- left behind) or "end". His end of a pair thing: the carrier drags it on alone.
function Moving.helperDrop(s: Session, npc: Model, why: string)
	local who = helperIdOf(npc)
	if not who then
		return
	end
	local spot, role = Rules.holding(s.move, who)
	if not spot then
		return
	end
	local item = s.items[spot]
	local thing = s.move.things[spot]
	if role == "helper" then
		Rules.release(s.move, who)
		local carrier = playerById(thing.carrier)
		if item and carrier and not s.ended then
			if why ~= "end" then
				say(carrier, `{npc.Name} let go: you drag the {thing.name} alone now.`)
			end
			carry(s, item) -- (dragged again: the carrier's weld and walk)
		end
		s.dirty = true
		return
	end
	local at = if item then item.root.CFrame else nil
	Rules.release(s.move, who)
	if item and at then
		for _, hook in item.hooks do
			hook:Disconnect()
		end
		table.clear(item.hooks)
		local fell = settle(item, thing, at)
		rewire(s, item)
		if why == "died" then
			hurtThing(s, spot, Rules.deathDamage(thing.fragile))
		elseif why == "put" then
			hurtThing(s, spot, Rules.fallDamage(fell, thing.fragile))
		end
	end
	s.dirty = true
end

-- He puts what he carries into the truck (MovingRules' packer, like Load). (ok, why: "noroom", "empty" …)
function Moving.helperLoad(s: Session, npc: Model): (boolean, string?)
	local who = helperIdOf(npc)
	if s.ended or not who or not truckOk(s) then
		return false, "over"
	end
	local spot = Rules.holding(s.move, who)
	local thing = if spot then s.move.things[spot] else nil
	local at, refused = Rules.load(s.move, who)
	if not at or not spot or not thing then
		return false, refused
	end
	local item = s.items[spot]
	if item then
		stow(s, item, at)
	end
	local c = Rules.counts(s.move)
	say(s.owner, `{npc.Name} loaded {labelOf(thing)} · {c.out}/{c.total} out · truck {math.floor(Rules.fill(s.move.packing) * 100 + 0.5)}% full`)
	s.dirty = true
	return true, nil
end

-- A bite took `hp` of his health: what he holds takes the knock (like a player's).
function Moving.helperHurt(s: Session, npc: Model, hp: number)
	local who = helperIdOf(npc)
	local spot = if who then Rules.holding(s.move, who) else nil
	local thing = if spot then s.move.things[spot] else nil
	if spot and thing then
		hurtThing(s, spot, Rules.hitDamage(hp, thing.fragile))
	end
end

-- ── Doors: in and out with a fade ──────────────────────────────────────────

local travel: (Player, CFrame, Session, boolean, boolean?) -> ()

travel = function(player: Player, target: CFrame, s: Session, inside: boolean, partner: boolean?)
	if traveling[player] then
		return
	end
	traveling[player] = true
	remote:FireClient(player, "fade", "out", T.Fade)
	task.delay(T.Fade, function()
		pcall(function()
			player:RequestStreamAroundAsync(target.Position, 4)
		end)
		local character, humanoid, root = bodyOf(player)
		if character and humanoid and root then
			local lift = humanoid.HipHeight + root.Size.Y / 2
			character:PivotTo(target + Vector3.new(0, lift, 0))
			if inside then
				s.inside[player] = true
			else
				s.inside[player] = nil
			end
			local spot, role = Rules.holding(s.move, player.UserId)
			if spot then
				local item = s.items[spot]
				if item then
					item.lastAt, item.fallFrom, item.apartSince = nil, nil, nil
				end
				-- the other end of a pair thing comes along, beside you
				local thing = s.move.things[spot]
				local other = playerById(if role == "carrier" then thing.helper else thing.carrier)
				if other and not partner then
					travel(other, target * CFrame.new(3.5, 0, 0), s, inside, true)
				end
			end
		end
		remote:FireClient(player, "fade", "in", T.Fade)
		traveling[player] = nil
		s.dirty = true
	end)
end

onEnter = function(player: Player, contractId: string)
	local s = sessionOf(player)
	if not s or s.contract.id ~= contractId then
		say(player, "Locked. Take this moving contract at the depot's board first (ZDC Moving).")
		return
	end
	if traveling[player] or s.ended then
		return
	end
	local _, humanoid, root = bodyOf(player)
	if not humanoid or not root then
		return
	end
	if humanoid.SeatPart then
		say(player, "Get out first.")
		return
	end
	if flat(root.Position, s.site.door) > T.Reach.Door + 4 then
		return
	end
	local spot, role = Rules.holding(s.move, player.UserId)
	if spot and role == "helper" then
		say(player, "The one at the front leads the way in.")
		return
	end
	travel(player, s.origin * (s.plan.entry :: CFrame), s, true)
end

local function onLeave(player: Player, s: Session)
	local exit = s.exit
	local _, humanoid, root = bodyOf(player)
	if traveling[player] or not exit or not humanoid or not root then
		return
	end
	if flat(root.Position, exit.Position) > T.Reach.Exit + 4 then
		return
	end
	local spot, role = Rules.holding(s.move, player.UserId)
	if spot and role == "helper" then
		say(player, "The one at the front leads the way out.")
		return
	end
	travel(player, s.site.outside, s, false)
end

-- ── The things' prompts ────────────────────────────────────────────────────

local function onPick(s: Session, spot: number, player: Player)
	if s.ended or sessionOf(player) ~= s or traveling[player] then
		return
	end
	local item = s.items[spot]
	local thing = s.move.things[spot]
	local character, humanoid, root = bodyOf(player)
	if not item or not thing or not character or not humanoid or not root then
		return
	end
	if humanoid.SeatPart then
		say(player, "Get out first.")
		return
	end
	if flat(root.Position, item.root.Position) > T.Reach.Item + math.max(thing.size.X, thing.size.Z) / 2 + 2 then
		return
	end
	if character:GetAttribute("Carrying") ~= nil or character:GetAttribute("Pushing") ~= nil then
		say(player, "Your hands are full: put down what you carry first (G).")
		return
	end
	local ok, why = Rules.pick(s.move, spot, player.UserId)
	if not ok then
		say(player, Rules.whyText(why))
		return
	end
	carry(s, item)
	if thing.class == "pair" then
		say(player, `The {thing.name} needs two: you drag it slowly. A crew mate can "Help lift" the other end.`)
	end
	s.dirty = true
end

local function onHelp(s: Session, spot: number, player: Player)
	if s.ended or sessionOf(player) ~= s or traveling[player] then
		return
	end
	local item = s.items[spot]
	local thing = s.move.things[spot]
	local character, humanoid, root = bodyOf(player)
	if not item or not thing or not character or not humanoid or not root or humanoid.SeatPart then
		return
	end
	if flat(root.Position, item.root.Position) > T.Reach.Item + math.max(thing.size.X, thing.size.Z) / 2 + 2 then
		return
	end
	if thing.carrier == player.UserId then
		say(player, Rules.whyText("yours"))
		return
	end
	if character:GetAttribute("Carrying") ~= nil or character:GetAttribute("Pushing") ~= nil then
		say(player, "Your hands are full: put down what you carry first (G).")
		return
	end
	local ok, why = Rules.help(s.move, spot, player.UserId)
	if not ok then
		say(player, Rules.whyText(why))
		return
	end
	pcall(function()
		require(script.Parent.Hand).holster(player, true)
	end)
	carry(s, item) -- (carried now, not dragged: the carrier's weld and walk change)
	local carrier = playerById(thing.carrier)
	if carrier then
		say(carrier, `{player.DisplayName} took the other end of the {thing.name}: walk together.`)
	end
	say(player, `You hold the other end of the {thing.name}: stay close to it.`)
	s.dirty = true
end

local function setupItem(s: Session, spot: number, model: Model)
	local thing = s.move.things[spot]
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	if not thing or not root or not root:IsA("BasePart") then
		return -- (a spot of furniture the rules do not know stays where it is)
	end
	local hold = if thing.class == "hand" then 0 elseif thing.class == "both" then 0.3 else 0.5
	local pick = newPrompt(root, if thing.class == "pair" then "Lift" else "Pick up", labelOf(thing), Enum.KeyCode.E, hold, T.Reach.Item)
	local help = newPrompt(root, "Help lift", labelOf(thing), Enum.KeyCode.E, 0.3, T.Reach.Item)
	help.Enabled = false
	tag(pick, s.owner)
	tag(help, s.owner)
	pick.Triggered:Connect(function(player: Player)
		onPick(s, spot, player)
	end)
	help.Triggered:Connect(function(player: Player)
		onHelp(s, spot, player)
	end)
	model:SetAttribute("MoveSpot", spot)
	s.items[spot] = {
		spot = spot,
		model = model,
		root = root,
		home = model:GetPivot(),
		pick = pick,
		help = help,
		down = {},
		weld = nil,
		hooks = {},
		health = {},
		lastAt = nil,
		lastTime = 0,
		apartSince = nil,
		fallFrom = nil,
	}
end

-- ── The state for the clients ──────────────────────────────────────────────

local function viewFor(s: Session, player: Player): { [string]: any }
	local items = {}
	for _, spot in s.move.order do
		local thing = s.move.things[spot]
		local carrier, helper = holderName(thing.carrier), holderName(thing.helper) -- (7.0 helper: Danny's name too)
		table.insert(items, {
			spot = spot,
			name = thing.name,
			icon = thing.icon,
			star = thing.star,
			class = thing.class,
			weight = thing.weight,
			fragile = thing.fragile,
			value = thing.value,
			room = thing.room,
			state = thing.state,
			condition = math.floor(thing.condition * 100 + 0.5) / 100,
			broken = Rules.broken(thing),
			by = if carrier then carrier .. (if helper then ` + {helper}` else "") else nil,
			mine = thing.carrier == player.UserId or thing.helper == player.UserId,
		})
	end
	local truck = truckOk(s)
	local drop = dropOffAt()
	return {
		id = s.id,
		contract = s.contract.id,
		name = s.contract.name,
		icon = s.contract.icon,
		client = s.contract.client,
		owner = s.owner.DisplayName,
		mine = player == s.owner,
		endsAt = s.move.endsAt,
		hordeAt = s.move.endsAt - T.HordeAt,
		seconds = s.move.seconds,
		horde = s.move.phase == "horde",
		items = items,
		counts = Rules.counts(s.move),
		fill = Rules.fill(s.move.packing),
		truck = truck ~= nil,
		backOpen = truck ~= nil and Vehicles.backOpen(truck),
		house = { x = s.site.home.park.x, z = s.site.home.park.z },
		door = { x = s.site.door.X, z = s.site.door.Z },
		dropOff = { x = drop.X, z = drop.Z },
		inside = s.inside[player] == true,
	}
end

local function send(s: Session)
	s.dirty = false
	s.sentAt = os.clock()
	for _, player in membersOf(s) do
		remote:FireClient(player, "state", viewFor(s, player))
	end
end

-- ── The end ────────────────────────────────────────────────────────────────

local function letGoZombies(list: { Zombies.Zombie })
	for _, z in list do
		if not z.dead then
			Zombies.march(z, nil)
		end
	end
	table.clear(list)
end

-- Everything of the session goes: whoever is inside comes out, the things, the interior, the truck's prompts.
local function cleanup(s: Session)
	for player in s.inside do
		local _, _, root = bodyOf(player)
		if root and player.Parent and (root.Position - s.origin.Position).Magnitude < 600 then
			travel(player, s.site.outside, s, false)
		end
	end
	for _, spot in s.move.order do
		local thing = s.move.things[spot]
		clearHands(playerById(thing.carrier))
		clearHands(playerById(thing.helper))
		local item = s.items[spot]
		if item and thing.state == "carried" then
			unweld(item)
			setParts(item.model, true, false, item.root)
		end
	end
	task.delay(T.Fade + 0.5, function()
		-- the interior first (server/HouseInterior.luau's own way), then the things that left it (carried, set down
		-- outside, in the truck: unloaded at the Wall)
		local interior = s.interior
		local a = art
		if interior then
			local ok = a ~= nil and pcall(function()
				(a :: Art).interior.destroy(interior)
			end)
			if not ok then
				interior:Destroy()
			end
		end
		for _, item in s.items do
			for _, hook in item.hooks do
				hook:Disconnect()
			end
			item.model:Destroy()
		end
		if s.exit then
			s.exit:Destroy()
		end
		if slots[s.slot] == s then
			slots[s.slot] = nil
		end
	end)
	for _, prompt in { s.load, s.unload } do
		if prompt then
			prompt:Destroy()
		end
	end
	local truck = s.truck
	if truck and truck.model.Parent then
		truck.model:SetAttribute("BackCrew", nil)
		local back = Vehicles.backPrompt(truck)
		if back then
			back.Enabled = true
		end
	end
	letGoZombies(s.horde)
	letGoZombies(s.roam)
	for member in s.members do
		if member:GetAttribute("MoveWith") == s.owner.UserId then
			member:SetAttribute("MoveWith", nil)
		end
	end
	if sessions[s.owner] == s then
		sessions[s.owner] = nil
	end
end

local HOW_TEXT: { [string]: string } = {
	done = "Delivered to the Wall",
	late = `Time's up: what was loaded counts at {math.floor(T.Pay.LateShare * 100 + 0.5)}% of its pay`,
	cancelled = "Called off",
	failed = "Lost",
}

-- The move ends with `event` (deliver, timeout, cancel, lose): the pay, the XP, the cards; `why` for the card.
local function finish(s: Session, event: string, why: string?)
	if s.ended then
		return
	end
	local phase = Rules.advance(s.move.phase, event)
	if not phase then
		return
	end
	s.move.phase = phase
	local result = Rules.result(s.move, phase, now())
	-- the crew near the truck (or near the owner without one) shares the pay
	local truck = truckOk(s)
	local _, _, ownerRoot = bodyOf(s.owner)
	local center = if truck then truck.chassis.Position elseif ownerRoot then ownerRoot.Position else nil
	local present: { Player } = { s.owner }
	for _, member in everyone(s) do
		if member == s.owner then
			continue
		end
		local _, _, root = bodyOf(member)
		if root and center and (root.Position - center).Magnitude <= T.Present then
			table.insert(present, member)
		end
	end
	local ownerPay, share = 0, 0
	if result.total > 0 then
		ownerPay, share = Economy.crewSplit(result.total, #present - 1)
	end
	s.ended = true
	local c = Rules.counts(s.move)
	for _, member in everyone(s) do
		local paid = if member == s.owner then ownerPay elseif table.find(present, member) then share else 0
		if paid > 0 then
			PlayerData.addMoney(member, paid, "MovePay")
		end
		local xp = if table.find(present, member) then result.xp else 0
		if xp > 0 then
			PlayerData.addXp(member, xp)
		end
		remote:FireClient(member, "result", {
			name = s.contract.name,
			icon = s.contract.icon,
			how = phase,
			howText = why or HOW_TEXT[phase] or phase,
			delivered = result.delivered,
			left = result.left,
			broken = result.broken,
			total = c.total,
			starsOut = result.starsOut,
			starsTotal = c.stars,
			stars = result.stars,
			pay = result.total,
			money = paid,
			xp = xp,
			base = math.floor(result.base + 0.5),
			starBonus = math.floor(result.starBonus + 0.5),
			timeBonus = math.floor(result.timeBonus + 0.5),
			fine = math.floor(result.fine + 0.5),
			crew = #present,
		})
		remote:FireClient(member, "state", nil)
	end
	storyText(s, phase, result.stars) -- MoveStory hook: Marge's debrief at the end
	if phase == "done" or phase == "late" then
		local owner = s.owner
		PlayerData.track("event", owner, "MoveDone", result.stars, s.contract.id, if #present > 1 then "crew" else "solo")
	end
	cleanup(s)
end

-- ── Starting ───────────────────────────────────────────────────────────────

local function freeSlot(): number?
	for index = 1, T.Slots do
		if not slots[index] then
			return index
		end
	end
	return nil
end

-- Why this player can't start a move now (nil: they can).
local function cantStart(owner: Player): string?
	if sessionOf(owner) then
		return "You are on a move already."
	end
	local leader = Crew.ownerOf(owner)
	if leader then
		return `You are in {leader.DisplayName}'s crew: they take the contract (or leave the crew).`
	end
	if jobs and jobs.active(owner) then
		return "Finish or cancel your job first."
	end
	if not artNow() then
		return "Moving is not ready in this place yet (the house art is missing)."
	end
	if not freeSlot() then
		return "Every moving crew is out right now: try again in a minute."
	end
	return nil
end

-- The contract card (the board, the admin): the house, its ★ things, the pay, the time; arms START.
function Moving.openCard(player: Player, contractId: string?, admin: boolean)
	local contract = contractById(contractId) or T.Contracts[1]
	local a = artNow()
	if not contract or not a then
		say(player, "Moving is not ready in this place yet (the house art is missing).")
		return
	end
	local ok, plan = pcall(function(): any
		return a.layout.plan(contract.seed, contract.kind)
	end)
	if not ok or type(plan) ~= "table" then
		warn(`[Moving] the plan of {contract.id} failed: {plan}`)
		say(player, "Moving is not ready in this place yet (the house plan failed).")
		return
	end
	local defs = defsOf(a)
	local spots = spotsOf(plan)
	local starNames: { string } = {}
	local count = 0
	for _, spot in spots do
		local def = defs[spot.item]
		if def then
			count += 1
			if spot.star then
				table.insert(starNames, `{def.icon} {def.name}`)
			end
		end
	end
	local site = sites[contract.id]
	local truck = Economy.findCar(T.Truck)
	armed[player] = { at = now(), admin = admin }
	remote:FireClient(player, "contract", {
		id = contract.id,
		name = contract.name,
		client = contract.client,
		icon = contract.icon,
		blurb = contract.blurb,
		address = if site then site.home.address else "",
		stars = starNames,
		items = count,
		estimate = Rules.estimate(spots, defs),
		time = T.Time,
		hordeAt = T.HordeAt,
		truck = if truck then truck.name else "Moving Truck",
		crew = #Crew.members(player),
		busy = cantStart(player),
	})
end

local function startMove(owner: Player, contractId: any, admin: boolean): string?
	local contract = contractById(contractId)
	local site = contract and sites[contract.id]
	if not contract or not site then
		return "No such moving contract."
	end
	local busy = cantStart(owner)
	if busy then
		return busy
	end
	local card = armed[owner]
	if not admin then
		local _, _, root = bodyOf(owner)
		local board = boardPart
		if not card or now() - card.at > T.CardFor then
			return "Open the contract at the depot's board first."
		end
		if not card.admin and (not root or not board or flat(root.Position, board.Position) > T.Reach.Board + 12) then
			return "Take the contract at the depot's board (ZDC Moving)."
		end
	end
	armed[owner] = nil
	local a = artNow() :: Art
	local slot = freeSlot() :: number
	local plan = a.layout.plan(contract.seed, contract.kind)
	local origin: CFrame = a.interior.slot(slot)
	local built, interior, models = pcall(function(): (Model, { [number]: Model })
		return a.interior.build(plan, origin)
	end)
	if not built or typeof(interior) ~= "Instance" then
		warn(`[Moving] the interior of {contract.id} failed: {interior}`)
		return "The house could not be built: try again."
	end
	-- the truck: lent right next to you, you in the driver's seat (your own car is parked as it is)
	local err = Vehicles.placeNear(owner, T.Truck)
	local truck = Vehicles.get(owner)
	if err or not truck or truck.id ~= T.Truck then
		pcall(function()
			a.interior.destroy(interior)
		end)
		return err or "The moving truck could not come: try again."
	end
	nextId += 1
	local bed: Rules.Bed = { width = T.Bed.Width, length = T.Bed.Length, height = T.Bed.Height, cell = T.Bed.Cell }
	local s: Session = {
		id = nextId,
		owner = owner,
		contract = contract,
		site = site,
		move = Rules.newMove(spotsOf(plan), defsOf(a), bed, now(), T.Time),
		plan = plan,
		origin = origin,
		slot = slot,
		interior = interior :: Model,
		items = {},
		exit = nil,
		truck = truck,
		load = nil,
		unload = nil,
		horde = {},
		roam = {},
		nextRoam = 0,
		bursts = 0,
		nextBurst = 0,
		members = {},
		inside = {},
		dirty = true,
		sentAt = 0,
		ended = false,
		emptyWarned = 0,
	}
	sessions[owner] = s
	slots[slot] = s
	for spot, model in (models :: { [number]: Model }) do
		if typeof(model) == "Instance" and model:IsA("Model") then
			setupItem(s, spot, model)
		end
	end
	-- "Leave house" by the front door inside
	local exitAt = origin * CFrame.new(plan.exit :: Vector3)
	local exit = invisible("LeaveDoor", Vector3.new(4, 6, 1), exitAt + Vector3.new(0, 3.5, 0), folder or workspace)
	local leave = newPrompt(exit, "Leave house", `{contract.icon} {contract.name}`, Enum.KeyCode.E, 0, T.Reach.Exit)
	leave.Triggered:Connect(function(player: Player)
		onLeave(player, s)
	end)
	s.exit = exit
	truckPrompts(s)
	tellAll(s, `🚚 Move started: {contract.name}, {site.home.address}. Drive the truck there (GPS), carry the things out, load them and drive them to the Wall at the depot. {Rules.counts(s.move).stars} ★ things are a must!`)
	storyText(s) -- MoveStory hook: Marge's text at the start
	return nil
end

-- ── The clock ──────────────────────────────────────────────────────────────

local function startHorde(s: Session)
	local phase = Rules.advance(s.move.phase, "horde")
	if not phase then
		return
	end
	s.move.phase = phase
	s.bursts = T.Horde.Bursts
	s.nextBurst = 0
	tellAll(s, `🧟 A HORDE is coming to {s.contract.name}! Load what you can and drive to the Wall!`)
	s.dirty = true
end

local function hordeBurst(s: Session, clock: number)
	if s.bursts <= 0 or clock < s.nextBurst then
		return
	end
	s.bursts -= 1
	s.nextBurst = clock + T.Horde.Every
	local door = s.site.door
	for _ = 1, math.ceil(T.Horde.Count / math.max(1, T.Horde.Bursts)) do
		local spot = Zombies.findSpot(door, nil, T.Horde.Near, T.Horde.Far)
		local z = if spot then Zombies.spawn(Zombies.pickKind(T.Horde.Kinds, spot, s.owner), spot, s.owner) else nil
		if z then
			Zombies.march(z, door, "move")
			table.insert(s.horde, z)
		end
	end
end

-- A few zombies roam round the house while somebody of the crew is outside near it.
local function keepRoam(s: Session, clock: number)
	if clock < s.nextRoam then
		return
	end
	s.nextRoam = clock + T.Roam.Every
	for index = #s.roam, 1, -1 do
		local z = s.roam[index]
		if z.dead or not z.model.Parent then
			table.remove(s.roam, index)
		end
	end
	local near = false
	for member in s.members do
		local _, _, root = bodyOf(member)
		if root and not s.inside[member] and flat(root.Position, s.site.door) <= T.Roam.Range then
			near = true
		end
	end
	if not near then
		return
	end
	for _ = 1, T.Roam.Count - #s.roam do
		local spot = Zombies.findSpot(s.site.door, nil, T.Roam.Near, T.Roam.Far)
		local z = if spot then Zombies.spawn(Zombies.pickKind(T.Roam.Kinds, spot, s.owner), spot, s.owner, false, false, true) else nil
		if z then
			table.insert(s.roam, z)
		end
	end
end

-- Who is on the move now (the owner and their crew): joiners hear about it, leavers drop what they hold and come out.
local function syncMembers(s: Session)
	local current: { [Player]: boolean } = {}
	for _, player in membersOf(s) do
		current[player] = true
		if player:GetAttribute("MoveWith") ~= s.owner.UserId then
			player:SetAttribute("MoveWith", s.owner.UserId)
		end
		if not s.members[player] then
			s.dirty = true
			if player ~= s.owner then
				say(player, `🚚 You are on {s.owner.DisplayName}'s move: {s.contract.name}. Help carry the things out to the truck.`)
			end
		end
	end
	for player in s.members do
		if not current[player] then
			release(s, player, "left")
			if player.Parent then
				if player:GetAttribute("MoveWith") == s.owner.UserId then
					player:SetAttribute("MoveWith", nil)
				end
				remote:FireClient(player, "state", nil)
				say(player, `You are off {s.owner.DisplayName}'s move.`)
				if s.inside[player] then
					travel(player, s.site.outside, s, false)
				end
			end
		end
	end
	s.members = current
end

-- The carried things: a helper too far for Grace s, a carrier faster than the carry (a teleport), a fall's top.
local function watchCarried(s: Session, clock: number)
	for _, spot in s.move.order do
		local thing = s.move.things[spot]
		local item = s.items[spot]
		if thing.state ~= "carried" or not item then
			continue
		end
		local carrier = playerById(thing.carrier)
		local character, _, root = bodyOrNil(carrier)
		if not carrier or not character or not root then
			continue
		end
		local holder: Player = carrier
		if item.fallFrom then
			item.fallFrom = math.max(item.fallFrom, root.Position.Y)
		end
		if not traveling[holder] then
			local last = item.lastAt
			if last and item.lastTime > 0 then
				local walk = Rules.carrySpeed(Config.Movement.Walk, Rules.mode(thing), thing.weight)
				local admin = holder:GetAttribute("AdminSpeed")
				local kit = character:GetAttribute("KitSpeed")
				local boost = (if type(admin) == "number" then math.clamp(admin, 1, 4) else 1) * (if type(kit) == "number" then math.clamp(kit, 1, 2) else 1)
				if flat(root.Position, last) > walk * boost * T.Pace.Factor * (clock - item.lastTime) + T.Pace.Slack then
					release(s, holder, "pace")
					continue
				end
			end
			item.lastAt, item.lastTime = root.Position, clock
		end
		local helper = playerById(thing.helper)
		if helper then
			local _, _, helperRoot = bodyOf(helper)
			local reach = math.max(thing.size.X, thing.size.Z) / 2 + T.Tether
			if helperRoot and flat(helperRoot.Position, item.root.Position) > reach and not traveling[helper] then
				item.apartSince = item.apartSince or clock
				if clock - (item.apartSince :: number) > T.Grace then
					release(s, holder, "apart")
				end
			else
				item.apartSince = nil
			end
		end
	end
end

local function tick(s: Session)
	local t = now()
	local clock = os.clock()
	local due = Rules.due(s.move, t)
	if due == "timeout" then
		finish(s, "timeout")
		return
	elseif due == "horde" then
		startHorde(s)
	end
	if not truckOk(s) then
		local truck = s.truck
		finish(s, "lose", if truck and truck.wrecked then "The moving truck was wrecked: the load is lost" else "The moving truck is gone: the load is lost")
		return
	end
	syncMembers(s)
	watchCarried(s, clock)
	keepRoam(s, clock)
	if s.move.phase == "horde" then
		hordeBurst(s, clock)
	end
	MoveHelper.sync(s, Moving) -- 7.0: Danny joins a crew of one, goes when it grows (his own loop walks him)
	refreshTruck(s)
	local truck = s.truck :: Vehicles.Car
	if flat(truck.chassis.Position, dropOffAt()) <= T.DropRadius then
		if Rules.counts(s.move).out > 0 then
			finish(s, "deliver")
			return
		elseif clock - s.emptyWarned > 15 then
			s.emptyWarned = clock
			say(s.owner, "The truck is empty: load the things at the house first.")
		end
	end
	if (s.dirty and clock - s.sentAt > 0.25) or clock - s.sentAt > 5 then
		send(s)
	end
end

-- ── The admin ──────────────────────────────────────────────────────────────

function Moving.admin(player: Player, arg: any): string
	local s = sessions[player]
	if arg == "card" then
		Moving.openCard(player, nil, true)
		return "ADMIN: the moving contract card is open (START begins Marge's House)."
	elseif arg == "start" then
		local err = startMove(player, T.Contracts[1].id, true)
		return if err then `ADMIN: {err}` else `ADMIN: {T.Contracts[1].name} started; the truck is yours.`
	elseif arg == "house" then
		local site = sites[T.Contracts[1].id]
		local character = player.Character
		if not site or not character then
			return "ADMIN: no house to go to."
		end
		local car = Vehicles.get(player)
		local seatedIn = Vehicles.seatedIn(player)
		if car and seatedIn == car then
			local x, z, dx, dz = Map.nearestRoad(site.home.park.x, site.home.park.z)
			local spot = Vector3.new(x, Vehicles.groundY(x, z) + 3, z)
			car.model:PivotTo(CFrame.lookAt(spot, spot + Vector3.new(dx, 0, dz)))
		else
			pcall(function()
				player:RequestStreamAroundAsync(site.outside.Position, 4)
			end)
			character:PivotTo(site.outside + Vector3.new(0, 3, 0))
		end
		return `ADMIN: at {site.contract.name}.`
	end
	if not s then
		return "ADMIN: you are not running a move (START one first)."
	end
	if arg == "horde" then
		if s.move.phase == "running" then
			s.move.endsAt = math.min(s.move.endsAt, now() + T.HordeAt)
			startHorde(s)
		end
		return "ADMIN: the horde comes now."
	elseif arg == "time" then
		s.move.endsAt = now() + 60
		s.dirty = true
		return "ADMIN: one minute left."
	elseif arg == "deliver" then
		finish(s, "deliver")
		return "ADMIN: delivered with what is in the truck."
	elseif arg == "end" then
		finish(s, "cancel", "Called off by the admin")
		return "ADMIN: the move is called off."
	end
	return "ADMIN: card | start | house | horde | time | deliver | end."
end

-- ── Start ──────────────────────────────────────────────────────────────────

local function onPutDown(player: Player)
	local s = sessionOf(player)
	if s and Rules.holding(s.move, player.UserId) then
		release(s, player, "put")
	end
end

local function onRequest(player: Player, action: any, arg: any)
	if not Net.limit(player, "Moving", Config.Robust.Limits.Moving) then
		return
	end
	if action == "start" then
		local err = startMove(player, arg, false)
		if err then
			say(player, err)
		end
	elseif action == "giveup" then
		local s = sessions[player]
		if s then
			finish(s, "cancel", "You called it off")
		end
	elseif action == "state" then
		local s = sessionOf(player)
		if s then
			remote:FireClient(player, "state", viewFor(s, player))
		end
	end
end

local function wireHooks()
	jobs = require(script.Parent.Jobs)
	-- a crew on a move is "hunted" like a job's: no ordinary roamers round them (the move brings its own), none inside
	local hunts = Zombies.hunts
	Zombies.hunts = function(player: Player): boolean
		return hunts(player) or sessionOf(player) ~= nil
	end
	-- the truck's knocks knock its load
	local function truckHit(player: Player, amount: number)
		local s = sessions[player]
		if not s or s.ended or type(amount) ~= "number" then
			return
		end
		for _, spot in s.move.order do
			local thing = s.move.things[spot]
			if thing.state == "truck" then
				hurtThing(s, spot, Rules.truckDamage(amount, thing.fragile))
			end
		end
	end
	local zombieHit = Zombies.onCarDamaged
	Zombies.onCarDamaged = function(player: Player, amount: number)
		zombieHit(player, amount)
		truckHit(player, amount)
	end
	local BanditCars = require(script.Parent.BanditCars)
	local banditHit = BanditCars.onCarDamaged
	BanditCars.onCarDamaged = function(player: Player, amount: number)
		banditHit(player, amount)
		truckHit(player, amount)
	end
	-- the crew opens and closes the truck's back too
	local backAllowed = Vehicles.backAllowed
	Vehicles.backAllowed = function(player: Player, car: Vehicles.Car): boolean
		if backAllowed(player, car) then
			return true
		end
		local s = sessions[car.owner]
		return s ~= nil and not s.ended and s.truck == car and sessionOf(player) == s
	end
	-- the truck stays while the move runs: CAR does not swap it, a respawn does not take it back
	local returnLent = jobs.returnLent
	jobs.returnLent = function(player: Player): boolean
		local s = sessions[player]
		if s and not s.ended and truckOk(s) then
			return false
		end
		return returnLent(player)
	end
	local callCar = Vehicles.callCar
	if callCar then
		local call: (Player, string?) -> string? = callCar
		Vehicles.callCar = function(player: Player, carId: string?): string?
			local s = sessions[player]
			if s and not s.ended and truckOk(s) then
				return "Your moving truck is out: finish the move first (or GIVE UP in the move's list, Tab)."
			end
			return call(player, carId)
		end
	end
end

function Moving.start()
	local made = Instance.new("Folder")
	made.Name = "Moves"
	made.Parent = workspace
	folder = made
	for _, contract in T.Contracts do
		local site = buildSite(contract, made)
		if site then
			sites[contract.id] = site
		end
	end
	buildBoard(made)
	buildDropOff(made)
	wireHooks()
	remote.OnServerEvent:Connect(onRequest)
	Net.get("PutDown").OnServerEvent:Connect(onPutDown)
	Players.PlayerRemoving:Connect(function(player: Player)
		local own = sessions[player]
		if own then
			for _, member in everyone(own) do
				if member ~= player then
					say(member, `The move was called off: {player.DisplayName} left.`)
				end
			end
			finish(own, "cancel", `{player.DisplayName} left the game`)
		end
		for _, session in sessions do
			if session.members[player] then
				release(session, player, "gone")
			end
			session.inside[player] = nil
			session.members[player] = nil
		end
		armed[player] = nil
		traveling[player] = nil
	end)
	-- a new body is never inside (a death inside respawns you at the depot)
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			for _, session in sessions do
				session.inside[player] = nil
				session.dirty = true
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	task.spawn(function()
		while true do
			task.wait(T.Tick)
			Moving.step()
		end
	end)
end

-- One tick of every running move (the loop's, every Config.Moving.Tick s; tests/moving_runtime_test.luau calls it).
function Moving.step()
	for _, s in sessions do
		if not s.ended then
			local ok, err = pcall(function()
				tick(s)
			end)
			if not ok then
				warn(`[Moving] {s.contract.id}: {err}`)
			end
		end
	end
end

return Moving
