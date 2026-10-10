--!strict
-- Real server/Cargo pickup, backpack and hand-over flow, including transient and persistent build failures.
-- Services are mocked; this is not a physics / proximity-distance test or a substitute for a Studio playtest.
local Runtime = require("./CargoRuntime")
local Mock = Runtime.Mock
local Cargo = require("./CargoServer")

local failures = 0
local function check(name: string, ok: boolean)
	if ok then print("ok    " .. name) else failures += 1; print("FAIL  " .. name) end
end

local nextUser = 0
local function run()
	nextUser += 1
	local character = Mock.Instance.new("Model")
	character.Parent = Mock.workspace
	local root = Mock.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = character
	local humanoid = Mock.Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.Parent = character
	local player = Mock.Instance.new("Player")
	player.UserId = nextUser
	player.Character = character
	player.Parent = Mock.workspace
	local session = Cargo.begin(player, {
		kind = "crate", look = "pizza", piece = "pizza", plural = "pizzas", total = 3,
		foot = true, pack = 1, allowed = function(by) return by == player end, changed = function() end,
	})
	return session, player
end

local function plan(stage: string, person: boolean?)
	return {
		index = if stage == "pickup" then 1 else 2,
		stage = stage, mode = "carry", needed = 3, order = 1,
		park = Mock.Vector3.zero, pile = Mock.Vector3.zero, facing = Mock.Vector3.zAxis,
		person = if person then { name = "Cook" } else nil,
		dests = if stage == "pickup" then { 2, 2, 2 } else nil,
	}
end

local function pickUp(session, player)
	for _ = 1, 3 do session.pilePrompt.trigger(player) end
	check("pickup completes with two in hand and one in backpack", Cargo.stopDone(session)
		and #session.held[player].pieces == 2 and #session.pack == 1)
	check("backpack attributes match the server contents", player:GetAttribute("PackCount") == 1
		and player:GetAttribute("PackRoom") == 1)
end

local function deliver(session, player)
	session.pilePrompt.trigger(player)
	check("hand over gives both hands and backpack to the correct stop", Cargo.stopDone(session)
		and session.held[player] == nil and #session.pack == 0 and Cargo.deliveredOf(session, 1) == 3)
	Cargo.finish(session)
end

-- A normal order uses the generated prompt callback, not an exposed private helper.
do
	local session, player = run()
	Cargo.setStop(session, plan("pickup"))
	Cargo.update(session, 0.2)
	pickUp(session, player)
	Cargo.setStop(session, plan("drop"))
	Cargo.update(session, 0.2)
	deliver(session, player)
end

-- One NPC failure previously latched busy = 1 and built = true forever, with no prompt and no retry.
do
	local session, player = run()
	Cargo.setStop(session, plan("pickup", true))
	Runtime.spawnFailures = 1
	local ok, err = pcall(Cargo.update, session, 0.2)
	check("NPC error reaches Jobs' tick guard", not ok and string.find(tostring(err), "NPC spawn failed", 1, true) ~= nil)
	check("failed NPC releases busy and the build latch", session.busy == 0 and not session.built
		and session.pilePrompt == nil and #session.pile == 0)
	Cargo.update(session, 0.2)
	check("next tick rebuilds a usable pickup", session.built and session.pilePrompt.Enabled and #session.pile == 3)
	pickUp(session, player)
	-- A drop retry must preserve the cargo already in the player's hands and backpack.
	Cargo.setStop(session, plan("drop", true))
	Runtime.spawnFailures = 1
	check("drop build also reports its error", not pcall(Cargo.update, session, 0.2))
	check("failed drop keeps the carried order and its counters", #session.held[player].pieces == 2
		and #session.pack == 1 and session.made == 3 and session.madeHere == 0)
	Cargo.update(session, 0.2)
	deliver(session, player)
end

-- Another courier at the same shop forces a side slot. A mid-build failure must undo the shift and partial pile.
do
	local other = run()
	Cargo.setStop(other, plan("pickup"))
	Cargo.update(other, 0.2)
	local session, player = run()
	local pickup = plan("pickup", true)
	pickup.personAt = Mock.Vector3.zero
	Cargo.setStop(session, pickup)
	local before = #Mock.workspace:GetDescendants()
	Runtime.failModelAfter = 2 -- the clerk and first pizza succeed, the second pizza fails
	local ok = pcall(Cargo.update, session, 0.2)
	check("partial build reports failure and destroys its clerk, pile and cargo", not ok and not session.built
		and #session.props == 0 and #session.pile == 0 and session.pilePrompt == nil
		and #Mock.workspace:GetDescendants() == before)
	check("partial build restores destination counters and side-slot coordinates", session.made == 0
		and session.madeHere == 0 and session.nextVariant == 0 and pickup.pile.Magnitude == 0
		and pickup.personAt.Magnitude == 0 and session.anchor == nil)
	Cargo.update(session, 0.2)
	check("retry chooses one side slot and creates exactly the order's three pieces", #session.pile == 3
		and session.made == 3 and session.madeHere == 3 and session.slot == 1)
	check("retry keeps piece destinations and order IDs", session.pile[1].dest == 2
		and session.pile[2].dest == 2 and session.pile[3].dest == 2 and session.pile[3].order == 1)
	pickUp(session, player)
	Cargo.finish(session)
	Cargo.finish(other)
end

-- A persistent failure must continue to reach Jobs on every tick so its existing failure limit can end the job.
do
	local session = run()
	local pickup = plan("pickup")
	pickup.mode = "pallet"
	pickup.kind, pickup.look = "pallet", "pallet"
	Cargo.setStop(session, pickup)
	local before = #Mock.workspace:GetDescendants()
	Runtime.failModelAfter = 1 -- the first pallet is already a Loose piece when the second fails
	local ok = pcall(Cargo.update, session, 0.2)
	check("failed pallet build removes its loose pieces and their prompts", not ok and not session.built
		and #session.loose == 0 and #Mock.workspace:GetDescendants() == before)
	Cargo.update(session, 0.2)
	check("pallet retry creates exactly three pallets without duplicates", session.built
		and #session.loose == 3 and session.made == 3)
	Cargo.finish(session)
end

-- A yielding spawn may finish after the owner has changed stops. Its error must not erase the new stop.
do
	local session = run()
	Cargo.setStop(session, plan("pickup", true))
	local replacement = plan("drop")
	Runtime.onSpawn = function()
		Cargo.setStop(session, replacement, true)
		Cargo.update(session, 0.2)
		Runtime.spawnFailures = 1
	end
	check("old visit's spawn failure still reports the error", not pcall(Cargo.update, session, 0.2))
	check("old visit's rollback preserves the replacement stop", session.plan == replacement
		and session.built and session.pilePrompt ~= nil and session.busy == 0)
	Cargo.finish(session)
end

-- A persistent failure must continue to reach Jobs on every tick so its existing failure limit can end the job.
do
	local session = run()
	Cargo.setStop(session, plan("pickup", true))
	Runtime.spawnFailures = 3
	local before = Runtime.spawnAttempts
	for i = 1, 3 do
		check(`persistent failure is reported on tick {i}`, not pcall(Cargo.update, session, 0.2)
			and session.busy == 0 and not session.built)
	end
	check("persistent failure never silently skips future attempts", Runtime.spawnAttempts == before + 3)
	Cargo.finish(session)
end

assert(failures == 0, `{failures} cargo runtime checks failed`)
print("ALL CHECKS PASSED")
