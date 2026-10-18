--!strict
-- 8.3 SANDBOX, the showroom's visitors (the owner: the warehouse should feel alive; Config.Visitors, the rules
-- shared/Visitors.luau). A few customers walk in through a warehouse's roller door (beside the van, off its unloading
-- lane), stroll between the stands with pieces on show, stop at a piece and look at it ("Ooh, a gramophone!"), and
-- leave the way they came. Now and then one makes an offer for the piece it looks at (server/VisitorOffers.luau: the
-- price, the card, ACCEPT / DECLINE) and waits for the owner's answer: sold, it carries a little box out.
--   * When: only to a warehouse with an owner and pieces on show; a group of 1 – 3 (Config.Visitors.Group) every
--     NearEvery s while the owner is at their warehouse (FirstWait s after they come), else every AwayEvery s; at most
--     PerHall in one warehouse by its level (the Garage: one) and Cap in the server.
--   * The bodies are server/Npcs.luau's (Npcs.spawn, its walk, its speech bubbles; the kinds' looks from
--     shared/Visitors.luau), in workspace.Npcs. The walk goes leg by leg (Npcs.walkTo, `through` between legs, giving
--     up when stuck) along shared/Visitors.luau's routes on the hall's grid: no PathfindingService. The hall is read
--     through shared/WarehouseLayout.luau at the plot's warehouse level (WarehouseLayout.site: its floor, door, door
--     path, stands and desk; the level server/Warehouse.luau built, Warehouse.level) and built again only when its level
--     or its stands change: a hall built again in place (a level bought) sends its visitors out on the new hall's ways,
--     and one that the new walls, a podium or the desk would catch (inside the new building's outline but on no free
--     cell of the new grid) is gone at once: never inside a wall.
--     In and out beside the van: from the street's side, turning in behind the van's back (past the bollards), through
--     the door's side.
--   * Never in the way: a visitor never stops in the door path, at the UPGRADES desk or within Clear studs of a player,
--     and moves on when a player comes that close while it looks (not while it waits for an answer); one visitor a
--     stand.
--   * Offers: once a visitor at most, at a stop, by its kind's chance, only while the owner is in the hall on foot
--     within Offer.Reach studs and VisitorOffers.ready (no offer open, Every s apart). The answer comes back through
--     VisitorOffers.onClosed: a line ("Pleasure doing business!"), and after a sale the box and the way out.
-- 10.4 (the warehouse in two, Config.Showroom): the visitors come for the SHOWROOM: only its pieces draw them (a
-- warehouse whose showroom shows nothing gets none) and only its stands are looked at; the collection hall's podiums
-- are only in their way. The owner's upgrade tree: Shop window (visitorRate) divides the waits between groups, VIP
-- buyers (vip) lets the VIP kind (Config.Showroom.Vip: Kind, Weight) come too.
-- One loop for every visitor, every hall and the offers' clocks (Config.Visitors.Tick s); Config.Visitors.On false: the
-- visitors there leave, none come. Nothing is done frame by frame.
--
--   Visitors.start()                the offers (VisitorOffers.start) and the loop
--   Visitors.step()                 one look of the loop (the tests')
--   Visitors.body(kind, name, at)   a visitor's body standing at CFrame `at` (Npcs.spawn in the kind's look; its
--                                   attribute Visitor the kind's id)
--   Visitors.carry(model)           the little box in its arms (after a sale)
--   Visitors.count(plot?)           the visitors here now (in plot `plot`'s warehouse)
--   Visitors.list()                 { { model, plot, kind, state, stand } } (a copy: the tests')
--   Visitors.useRandom(fn)          the dice: fn() → [0, 1) (a test's)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Rules = require(Shared.Visitors)
local CollectionRules = require(Shared.CollectionRules)
local SandboxMap = require(Shared.SandboxMap)
local WarehouseLayout = require(Shared.WarehouseLayout)
local Npcs = require(script.Parent.Npcs)
local Collection = require(script.Parent.Collection)
local SandboxPlots = require(script.Parent.SandboxPlots)
local Warehouse = require(script.Parent.Warehouse)
local Offers = require(script.Parent.VisitorOffers)
local Upgrades = require(script.Parent.Upgrades) -- 10.4: the tree's Shop window and VIP buyers

local Visitors = {}

local T = Config.Visitors
local FLOOR = WarehouseLayout.FloorTop

type Visitor = {
	id: number,
	plot: number,
	owner: Player,
	key: string, -- the hall it came into (its level and stands)
	hall: Rules.Hall,
	door: Rules.Doorway,
	side: number, -- the door's side it uses (−1 west, 1 east)
	kind: Rules.Kind,
	model: Model,
	state: string, -- "in" to a stand, "look" at a piece, "offer" waiting for the answer, "out" on its way out, "done"
	legs: { Vector3 },
	leg: number,
	walking: boolean,
	walkToken: number,
	misses: number,
	stand: number?,
	spot: Rules.Spot?,
	untilAt: number, -- os.clock() its look ends
	stops: number,
	seen: { [number]: boolean },
	offered: boolean,
	born: number,
}
type Plan = {
	owner: Player?,
	key: string?,
	level: number?, -- the warehouse's level its hall was built for
	hall: Rules.Hall?,
	due: number?, -- os.clock() the next group comes
	last: number?, -- os.clock() the last group came
	near: boolean, -- the owner at their warehouse at the last look
	queue: { number }, -- the group's walk-ins still to come (os.clock())
	shown: { [number]: CollectionRules.Entry }?, -- stand → the piece on show there (nil: look again)
}

local visitors: { Visitor } = {}
local plans: { [number]: Plan } = {}
local nextId = 0
local dice: (() -> number)? = nil
local random: Random? = nil
local started = false

local function roll(): number
	local fn = dice
	if fn then
		return fn()
	end
	local r = random
	if not r then
		r = Random.new()
		random = r
	end
	return (r :: Random):NextNumber()
end

local function rootOf(model: Instance?): BasePart?
	if not model then
		return nil
	end
	local root = if model:IsA("Model") then (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function flat(p: Vector3): Rules.Point
	return { x = p.X, z = p.Z }
end

local function at(p: Rules.Point): Vector3
	return Vector3.new(p.x, FLOOR, p.z)
end

-- ── The halls ──────────────────────────────────────────────────────────────

local function levelOf(id: number): number?
	local fn = (Warehouse :: any).level
	if type(fn) ~= "function" then
		return nil
	end
	local ok, level = pcall(fn, id)
	return if ok and type(level) == "number" then level else nil
end

-- 8.3: the plot at its warehouse's level (WarehouseLayout.site: that level's building; nil level: a plain Plot, 4).
local function siteOf(plot: SandboxMap.Plot, level: number?): SandboxMap.Plot
	return if level then WarehouseLayout.site(plot, level) or plot else plot
end

-- The hall's numbers (WarehouseLayout's, at the warehouse's level) with its first `stands` podiums (10.4: and its
-- first `show` showroom plinths: every one there is in the way, only the showroom's are looked at).
local function hallOf(plot: SandboxMap.Plot, stands: number, level: number?, show: number?): Rules.Hall
	local site = siteOf(plot, level)
	local inside = WarehouseLayout.inside(site)
	local door = WarehouseLayout.door(site)
	local podiums: { Rules.Podium } = {}
	local numbers: { number } = {}
	for i = 1, stands do
		table.insert(numbers, i)
	end
	for k = 1, show or 0 do
		table.insert(numbers, WarehouseLayout.ShowBase + k)
	end
	for _, i in numbers do
		local s = WarehouseLayout.stand(site, i)
		if s then
			table.insert(podiums, { index = i, x = s.x, z = s.z, sx = s.sx, sz = s.sz, yaw = s.yaw })
		end
	end
	local deskOk, desk = pcall(WarehouseLayout.terminal, site)
	local path = WarehouseLayout.doorPath(site)
	return Rules.hall({
		inside = { x0 = inside.x0, x1 = inside.x1, z0 = inside.z0, z1 = inside.z1 },
		door = { x = door.x, z = door.z, width = door.width },
		doorPath = { x0 = path.x0, x1 = path.x1, z0 = path.z0, z1 = path.z1 },
		desk = if deskOk and type(desk) == "table" then { index = 0, x = desk.x, z = desk.z, sx = desk.sx, sz = desk.sz, yaw = desk.yaw } else nil,
		stands = podiums,
	})
end

local function planOf(id: number): Plan
	local plan = plans[id]
	if not plan then
		plan = { near = false, queue = {} }
		plans[id] = plan
	end
	return plan :: Plan
end

-- The pieces on show in the owner's SHOWROOM now (stand → piece; 10.4: the collection hall's are not for sale: no
-- visitor looks at them), looked at again after their collection changed.
local function shownOf(plan: Plan, owner: Player, show: number): { [number]: CollectionRules.Entry }
	local shown = plan.shown
	if shown then
		return shown
	end
	local fresh: { [number]: CollectionRules.Entry } = {}
	local base = WarehouseLayout.ShowBase
	for _, entry in Collection.stock(owner) do
		local stand = entry.stand
		if stand ~= nil and stand > base and stand <= base + show then
			fresh[stand] = entry
		end
	end
	plan.shown = fresh
	return fresh
end

-- Is the owner at their warehouse (within Near studs of its walls)?
local function ownerNear(owner: Player, plot: SandboxMap.Plot, level: number?): boolean
	local root = rootOf(owner.Character)
	if not root then
		return false
	end
	local box = WarehouseLayout.outline(siteOf(plot, level))
	local p = root.Position
	return p.X >= box.x0 - T.Near and p.X <= box.x1 + T.Near and p.Z >= box.z0 - T.Near and p.Z <= box.z1 + T.Near
end

local function countIn(id: number): number
	local n = 0
	for _, v in visitors do
		if v.plot == id and v.state ~= "done" then
			n += 1
		end
	end
	return n
end

-- ── A visitor's walk ───────────────────────────────────────────────────────

-- The next leg (Npcs.walkTo): through the corners without a halt; a leg that fails (stuck, too long) is skipped, three
-- and the walk is over where it stands.
local function go(v: Visitor)
	v.walkToken += 1
	local token = v.walkToken
	local last = v.leg >= #v.legs
	v.walking = true
	Npcs.walkTo(v.model, v.legs[v.leg], function(ok: boolean)
		if v.walkToken ~= token or v.state == "done" then
			return
		end
		if not ok then
			v.misses += 1
		end
		if v.leg < #v.legs and v.misses < 3 then
			v.leg += 1
			go(v)
		else
			v.walking = false
		end
	end, nil, { through = not last, stuck = T.Stuck, near = if last then 1.2 else 2, jump = false })
end

local function walk(v: Visitor, points: { Rules.Point })
	local legs: { Vector3 } = {}
	for _, p in points do
		table.insert(legs, at(p))
	end
	v.legs, v.leg, v.misses = legs, 1, 0
	if #legs == 0 then
		v.walking = false
		return
	end
	go(v)
end

local function where(v: Visitor): Rules.Point
	local root = rootOf(v.model)
	return if root then flat(root.Position) else v.door.inside
end

local function remove(v: Visitor)
	if v.state == "done" then
		return
	end
	v.state = "done"
	v.walkToken += 1
	local offer = Offers.current(v.owner)
	if offer and offer.token == v.id then
		Offers.close(v.owner, "left")
	end
	Npcs.remove(v.model)
end

-- Out the way it came (`again`: on new ways, already on its way out): inside the hall to the door, through it and
-- behind the van's back; from outside the hall straight off.
local function leave(v: Visitor, again: boolean?)
	if v.state == "done" or (v.state == "out" and not again) then
		return
	end
	v.model:SetAttribute("Busy", nil)
	local offer = Offers.current(v.owner)
	if offer and offer.token == v.id then
		Offers.close(v.owner, "left")
	end
	v.state, v.stand, v.spot = "out", nil, nil
	local here = where(v)
	local r = v.hall.input.inside
	local legs: { Rules.Point } = {}
	if here.x >= r.x0 and here.x <= r.x1 and here.z >= r.z0 and here.z <= r.z1 then
		legs = Rules.route(v.hall, here, v.door.inside) or { v.door.inside }
		table.insert(legs, v.door.threshold)
	elseif here.z < v.door.threshold.z then
		-- (outside the hall but beside or behind it: a smaller one built round where it stood) round its nearer side
		local side = if here.x < v.hall.input.door.x then -1 else 1
		local x = if side < 0 then math.min(here.x, r.x0 - 3) else math.max(here.x, r.x1 + 3)
		v.side, v.door = side, Rules.doorway(v.hall, side)
		table.insert(legs, { x = x, z = here.z })
		table.insert(legs, { x = x, z = v.door.approach.z })
	end
	table.insert(legs, v.door.approach)
	table.insert(legs, v.door.outside)
	walk(v, legs)
end

-- The plot's hall was built again (a level bought or lost, other stands): every visitor still there goes on the new
-- hall's ways; one that the new walls, a podium or the desk would catch is gone at once.
local function rebuilt(plot: SandboxMap.Plot, plan: Plan)
	local hall = plan.hall
	local key = plan.key
	if not hall or not key then
		return
	end
	local box = WarehouseLayout.outline(siteOf(plot, plan.level)) -- (the new building's walls round its floor)
	for _, v in visitors do
		if v.plot == plot.id and v.state ~= "done" and v.key ~= key then
			local here = where(v)
			local within = here.x >= box.x0 - 1 and here.x <= box.x1 + 1 and here.z >= box.z0 - 1 and here.z <= box.z1 + 1
			if within and not Rules.free(hall, here.x, here.z) then -- (in its walls, on a podium, at the desk: caught)
				remove(v)
			else
				v.hall, v.key = hall, key
				v.door = Rules.doorway(hall, v.side)
				leave(v, true)
			end
		end
	end
end

-- Is a player standing within Clear studs of the point?
local function crowded(p: Rules.Point, feet: { Vector3 }): boolean
	for _, f in feet do
		if (f.X - p.x) ^ 2 + (f.Z - p.z) ^ 2 < T.Clear * T.Clear then
			return true
		end
	end
	return false
end

-- A stand to look at next: one with a piece on show, not seen yet, nobody else's, its spot free of players and on a
-- way from here. → stand, spot, legs (nil: none left).
local function pickStand(v: Visitor, plan: Plan, feet: { Vector3 }, from: Rules.Point): (number?, Rules.Spot?, { Rules.Point }?)
	local taken: { [number]: boolean } = {}
	for _, other in visitors do
		if other ~= v and other.plot == v.plot and other.stand ~= nil and other.state ~= "out" and other.state ~= "done" then
			taken[other.stand :: number] = true
		end
	end
	local options: { number } = {}
	for stand in shownOf(plan, v.owner, Collection.showStands(v.owner)) do
		if not v.seen[stand] and not taken[stand] then
			table.insert(options, stand)
		end
	end
	table.sort(options)
	while #options > 0 do
		local stand = table.remove(options, math.floor(roll() * #options) + 1) :: number
		local spot = Rules.spot(v.hall, stand, roll())
		if spot and not crowded({ x = spot.x, z = spot.z }, feet) then
			local legs = Rules.route(v.hall, from, { x = spot.x, z = spot.z })
			if legs then
				return stand, spot, legs
			end
		end
		v.seen[stand] = true -- (no spot or no way: not again)
	end
	return nil, nil, nil
end

local function nextStop(v: Visitor, feet: { Vector3 })
	v.model:SetAttribute("Busy", nil)
	local plan = plans[v.plot]
	if v.stops <= 0 or not plan then
		leave(v)
		return
	end
	local stand, spot, legs = pickStand(v, plan, feet, where(v))
	if not stand or not spot or not legs then
		leave(v)
		return
	end
	v.stand, v.spot, v.state = stand, spot, "in"
	walk(v, legs)
end

-- May the visitor offer for this piece now: the owner in the hall on foot within Reach, no offer open, not broken?
local function offerOk(v: Visitor, entry: CollectionRules.Entry): boolean
	if not Offers.ready(v.owner) or CollectionRules.broken(entry) then
		return false
	end
	local character = v.owner.Character
	local root, mine = rootOf(character), rootOf(v.model)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not mine or (humanoid and humanoid.SeatPart) then
		return false
	end
	local p = root.Position
	local inside = v.hall.input.inside
	return (p - mine.Position).Magnitude <= T.Offer.Reach and p.X >= inside.x0 - 2 and p.X <= inside.x1 + 2 and p.Z >= inside.z0 - 2 and p.Z <= inside.z1 + 2
end

-- At the stand: look at its piece (and maybe say so), or make an offer for it.
local function arrive(v: Visitor, now: number, feet: { Vector3 })
	local plan = plans[v.plot]
	local stand, spot = v.stand, v.spot
	local entry = if plan and stand then shownOf(plan, v.owner, Collection.showStands(v.owner))[stand] else nil
	if not entry or not spot or not stand then
		nextStop(v, feet) -- (the piece went while it walked there)
		return
	end
	v.seen[stand] = true
	v.stops -= 1
	Npcs.face(v.model, Vector3.new(spot.faceX, FLOOR + 2, spot.faceZ))
	v.model:SetAttribute("Busy", true) -- (it looks at the piece, not at the players walking by: server/Npcs.luau greet)
	v.state, v.untilAt = "look", now + Rules.between(T.Look, roll())
	if not v.offered and roll() < Rules.offerChance(v.kind) and offerOk(v, entry) then
		local offer = Offers.make(v.owner, entry.uid, v.kind.id, nil, v.id)
		if offer then
			v.offered, v.state = true, "offer"
			v.model:SetAttribute("Busy", nil) -- (it turns to the owner: server/Npcs.luau greet)
			local line = Rules.say("offer", roll(), offer.name, offer.price)
			if line then
				Npcs.say(v.model, line, 7)
			end
			return
		end
	end
	if roll() < T.Talk then
		local line = Rules.say("look", roll(), entry.name)
		if line then
			Npcs.say(v.model, line)
		end
	end
end

-- The owner answered (or the offer closed otherwise): a word, then on; after a sale the box and the way out.
local function onClosed(_player: Player, offer: Offers.Offer, how: string, _money: number?)
	local v: Visitor? = nil
	for _, other in visitors do
		if other.id == offer.token then
			v = other
		end
	end
	if not v or v.state == "done" or v.state == "out" or how == "left" then
		return
	end
	local line = Rules.say(how, roll(), offer.name, offer.price)
	if line then
		Npcs.say(v.model, line)
	end
	if how == "sold" then
		Npcs.act(v.model, "take")
		Visitors.carry(v.model)
		v.stops = 0
	end
	v.state, v.untilAt = "look", os.clock() + 1.5 -- (a moment, then on: the loop)
end

-- ── Coming in ──────────────────────────────────────────────────────────────

local function spawnOne(plot: SandboxMap.Plot, plan: Plan, owner: Player, now: number, feet: { Vector3 })
	local hall = plan.hall
	local key = plan.key
	if not hall or not key or countIn(plot.id) >= Rules.perHall(plan.level) or #visitors >= T.Cap then
		return
	end
	local side = if roll() < 0.5 then -1 else 1
	local door = Rules.doorway(hall, side)
	-- (10.4: the tree's VIP buyers: the VIP kind comes too, Config.Showroom.Vip.Weight)
	local kind = Rules.pickKind(roll(), if Upgrades.effect(owner, "vip") >= 1 then { [Config.Showroom.Vip.Kind] = Config.Showroom.Vip.Weight } else nil)
	local name = Rules.pickName(kind, roll())
	local v: Visitor = {
		id = nextId + 1,
		plot = plot.id,
		owner = owner,
		key = key,
		hall = hall,
		door = door,
		side = side,
		kind = kind,
		model = (nil :: any), -- (its body once it has a stand to go to)
		state = "in",
		legs = {},
		leg = 1,
		walking = false,
		walkToken = 0,
		misses = 0,
		untilAt = now,
		stops = math.floor(Rules.between(T.Stops, roll()) + 0.5),
		seen = {},
		offered = false,
		born = now,
	}
	local stand, spot, legs = pickStand(v, plan, feet, door.inside)
	if not stand or not spot or not legs then
		return -- (nothing it could look at: it never comes)
	end
	local from = at(door.outside)
	local model = Visitors.body(kind, name, CFrame.lookAt(Vector3.new(from.X, SandboxMap.GroundTop, from.Z), Vector3.new(door.approach.x, SandboxMap.GroundTop, door.approach.z)))
	nextId += 1
	v.model, v.stand, v.spot = model, stand, spot
	table.insert(visitors, v)
	local route = { door.approach, door.threshold, door.inside }
	for _, p in legs do
		table.insert(route, p)
	end
	walk(v, route)
	local line = Rules.say("greet", roll())
	if line then
		Npcs.say(model, line)
	end
end

-- One warehouse's look: its owner, its hall, its pieces on show; the next group's time; a walk-in due.
local function plotStep(plot: SandboxMap.Plot, now: number, feet: { Vector3 })
	local plan = planOf(plot.id)
	local owner = SandboxPlots.owner(plot.id)
	if owner ~= plan.owner then
		plan.owner, plan.due, plan.near, plan.shown = owner, nil, false, nil
		table.clear(plan.queue)
	end
	local level = levelOf(plot.id)
	local stands = if owner and owner.Parent then Collection.stands(owner) else 0
	local show = if owner and owner.Parent then Collection.showStands(owner) else 0 -- 10.4: the showroom's
	local key = `{level or 0}:{stands}:{show}`
	if plan.key ~= key then
		plan.key, plan.level, plan.shown = key, level, nil
		plan.hall = hallOf(plot, stands, level, show)
		rebuilt(plot, plan) -- (the visitors still there on the new hall's ways)
	end
	if not T.On or not owner or not owner.Parent then
		table.clear(plan.queue)
		return
	end
	local near = ownerNear(owner, plot, level)
	if next(shownOf(plan, owner, show)) == nil then
		plan.due, plan.near = nil, near
		table.clear(plan.queue)
		return
	end
	-- 10.4: the tree's Shop window brings them more often (its rate divides the waits)
	local rate = math.max(0.25, Upgrades.effect(owner, "visitorRate"))
	if plan.due == nil or (near and not plan.near) then
		local wait = (if near then Rules.between(T.FirstWait, roll()) else Rules.gap(false, roll())) / rate
		local soon = math.max(now + wait, (plan.last or -math.huge) + T.NearEvery[1]) -- (an owner in and out: not a group each time)
		plan.due = if plan.due then math.min(plan.due :: number, soon) else soon
	end
	plan.near = near
	if #plan.queue > 0 and now >= plan.queue[1] then
		table.remove(plan.queue, 1)
		spawnOne(plot, plan, owner, now, feet)
	end
	if now >= (plan.due :: number) and #plan.queue == 0 then
		local room = math.min(Rules.perHall(plan.level) - countIn(plot.id), T.Cap - #visitors)
		for k = 0, math.min(room, Rules.groupSize(roll())) - 1 do
			table.insert(plan.queue, now + k * T.Stagger)
		end
		plan.due, plan.last = now + Rules.gap(near, roll()) / rate, now
	end
end

-- One visitor's look.
local function visitorStep(v: Visitor, now: number, feet: { Vector3 })
	if v.state == "done" then
		return
	end
	if not v.model.Parent or now - v.born > T.Life then
		remove(v)
		return
	end
	local plan = plans[v.plot]
	if v.state ~= "out" and (not T.On or not v.owner.Parent or SandboxPlots.owner(v.plot) ~= v.owner or not plan or plan.key ~= v.key) then
		leave(v) -- (off, the owner gone, the hall changed)
		return
	end
	if v.state == "in" then
		if not v.walking then
			arrive(v, now, feet)
		end
	elseif v.state == "look" then
		local here = where(v)
		if now >= v.untilAt or crowded(here, feet) then -- (a player steps up: it moves on, never in the way)
			nextStop(v, feet)
		end
	elseif v.state == "offer" then
		local offer = Offers.current(v.owner)
		if not offer or offer.token ~= v.id then
			v.state, v.untilAt = "look", now -- (closed without a word to it: on)
		end
	elseif v.state == "out" then
		if not v.walking then
			remove(v)
		end
	end
end

-- ── The API ────────────────────────────────────────────────────────────────

function Visitors.body(kind: Rules.Kind, name: string, standAt: CFrame): Model
	local model = Npcs.spawn(Rules.look(kind, name), standAt)
	model:SetAttribute("Visitor", kind.id)
	return model
end

function Visitors.carry(model: Model): BasePart?
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart")
	if not torso or not torso:IsA("BasePart") or model:FindFirstChild("VisitorBox") then
		return nil
	end
	local box = Instance.new("Part")
	box.Name = "VisitorBox"
	box.Size = Vector3.new(1.5, 1.1, 1.2)
	box.Color = Color3.fromRGB(196, 158, 108)
	box.Material = Enum.Material.Cardboard
	box.CFrame = torso.CFrame * CFrame.new(0, -0.35, -(torso.Size.Z / 2 + 0.62))
	local tape = Instance.new("Part")
	tape.Name = "Tape"
	tape.Size = Vector3.new(0.32, 1.12, 1.22)
	tape.Color = Color3.fromRGB(226, 206, 150)
	tape.Material = Enum.Material.SmoothPlastic
	tape.CFrame = box.CFrame
	for _, part in { box, tape } do
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = part
		weld.Parent = part
	end
	tape.Parent = box
	box.Parent = model
	return box
end

function Visitors.count(plot: number?): number
	local n = 0
	for _, v in visitors do
		if v.state ~= "done" and (plot == nil or v.plot == plot) then
			n += 1
		end
	end
	return n
end

function Visitors.list(): { { model: Model, plot: number, kind: string, state: string, stand: number? } }
	local out = {}
	for _, v in visitors do
		if v.state ~= "done" then
			table.insert(out, { model = v.model, plot = v.plot, kind = v.kind.id, state = v.state, stand = v.stand })
		end
	end
	return out
end

function Visitors.useRandom(fn: (() -> number)?)
	dice = fn
end

function Visitors.step()
	local now = os.clock()
	Offers.tick()
	local feet: { Vector3 } = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player.Character)
		if root then
			table.insert(feet, root.Position)
		end
	end
	for _, plot in SandboxMap.Plots do
		plotStep(plot, now, feet)
	end
	for index = #visitors, 1, -1 do
		local v = visitors[index]
		visitorStep(v, now, feet)
		if v.state == "done" then
			table.remove(visitors, index)
		end
	end
end

function Visitors.start()
	if started then
		return
	end
	started = true
	Offers.start()
	Offers.onClosed(onClosed)
	Collection.onChanged(function(player: Player)
		for _, plan in plans do
			if plan.owner == player then
				plan.shown = nil -- (looked at again at the next step)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(T.Tick)
			local ok, err = pcall(Visitors.step :: () -> ...any)
			if not ok then
				warn(`[Visitors] {err}`)
			end
		end
	end)
end

return Visitors
