--!strict
-- 6.23 (from Codex's codex/cargo-missions-fix): the real server/Cargo.luau in the Luau CLI (tests/run_tests.py builds
-- it as CargoServer.luau over tests/runtime/CargoRuntime.luau's mocks): a stop whose person or pieces fail to build
-- (an NPC that could not spawn, a model that could not be made) is undone and built again on the next tick, its
-- error still reaching the job's tick guard; the pieces already carried and a stop that came meanwhile are kept; a
-- bus/ambulance passenger whose rider fails to spawn stays in the vehicle. Prompts are fired through their own
-- callbacks. No physics, no proximity distances: no substitute for a Studio playtest.
local Runtime = require("./CargoRuntime")
local Mock = Runtime.Mock
local Cargo = require("./CargoServer")

local failures = 0
local function check(name: string, ok: boolean)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name)
	end
end

local nextUser = 0
local function courier(): any
	nextUser += 1
	local character = Mock.Instance.new("Model")
	character.Parent = Mock.workspace
	local root = Mock.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = character
	character.PrimaryPart = root
	local humanoid = Mock.Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.Parent = character
	local player = Mock.Instance.new("Player")
	player.UserId = nextUser
	player.Name = `Courier{nextUser}`
	player.Character = character
	player.Parent = Mock.workspace
	return player
end

-- A foot run of `total` pizzas (no bag: they go in the hands), or with kind "kid" a school run (the bus, board stops).
local function run(total: number, kind: string?): (any, any)
	local player = courier()
	local session = Cargo.begin(player, {
		kind = kind or "crate", look = if kind == "kid" then "kid" else "pizza", piece = "pizza", plural = "pizzas",
		total = total, handles = kind == nil, foot = kind == nil,
		allowed = function(by)
			return by == player
		end,
		changed = function() end,
	} :: any)
	return session, player
end

local function plan(stage: string, needed: number, person: boolean?): any
	return {
		index = if stage == "pickup" then 1 else 2,
		stage = stage, mode = "carry", needed = needed, order = 1, hold = 0, keep = 0,
		park = Mock.Vector3.zero, pile = Mock.Vector3.zero, facing = Mock.Vector3.zAxis,
		person = if person then { name = if stage == "pickup" then "Cook" else "Customer" } else nil,
		dests = if stage == "pickup" then table.create(needed, 2) else nil,
	}
end

local function fire(prompt: any, player: any)
	local callback = prompt and prompt.TriggeredCallback
	assert(callback, "the prompt has no Triggered callback")
	callback(player)
end

local function held(session: any, player: any): number
	local hands = session.held[player]
	return if hands then #hands.pieces else 0
end

-- Picks the pile up through its prompt (one piece a press); deliver hands it all over at the drop.
local function pickUp(session: any, player: any, count: number)
	for _ = 1, count do
		fire(session.pilePrompt, player)
	end
	check("pickup done: the pile in the hands", Cargo.stopDone(session) and held(session, player) == count and #session.pile == 0)
end

local function deliver(session: any, player: any, count: number)
	fire(session.pilePrompt, player)
	check("hand-over: everything delivered to its stop", Cargo.stopDone(session) and held(session, player) == 0
		and Cargo.deliveredOf(session, 1) == count)
end

-- An ordinary foot order: built, picked up, handed over.
do
	local session, player = run(2)
	Cargo.setStop(session, plan("pickup", 2, true))
	Cargo.update(session, 0.2)
	check("a pickup builds its clerk, pile and prompt", session.built and session.person ~= nil and #session.pile == 2
		and session.pilePrompt ~= nil)
	pickUp(session, player, 2)
	Cargo.setStop(session, plan("drop", 2, true))
	Cargo.update(session, 0.2)
	deliver(session, player, 2)
	Cargo.finish(session)
end

-- One failed NPC spawn used to leave busy = 1 and built = true for good: no pile, no prompt, never done, and no
-- error after the first tick (so the job's tick guard never ended it).
do
	local session, player = run(2)
	Cargo.setStop(session, plan("pickup", 2, true))
	Runtime.spawnFailures = 1
	local ok, err = pcall(Cargo.update, session, 0.2)
	check("a failed clerk spawn reaches the tick guard", not ok and string.find(tostring(err), "NPC spawn failed", 1, true) ~= nil)
	check("… gives busy back and is not built (no pile, no prompt)", session.busy == 0 and not session.built
		and session.pilePrompt == nil and #session.pile == 0 and session.person == nil)
	check("… and the pieces' counters are back", session.made == 0 and session.madeHere == 0)
	Cargo.update(session, 0.2)
	check("the next tick builds the pickup", session.built and session.pilePrompt ~= nil and #session.pile == 2
		and session.made == 2)
	pickUp(session, player, 2)
	-- At the drop: a failed receiver keeps what is carried and builds again.
	Cargo.setStop(session, plan("drop", 2, true))
	Runtime.spawnFailures = 1
	check("a failed receiver spawn reaches the tick guard", not pcall(Cargo.update, session, 0.2))
	check("… keeps the pieces in the hands and the counters", held(session, player) == 2 and session.made == 2
		and session.busy == 0 and not session.built)
	Cargo.update(session, 0.2)
	check("the next tick builds the drop", session.built and session.person ~= nil and session.pilePrompt ~= nil)
	deliver(session, player, 2)
	Cargo.finish(session)
end

-- How many Models one stop of `needed` pieces makes with a clerk (the clerk is one; the rest are the pieces').
local function modelsFor(needed: number): number
	local session = run(needed)
	Cargo.setStop(session, plan("pickup", needed, true))
	local before = Runtime.models
	Cargo.update(session, 0.2)
	local made = Runtime.models - before
	Cargo.finish(session)
	return made
end

-- Another courier at the same shop puts this pile in a side slot. A piece failing half-way undoes the clerk, the
-- pieces made, the slot's shift and the counters; the retry takes one side slot and makes exactly the order's pieces.
do
	local perPiece = (modelsFor(2) - 1) / 2
	local other = run(2)
	Cargo.setStop(other, plan("pickup", 2))
	Cargo.update(other, 0.2)
	local session, player = run(3)
	local pickup = plan("pickup", 3, true)
	pickup.personAt = Mock.Vector3.zero
	Cargo.setStop(session, pickup)
	local before = #Mock.workspace:GetDescendants()
	Runtime.failModelAfter = 1 + perPiece -- the clerk and the first pizza are made, the second fails
	local ok = pcall(Cargo.update, session, 0.2)
	check("a piece failing half-way reaches the tick guard and is not built", not ok and not session.built
		and #session.props == 0 and #session.pile == 0 and session.pilePrompt == nil)
	check("… leaves nothing behind in the world", #Mock.workspace:GetDescendants() == before)
	check("… and the counters, the pile and the clerk's spot are back", session.made == 0 and session.madeHere == 0
		and pickup.pile.Magnitude == 0 and pickup.personAt.Magnitude == 0 and session.anchor == nil and session.slot == 0)
	Cargo.update(session, 0.2)
	check("the retry takes one side slot and makes exactly 3 pieces", session.built and #session.pile == 3
		and session.made == 3 and session.madeHere == 3 and session.slot == 1 and pickup.pile.Magnitude > 0)
	check("… each going to its stop for its order", session.pile[1].dest == 2 and session.pile[3].dest == 2
		and session.pile[3].order == 1)
	fire(session.pilePrompt, player)
	check("its prompt picks a piece up", held(session, player) == 1 and #session.pile == 2)
	Cargo.finish(session)
	Cargo.finish(other)
end

-- A pallet pickup's pallets are Loose pieces with prompts: a failure half-way removes them and their prompts.
do
	local session = run(3)
	local pickup = plan("pickup", 3)
	pickup.mode = "pallet"
	pickup.kind, pickup.look = "pallet", "pallet"
	pickup.staging = { Mock.Vector3.new(4, 0, 0), Mock.Vector3.new(8, 0, 0), Mock.Vector3.new(12, 0, 0) }
	Cargo.setStop(session, pickup)
	local before = #Mock.workspace:GetDescendants()
	local counted = Runtime.models
	Cargo.update(session, 0.2)
	local perPallet = (Runtime.models - counted) / 3
	Cargo.finish(session)
	session = run(3)
	Cargo.setStop(session, pickup)
	before = #Mock.workspace:GetDescendants()
	Runtime.failModelAfter = perPallet -- the first pallet is made, the second fails
	local ok = pcall(Cargo.update, session, 0.2)
	check("a pallet failing half-way removes the pallets made and their prompts", not ok and not session.built
		and #session.loose == 0 and #Mock.workspace:GetDescendants() == before)
	Cargo.update(session, 0.2)
	check("the retry lays out exactly 3 pallets", session.built and #session.loose == 3 and session.made == 3)
	Cargo.finish(session)
end

-- A spawn may yield, and the stop may change meanwhile: the old visit's failure keeps the new stop as it is.
do
	local session = run(2)
	Cargo.setStop(session, plan("pickup", 2, true))
	local replacement = plan("drop", 2)
	Runtime.onSpawn = function()
		Cargo.setStop(session, replacement, true)
		Cargo.update(session, 0.2)
		Runtime.spawnFailures = 1
	end
	check("the old visit's failure still reaches the tick guard", not pcall(Cargo.update, session, 0.2))
	check("… and leaves the new stop built", session.plan == replacement and session.built and session.pilePrompt ~= nil
		and session.busy == 0)
	Cargo.finish(session)
end

-- A failure that stays must reach the tick guard on every tick (Config.Jobs.TickFails in a row end the job).
do
	local session = run(2)
	Cargo.setStop(session, plan("pickup", 2, true))
	Runtime.spawnFailures = 3
	local attempts = Runtime.spawnAttempts
	for tick = 1, 3 do
		check(`a lasting failure is reported on tick {tick}`, not pcall(Cargo.update, session, 0.2) and session.busy == 0
			and not session.built)
	end
	check("… and every tick tries again", Runtime.spawnAttempts == attempts + 3)
	Runtime.spawnFailures = 0
	Cargo.finish(session)
end

-- A school run's drop (board): a kid whose rider fails to spawn stays in the bus (it used to be lost on the way out,
-- the drop then never done), and the error reaches the tick guard.
do
	local session, player = run(2, "kid")
	Runtime.car = Runtime.parkedCar(player)
	Cargo.fill(session, 2)
	local drop = plan("drop", 2)
	drop.mode = "board"
	Cargo.setStop(session, drop)
	Runtime.spawnFailures = 1
	check("a kid's failed spawn reaches the tick guard", not pcall(Cargo.update, session, 0.2))
	check("… and the kid stays in the vehicle", session.built and #session.load == 2 and #session.walking == 0
		and session.busy == 0)
	session.nextKid = 0
	Cargo.update(session, 0.2)
	check("the next try lets the kid off", #session.load == 1 and #session.walking == 1)
	Cargo.finish(session)
	Runtime.car = nil
end

assert(failures == 0, `{failures} cargo runtime checks failed`)
print("ALL CHECKS PASSED")
