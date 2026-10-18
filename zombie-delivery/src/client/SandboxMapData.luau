--!strict
-- 10.x THE MAP, what the map knows (Config.SandboxMapUi; the rules shared/SandboxMapRules.luau): client/SandboxMapUi.luau's
-- big map and client/SandboxMiniMap.luau's minimap read the world through it and draw it with client/SandboxMapDraw.luau.
-- Presentation only: it reads what the server shows every client and asks for nothing but the move's state.
--   * Where you are (place()): in a run when your move's state (the Moving remote's "state", as client/MovingHud.luau
--     reads it) names a house of SandboxMap.Houses (its `contract`), else client/RunUi.luau's run, else the interior you
--     stand in; its inside is the model in workspace.Moves whose Kind is that house's plan kind (Config.Moving.Sandbox
--     .Houses), its floor plan the model's MapPlan (server/HouseInterior.luau; decoded once a model), its yard
--     SandboxMapRules.yard. Anywhere else: the lobby.
--   * The fog (a run: look() every Fog.Every s while you are in its house, the map open or not): the house's loot (the
--     CollectionService tag Config.Loot.Tag, in the plan's box) within Fog.See studs of your eyes (Fog.Eye over your
--     root), the nearest Fog.Most first, a ray to each against the house's shell only (its folder "Shell": the walls,
--     not the furniture): a piece seen stays seen for that interior (shared/SandboxMapRules.luau shown: until carried
--     out, the Moving state's item states).
--   * The lists, in the place's own studs (the lobby's world x, z; a run's plan frame, its yard's strip under it), read
--     when drawn: people() (you with your look; the players there: a run's are its party; the helpers in workspace.Npcs
--     with MoveHelper; the zombies within Config.SandboxMapUi.Zombies studs of you), loot() (seen, not carried out, its
--     rarity, its pulse), dangers() (the tags of Config.SandboxMapUi.Danger with their Open and Kind), truck() (the van
--     in workspace.Cars with Config.Runs.Truck.Attribute in the house's run zone, else its curb), status() (the clock,
--     IN THE TRUCK n / total, the van's fill, the difficulty), 10.4 lobbies() (the PLAY circle model's attribute
--     Config.Runs.Party.Attribute: server/Parties.luau's open lobbies and the runs now, shared/PartyRules.luau decode),
--     plots() (whose they are: the players' Plot; their level: workspace.Warehouses' Level<n>). You and your party pinned to the yard's strip when out of it (`pinned`).
-- Kept by signals (the tags' added / removed, the folders' ChildAdded / ChildRemoved): no GetDescendants.
--   SandboxMapData.start()                     once (Main starts client/SandboxMapUi.luau, which starts it)
--   SandboxMapData.place() -> Place
--   SandboxMapData.locate(place, at) -> (x, z, where)   a world point in the place's studs; where "lobby" | "house" |
--                                              "yard" | "zone" (in the run's zone, off the strip) | nil (not there)
--   SandboxMapData.people(place) / loot(place) / dangers(place) / truck(place) / status(place) / lobbies() / plots()
--   SandboxMapData.round() -> Round?   10.6 both in PLAY: the quick round (server/Runs.luau's attributes on the PLAY
--                                      circle's model: RoundPhase, RoundHouse, RoundDifficulty, RoundEndsAt, RoundQueued,
--                                      RoundMovers) or nil (none written, the rounds off)
--   SandboxMapData.look()                      one look of the fog (the loop's; the checks')
--   SandboxMapData.seen(model) -> boolean      seen in this interior

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PartyRules = require(Shared.PartyRules)
local RunRules = require(Shared.RunRules)
local SandboxMap = require(Shared.SandboxMap)
local Rules = require(Shared.SandboxMapRules)
local WarehouseLayout = require(Shared.WarehouseLayout)

local SandboxMapData = {}

local C = Config.SandboxMapUi
local player = Players.LocalPlayer

export type Place = {
	kind: string, -- "lobby" | "run"
	house: string?,
	name: string,
	plan: Rules.Plan?,
	yard: Rules.Yard?,
	interior: Instance?,
	difficulty: string?, -- (its name: "Hard")
	key: string, -- what is drawn: a new key draws the plan again
}
export type Person = { name: string, kind: string, x: number, z: number, lookX: number?, lookZ: number?, pinned: boolean, where: string }
export type Loot = { model: Instance, x: number, z: number, rarity: string, state: string?, pulse: boolean, where: string }
export type Danger = { tag: string, x: number, z: number, open: boolean, kind: string?, where: string }
export type Status = { left: number?, out: number, total: number, fill: number, difficulty: string?, color: { number }? }
export type PlotView = { id: number, owner: string?, mine: boolean, level: number }

local started = false
local move: any = nil -- the Moving remote's last "state" (nil: no move)
local asked = false -- a "state" asked once in a run with none yet
local interiors: { [Instance]: boolean } = {}
local plans: { [Instance]: { code: string, plan: Rules.Plan? } } = {}
local pieces: { [Instance]: boolean } = {}
local dangers: { [Instance]: string } = {}
local seenBy: { [Instance]: { [Instance]: boolean } } = setmetatable({}, { __mode = "k" }) :: any -- interior → pieces seen
local folders: { [string]: Instance? } = {}
local rayParams: any = nil
local rayShell: Instance? = nil

-- ── Small things ─────────────────────────────────────────────────────────────

local function positionOf(thing: Instance): Vector3?
	if thing:IsA("BasePart") then
		return (thing :: BasePart).Position
	elseif thing:IsA("Model") then
		local primary = (thing :: Model).PrimaryPart
		if primary then
			return primary.Position
		end
		local ok, pivot = pcall(function(): CFrame
			return (thing :: Model):GetPivot()
		end)
		return if ok and pivot then pivot.Position else nil
	elseif thing:IsA("Attachment") then
		return (thing :: Attachment).WorldPosition
	end
	return nil
end

local function rootOf(character: Model?): BasePart?
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function kindOf(house: string): string?
	local own = (Config.Moving.Sandbox.Houses :: any)[house]
	if own and type(own.Kind) == "string" then
		return own.Kind
	end
	local h = SandboxMap.house(house)
	return if h then h.kind else nil
end

local function planOf(model: Instance): Rules.Plan?
	local code = model:GetAttribute("MapPlan")
	if type(code) ~= "string" then
		return nil
	end
	local known = plans[model]
	if known and known.code == code then
		return known.plan
	end
	local plan = Rules.decode(code)
	plans[model] = { code = code, plan = plan }
	return plan
end

local function runView(): any
	local ok, view = pcall(function(): any
		return (require(script.Parent.RunUi) :: any).run()
	end)
	return if ok and type(view) == "table" then view else nil
end

-- ── Where you are ────────────────────────────────────────────────────────────

local function interiorFor(house: string?, at: Vector3?): (Instance?, Rules.Plan?)
	local kind = if house then kindOf(house) else nil
	local best: Instance?, bestPlan: Rules.Plan? = nil, nil
	for model in interiors do
		if model.Parent then
			local plan = planOf(model)
			if plan then
				local inside = false
				if at then
					local lx, lz = Rules.toLocal(plan, at.X, at.Z)
					inside = Rules.inside(plan, lx, lz, at.Y)
				end
				if inside and (kind == nil or plan.kind == kind) then
					return model, plan -- (you stand in it)
				elseif kind ~= nil and plan.kind == kind and best == nil then
					best, bestPlan = model, plan
				end
			end
		end
	end
	return best, bestPlan
end

local function houseByKind(kind: string): string?
	for _, h in SandboxMap.Houses do
		if kindOf(h.id) == kind then
			return h.id
		end
	end
	return nil
end

function SandboxMapData.place(): Place
	local root = rootOf(player.Character)
	local at = if root then root.Position else nil
	local house: string? = nil
	if type(move) == "table" and SandboxMap.house(move.contract) then
		house = move.contract
	end
	local run = runView()
	if not house and run and SandboxMap.house(run.house) then
		house = run.house
	end
	local interior, plan = interiorFor(house, at)
	if not house and interior and plan then
		-- (no state yet, but you stand in a house's inside: that house)
		local lx, lz = Rules.toLocal(plan, (at :: Vector3).X, (at :: Vector3).Z)
		if Rules.inside(plan, lx, lz, (at :: Vector3).Y) then
			house = houseByKind(plan.kind)
		else
			interior, plan = nil, nil
		end
	end
	local h = if house then SandboxMap.house(house) else nil
	if not h then
		return { kind = "lobby", name = "THE LOBBY", key = "lobby" }
	end
	if not asked and move == nil then
		asked = true
		pcall(function()
			Net.get("Moving"):FireServer("state")
		end)
	end
	local yard = Rules.yard(h.id)
	local id = if type(move) == "table" and type(move.run) == "table" then move.run.difficulty elseif run then run.difficulty else nil
	local def = RunRules.def(id)
	return {
		kind = "run",
		house = h.id,
		name = string.upper(h.name),
		plan = plan,
		yard = yard,
		interior = interior,
		difficulty = if def then def.name else nil,
		key = `run|{h.id}|{if interior then tostring(interior:GetAttribute("Seed")) else "none"}|{if plan then "plan" else "no plan"}`,
	}
end

function SandboxMapData.locate(place: Place, at: Vector3): (number, number, string?)
	if place.kind == "lobby" then
		if SandboxMap.inLobby(at.X, at.Z, 2) then
			return at.X, at.Z, "lobby"
		end
		return 0, 0, nil
	end
	local plan = place.plan
	if plan then
		local lx, lz = Rules.toLocal(plan, at.X, at.Z)
		if Rules.inside(plan, lx, lz, at.Y) then
			return lx, lz, "house"
		end
	end
	local yard = place.yard
	local zone = if place.house then SandboxMap.zone(place.house) else nil
	if yard and zone then
		local r = zone.rect
		if at.X >= r.x0 and at.X <= r.x1 and at.Z >= r.z0 and at.Z <= r.z1 then
			local yx, yz = Rules.toYard(yard, at.X, at.Z)
			if Rules.inYard(yard, yx, yz) then
				return yx, yz, "yard"
			end
			return yx, yz, "zone"
		end
	end
	return 0, 0, nil
end

-- A look (a unit-ish x, z) in the place's frame where `where` puts it.
local function lookIn(place: Place, where: string, lx: number, lz: number): (number, number)
	if where == "house" and place.plan then
		return Rules.turn(lx, lz, place.plan.origin.yaw)
	elseif (where == "yard" or where == "zone") and place.yard then
		return Rules.turn(lx, lz, place.yard.yaw)
	end
	return lx, lz
end

-- ── The lists ────────────────────────────────────────────────────────────────

local function addPerson(out: { Person }, place: Place, at: Vector3, name: string, kind: string, look: Vector3?, pin: boolean)
	local x, z, where = SandboxMapData.locate(place, at)
	if not where then
		return
	end
	local pinned = false
	if where == "zone" then
		if not pin or not place.yard then
			return
		end
		x, z = Rules.clampYard(place.yard, x, z)
		pinned = true
	end
	local person: Person = { name = name, kind = kind, x = x, z = z, lookX = nil, lookZ = nil, pinned = pinned, where = where }
	if look then
		person.lookX, person.lookZ = lookIn(place, where, look.X, look.Z)
	end
	table.insert(out, person)
end

function SandboxMapData.people(place: Place): { Person }
	local out: { Person } = {}
	local myRoot = rootOf(player.Character)
	for _, p in Players:GetPlayers() do
		local root = rootOf(p.Character)
		if root then
			local mine = p == player
			local kind = if mine then "you" elseif place.kind == "run" then "party" else "player"
			addPerson(out, place, root.Position, p.DisplayName, kind, if mine then root.CFrame.LookVector else nil, true)
		end
	end
	if place.kind ~= "run" then
		return out
	end
	local npcs = folders.Npcs
	if npcs then
		for _, body in npcs:GetChildren() do
			if body:GetAttribute("MoveHelper") ~= nil then
				local at = positionOf(body)
				if at then
					addPerson(out, place, at, body.Name, "helper", nil, false)
				end
			end
		end
	end
	local zombies = folders.Zombies
	if zombies and myRoot then
		local me = myRoot.Position
		for _, body in zombies:GetChildren() do
			local at = positionOf(body)
			if at and (at - me).Magnitude <= C.Zombies then
				addPerson(out, place, at, "", "zombie", nil, false)
			end
		end
	end
	return out
end

local function itemStates(): { [number]: string }
	local states: { [number]: string } = {}
	if type(move) == "table" and type(move.items) == "table" then
		for _, item in move.items do
			if type(item) == "table" and type(item.spot) == "number" and type(item.state) == "string" then
				states[item.spot] = item.state
			end
		end
	end
	return states
end

local function spotOf(model: Instance): number?
	local spot = model:GetAttribute("MoveSpot")
	if type(spot) ~= "number" then
		spot = model:GetAttribute("Spot")
	end
	return if type(spot) == "number" then spot else nil
end

function SandboxMapData.seen(model: Instance): boolean
	for _, list in seenBy do
		if list[model] then
			return true
		end
	end
	return false
end

function SandboxMapData.loot(place: Place): { Loot }
	local out: { Loot } = {}
	local interior = place.interior
	local seen = if interior then seenBy[interior] else nil
	if place.kind ~= "run" or not seen then
		return out
	end
	local states = itemStates()
	for model in seen do
		if model.Parent and pieces[model] then
			local spot = spotOf(model)
			local state = if spot then states[spot] else nil
			if Rules.shown(true, state) then
				local at = positionOf(model)
				if at then
					local x, z, where = SandboxMapData.locate(place, at)
					if where == "house" or where == "yard" then
						local rarity = model:GetAttribute("Rarity")
						local tier = if type(rarity) == "string" then rarity else "common"
						table.insert(out, { model = model, x = x, z = z, rarity = tier, state = state, pulse = Rules.pulses(tier, state), where = where :: string })
					end
				end
			end
		end
	end
	return out
end

function SandboxMapData.dangers(place: Place): { Danger }
	local out: { Danger } = {}
	if place.kind ~= "run" then
		return out
	end
	for thing, tag in dangers do
		if thing.Parent then
			local at = positionOf(thing)
			if at then
				local x, z, where = SandboxMapData.locate(place, at)
				if where == "house" or where == "yard" then
					local kind = thing:GetAttribute("Kind")
					table.insert(out, { tag = tag, x = x, z = z, open = thing:GetAttribute("Open") == true, kind = if type(kind) == "string" then kind else nil, where = where :: string })
				end
			end
		end
	end
	return out
end

function SandboxMapData.truck(place: Place): { x: number, z: number }?
	local yard = place.yard
	if place.kind ~= "run" or not yard then
		return nil
	end
	local cars = folders.Cars
	if cars then
		for _, car in cars:GetChildren() do
			if car:GetAttribute(Config.Runs.Truck.Attribute) == true then
				local at = positionOf(car)
				if at then
					local x, z, where = SandboxMapData.locate(place, at)
					if where == "yard" then
						return { x = x, z = z }
					end
				end
			end
		end
	end
	return { x = yard.truck.x, z = yard.truck.z } -- (where it parks: the curb)
end

function SandboxMapData.status(place: Place): Status?
	if place.kind ~= "run" then
		return nil
	end
	local s = if type(move) == "table" and move.contract == place.house then move else nil
	local counts = if s and type(s.counts) == "table" then s.counts else {}
	local endsAt = if s then tonumber(s.endsAt) else nil
	local left: number? = nil
	if endsAt then
		local ok, now = pcall(function(): number
			return workspace:GetServerTimeNow()
		end)
		left = math.max(0, endsAt - (if ok then now else 0))
	end
	local id = if s and type(s.run) == "table" then s.run.difficulty else nil
	local def = RunRules.def(id)
	return {
		left = left,
		out = tonumber(counts.out) or 0,
		total = tonumber(counts.total) or 0,
		fill = math.clamp(if s then tonumber(s.fill) or 0 else 0, 0, 1),
		difficulty = if def then def.name else place.difficulty,
		color = if def then def.color else nil,
	}
end

-- 10.4: the PLAY circle's open lobbies and the runs now (server/Parties.luau's attribute on the PLAY circle's model).
function SandboxMapData.lobbies(): { PartyRules.Entry }
	local world = workspace:FindFirstChild("Sandbox")
	local lobby = world and world:FindFirstChild("Lobby")
	local circle = lobby and lobby:FindFirstChild("PlayCircle")
	return PartyRules.decode(if circle then circle:GetAttribute(Config.Runs.Party.Attribute) else nil)
end

-- 10.6: the quick round (the PLAY circle's Round… attributes, server/Runs.luau's), nil none.
function SandboxMapData.round(): { [string]: any }?
	local world = workspace:FindFirstChild("Sandbox")
	local lobby = world and world:FindFirstChild("Lobby")
	local circle = lobby and lobby:FindFirstChild("PlayCircle")
	local phase = if circle then circle:GetAttribute("RoundPhase") else nil
	if not circle or type(phase) ~= "string" or phase == "off" then
		return nil
	end
	return {
		phase = phase,
		house = circle:GetAttribute("RoundHouse"),
		difficulty = circle:GetAttribute("RoundDifficulty"),
		endsAt = circle:GetAttribute("RoundEndsAt"),
		queued = circle:GetAttribute("RoundQueued"),
		movers = circle:GetAttribute("RoundMovers"),
	}
end

function SandboxMapData.plots(): { PlotView }
	local out: { PlotView } = {}
	local owners: { [number]: Player } = {}
	for _, p in Players:GetPlayers() do
		local id = p:GetAttribute("Plot")
		if type(id) == "number" then
			owners[id] = p
		end
	end
	local halls = workspace:FindFirstChild("Warehouses")
	for _, plot in SandboxMap.Plots do
		local owner = owners[plot.id]
		local level = if halls then halls:GetAttribute(`Level{plot.id}`) else nil
		table.insert(out, {
			id = plot.id,
			owner = if owner then owner.DisplayName else nil,
			mine = owner == player,
			level = if type(level) == "number" then level else WarehouseLayout.levelOf(plot),
		})
	end
	return out
end

-- ── The fog ──────────────────────────────────────────────────────────────────

local function clearBetween(shell: Instance, from: Vector3, to: Vector3): boolean
	if rayShell ~= shell or not rayParams then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { shell }
		rayParams, rayShell = params, shell
	end
	local ok, hit = pcall(function(): any
		return workspace:Raycast(from, to - from, rayParams)
	end)
	return ok and hit == nil
end

function SandboxMapData.look()
	local place = SandboxMapData.place()
	local interior, plan = place.interior, place.plan
	local root = rootOf(player.Character)
	if place.kind ~= "run" or not interior or not plan or not root then
		return
	end
	local at = root.Position
	local lx, lz = Rules.toLocal(plan, at.X, at.Z)
	if not Rules.inside(plan, lx, lz, at.Y) then
		return -- (out of the house you see none of it)
	end
	local seen = seenBy[interior]
	if not seen then
		seen = setmetatable({}, { __mode = "k" }) :: any
		seenBy[interior] = seen
	end
	local eye = at + Vector3.new(0, C.Fog.Eye, 0)
	local near: { { model: Instance, at: Vector3, d: number } } = {}
	for model in pieces do
		if not (seen :: any)[model] and model.Parent then
			local p = positionOf(model)
			if p then
				local d = (p - eye).Magnitude
				if d <= C.Fog.See then
					local px, pz = Rules.toLocal(plan, p.X, p.Z)
					if Rules.inside(plan, px, pz, p.Y) then
						table.insert(near, { model = model, at = p, d = d })
					end
				end
			end
		end
	end
	table.sort(near, function(a, b): boolean
		return a.d < b.d
	end)
	local shell = interior:FindFirstChild("Shell")
	for n = 1, math.min(#near, C.Fog.Most) do
		local item = near[n]
		local clear = if shell then clearBetween(shell, eye, item.at) else true
		if Rules.sees(item.d, clear) then
			(seen :: any)[item.model] = true
		end
	end
end

-- ── Starting ─────────────────────────────────────────────────────────────────

local function watchFolder(name: string, onAdd: ((Instance) -> ())?, onRemove: ((Instance) -> ())?)
	task.spawn(function()
		local folder = workspace:WaitForChild(name, 60)
		if not folder then
			return
		end
		folders[name] = folder
		if onAdd then
			for _, child in folder:GetChildren() do
				onAdd(child)
			end
			folder.ChildAdded:Connect(onAdd)
		end
		if onRemove then
			folder.ChildRemoved:Connect(onRemove)
		end
	end)
end

local function watchTag(tag: string, add: (Instance) -> (), remove: (Instance) -> ())
	for _, thing in CollectionService:GetTagged(tag) do
		add(thing)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(remove)
end

function SandboxMapData.start()
	if started then
		return
	end
	started = true
	Net.get("Moving").OnClientEvent:Connect(function(kind: any, view: any)
		if kind == "state" then
			move = if type(view) == "table" then view else nil
			if move == nil then
				asked = false
			end
		end
	end)
	watchFolder("Moves", function(child: Instance)
		if child:IsA("Model") then
			interiors[child] = true
		end
	end, function(child: Instance)
		interiors[child] = nil
		plans[child] = nil
		seenBy[child] = nil
	end)
	watchFolder("Npcs", nil, nil)
	watchFolder("Zombies", nil, nil)
	watchFolder("Cars", nil, nil)
	watchTag(Config.Loot.Tag, function(thing: Instance)
		pieces[thing] = true
	end, function(thing: Instance)
		pieces[thing] = nil
	end)
	for tag in C.Danger do
		watchTag(tag, function(thing: Instance)
			dangers[thing] = tag
		end, function(thing: Instance)
			dangers[thing] = nil
		end)
	end
	task.spawn(function()
		while true do
			task.wait(C.Fog.Every)
			local ok, err = pcall(SandboxMapData.look :: any)
			if not ok then
				warn(`[SandboxMapData] {err}`)
			end
		end
	end)
end

return SandboxMapData
