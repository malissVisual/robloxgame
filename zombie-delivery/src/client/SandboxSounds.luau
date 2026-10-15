--!strict
-- 8.1 SANDBOX, the sandbox's own sounds (the owner: "make the sandbox sound right"; art/audio/sfx4.ogg's 8.1 part, until
-- it is up their stand-ins, shared/SoundSheet.luau Fallback; what plays when: shared/SoundPlan.luau,
-- Config.Soundscape.Sandbox). Heard from what the sandbox already sends, no hooks in its modules:
--   the "Collection" remote (server/Collection.luau)
--     state      one after the other (SoundPlan.collectionCues): a piece put on a stand (a soft thunk and a sparkle) or
--                taken down, pieces that came home (the trip home: a small fanfare; not when the move's result card
--                has just played its own jingle: the Moving remote's "result", StoredQuiet s before)
--     sold       the till's ka-ching
--   the State remote's money going up (SoundPlan.incomeClink): the stands' income, a soft coin clink, at most every
--                IncomeGap s, only while pieces are on show, never with the warehouse's window open
--                (client/WarehouseUi.luau isOpen) and not right after a sale (its money comes in then: SoldQuiet s)
--   every ZDC Sprinter near the camera (workspace.Cars, its SlideOpen attribute, server/Vehicles.luau): its sliding
--                door rolling open and slammed shut, 3D at the door (SoundPlan.slideSound)
--   the walk-in step: your feet onto a Sprinter's rear or side step (your Humanoid's floor changed: a ray down, solid
--                parts only, SoundPlan.isStep): a hollow clonk and the van's springs, at most every StepGap s
-- 8.3, the 8.2 features' feedback (SoundPlan.feedbackOf / feedbackCues / slot: the existing sheets' sounds; the stings
-- one after the other in one lane, never over each other, a burst of one kind is one):
--   the "CollectionBook" remote   a state with pieces new in the book: the discovery chime (after the trip home's
--                fanfare); a milestone paid: a fanfare (after the chime)
--   the "SandboxTasks" remote     a task done; a reward claimed (client/SandboxTasksUi.luau plays nothing itself now)
--   the "Collection" remote       ⭐ FILL BEST's answer ("bulk", "fillbest"): a few soft stand clicks (the state after it
--                then plays no stand_display); 💰 SELL…'s sale (a "sold" of 2 pieces or more): the till once, louder,
--                with the old ka-ching on top (one piece's sale: the till as before)
--   the money a claim, a milestone or a sale brought plays no income clink (SoldQuiet s); the move's result card's
--                jingle holds the lane too (SoundPlan.hold: the chime waits for it)
-- The rest of the sandbox's sound is client/SoundScape.luau's (the fields, the warehouse's hall, the farmstead's room,
-- Jinočany's far sounds, the room's echo, the Sprinter's back doors); client/Sounds.luau leaves the sandbox's money to this
-- module and plays everything (Sounds.play / playAt: the SOUND setting, the stand-ins).
-- 8.9, the newest features' own sounds (art/audio/sfx5.ogg; until it is up their stand-ins or silence): one entry for
-- every module, by the event's name (shared/SoundPlan.luau Events; Config.Soundscape.Danny, .Trade, .Auction):
--   * event(name, after?): the clipboard taken out and put away (client/DannyOrders.luau), Danny's whistle
--     (client/DannyBubble.luau), the auction's tick, gavel and "sold!" bell (client/AuctionUi.luau), and the hook for the
--     trade code (trade_sold, trade_offer, trade_price: client/TradeUi.luau and client/OfferCard.luau call it once their
--     fixes are in); never the same again within its gap; one that comes with a Notice (Events' notice) answers it.
--   * await(outcome): an answer awaited from the server (client/MoveHelperCard.luau: a piece given to Danny or taken
--     back, an order; the clipboard asked out: DannyOrders, his card), `outcome()` looked at every Poll s
--     (SoundPlan.answer): its event once it shows (the pen's tick, the cross-off, his chirp); its Notice came and nothing
--     changed Grace s later: the soft nope; nothing at all: given up after Answer s. Its Notice plays no notify (the
--     answer's sound says it).
--   * Sounds.answered (client/Sounds.luau asks it NoticeWait s after every Notice): true when an await claims that
--     Notice, or an event that comes with one played round it; its notify is left out then.
--   SandboxSounds.start()   listens (once; nothing when Config.Sandbox.On is false; client/Main.client.luau starts it)
--   SandboxSounds.event(name, after?) -> boolean   8.9 plays an event now (after: in that many s); false: none, too soon
--   SandboxSounds.await(outcome)                   8.9 an answer awaited (see above)
-- Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SoundPlan = require(Shared.SoundPlan)
local Sounds = require(script.Parent.Sounds)

local SandboxSounds = {}

local B = Config.Soundscape.Sandbox
local player = Players.LocalPlayer
local started = false

local collection: any = nil -- the last "Collection" state (nil: none yet)
local earning = false -- pieces on show earn (its income over 0)
local money: number? = nil -- the last State's money (nil: none yet)
local soldAt = -math.huge -- (8.3: a sale's, a claim's or a milestone's money: no income clink for it)
local resultAt = -math.huge
local clinkAt = -math.huge
local fillAt = -math.huge -- 8.3: ⭐ FILL BEST's answer (its clicks)
local lane = SoundPlan.lane() -- 8.3: the stings one after the other

-- Is the warehouse's window open (client/WarehouseUi.luau, when it is there)?
local function windowOpen(): boolean
	local module = script.Parent:FindFirstChild("WarehouseUi")
	if not module or not module:IsA("ModuleScript") then
		return false
	end
	local ok, open = pcall(function(): any
		return (require(module) :: any).isOpen()
	end)
	return ok and open == true
end

-- ── 8.3: the feedback's lane ────────────────────────────────────────────────

-- A kind's cues (SoundPlan.feedbackCues), when the lane lets it (SoundPlan.slot: never over a sting, a burst is one).
local function feedback(kind: string, count: number?)
	local now = os.clock()
	local at = SoundPlan.slot(lane, kind, now, count)
	if not at then
		return
	end
	for _, cue in SoundPlan.feedbackCues(kind, count) do
		local wait = at - now + cue.at
		if wait > 0.02 then
			task.delay(wait, Sounds.play, cue.name, cue.volume, cue.pitch)
		else
			Sounds.play(cue.name, cue.volume, cue.pitch)
		end
	end
end

-- ── The collection, a sale, the income ──────────────────────────────────────

local function onCollection(message: any)
	if type(message) ~= "table" then
		return
	end
	if message.kind == "state" then
		local was = collection
		collection = message
		earning = (tonumber(message.income) or 0) > 0
		for _, c in SoundPlan.collectionCues(was, message, os.clock() - resultAt, os.clock() - fillAt) do
			if c.name == "stored_fanfare" then
				feedback("stored") -- (8.3: in the lane, the book's chime after it)
			else
				Sounds.play(c.name, c.volume, c.pitch)
			end
		end
	elseif message.kind == "sold" then
		soldAt = os.clock()
		local kind, count = SoundPlan.feedbackOf("Collection", message)
		if kind then
			feedback(kind, count) -- (8.3: 💰 SELL…'s sale: the till once, a bigger ka-ching)
		else
			Sounds.play("sale_register", B.Sold)
		end
	elseif message.kind == "bulk" then
		local kind, count = SoundPlan.feedbackOf("Collection", message)
		if kind then
			fillAt = os.clock()
			feedback(kind, count) -- (8.3: ⭐ FILL BEST's clicks)
		end
	end
end

-- 8.3: the collection book's discoveries and milestones, the tasks done and claimed.
local function onBook(message: any)
	local kind, count = SoundPlan.feedbackOf("CollectionBook", message)
	if kind == "milestone" then
		soldAt = os.clock() -- (its money comes in: no income clink)
	end
	if kind then
		feedback(kind, count)
	end
end

local function onTasks(message: any)
	local kind, count = SoundPlan.feedbackOf("SandboxTasks", message)
	if kind == "claimed" then
		soldAt = os.clock()
	end
	if kind then
		feedback(kind, count)
	end
end

local function onState(state: any)
	if type(state) ~= "table" or type(state.money) ~= "number" then
		return
	end
	local was = money
	money = state.money
	if was == nil then
		return -- (the first State: nothing came in)
	end
	local now = os.clock()
	if SoundPlan.incomeClink(state.money - was, now, clinkAt, soldAt, windowOpen(), earning) then
		clinkAt = now
		Sounds.play("coin", B.Income, 0.94)
	end
end

-- ── The Sprinter's sliding door ────────────────────────────────────────────

local function watchCar(car: Instance)
	if not car:IsA("Model") then
		return
	end
	local was = car:GetAttribute("SlideOpen")
	car:GetAttributeChangedSignal("SlideOpen"):Connect(function()
		local now = car:GetAttribute("SlideOpen")
		local before = was
		was = now
		if type(before) ~= "boolean" or type(now) ~= "boolean" or now == before then
			return -- (set for the first time as it is built: no sound)
		end
		local chassis = car.PrimaryPart
		local point = chassis and chassis:FindFirstChild("SlidePoint")
		local at = if point and point:IsA("Attachment") then point.WorldPosition else car:GetPivot().Position
		Sounds.playAt(SoundPlan.slideSound(now), at, B.Slide, 1, B.SlideRange)
	end)
end

local function watchCars()
	local cars = workspace:WaitForChild("Cars", 60)
	if not cars then
		return
	end
	for _, car in cars:GetChildren() do
		watchCar(car)
	end
	cars.ChildAdded:Connect(watchCar)
end

-- ── The walk-in step ────────────────────────────────────────────────────────

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true -- (a step folded away is still there, not solid)

local function watchFeet(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local onStep = false
	local stepAt = -math.huge
	local skip: { Instance } = { character } -- (8.2 perf: the ray's filter made once a body, not at every floor change)
	humanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or humanoid.SeatPart ~= nil then
			onStep = false
			return
		end
		params.FilterDescendantsInstances = skip
		local reach = humanoid.HipHeight + root.Size.Y / 2 + 1
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), params)
		local now = hit ~= nil and SoundPlan.isStep(hit.Instance.Name) and hit.Instance:GetAttribute("SprinterDoor") ~= nil
		if now and not onStep and os.clock() - stepAt >= B.StepGap then
			stepAt = os.clock()
			Sounds.play("van_step_up", B.Step, 0.95 + math.random() * 0.1)
		end
		onStep = now
	end)
end

-- ── 8.9: the newest features' sounds (sfx5.ogg) ─────────────────────────────

type Await = { outcome: () -> string?, sent: number, noticed: number?, settled: boolean }

local playedAt: { [string]: number } = {} -- an event's last time (its gap)
local answeredAt = -math.huge -- the last event that comes with a Notice (its notify left out)
local awaits: { Await } = {}

function SandboxSounds.event(name: string, after: number?): boolean
	local e = SoundPlan.eventOf(name)
	if not e then
		return false
	end
	if after and after > 0.02 then
		task.delay(after, SandboxSounds.event, name)
		return true
	end
	local now = os.clock()
	local last = playedAt[name]
	if last and now - last < e.gap then
		return false
	end
	playedAt[name] = now
	if e.notice and Sounds.has(e.sound) then
		answeredAt = now -- (its Notice, just before or just after it: no notify under it)
	end
	Sounds.play(e.sound, e.volume, e.pitch)
	return true
end

-- Client/Sounds.luau asks NoticeWait s after a Notice that came at `at`: is it answered by a sound of ours?
local function answered(at: number): boolean
	if answeredAt >= at - Config.Soundscape.NoticeWait then
		return true -- (an event that comes with it played round it)
	end
	for _, a in awaits do
		if a.noticed == nil and a.sent <= at then
			a.noticed = at -- (the oldest answer awaited that had no Notice yet: this is its)
			return Sounds.has(SoundPlan.Events.danny_nope.sound) -- (it can still say no itself)
		end
	end
	return false
end
Sounds.answered = answered

function SandboxSounds.await(outcome: () -> string?)
	local a: Await = { outcome = outcome, sent = os.clock(), noticed = nil, settled = false }
	table.insert(awaits, a)
	local D = Config.Soundscape.Danny
	task.spawn(function()
		while true do
			task.wait(D.Poll)
			local now = os.clock()
			if not a.settled then
				local ok, got = pcall(a.outcome)
				local name, over = SoundPlan.answer(if ok then got else nil, a.sent, a.noticed, now)
				if name then
					SandboxSounds.event(name)
				end
				a.settled = over
				if over and (got == "" or name == nil or a.noticed ~= nil) then
					break -- (settled quietly, given up, or its Notice is in: nothing left to wait for)
				end
			elseif a.noticed ~= nil or now - a.sent >= D.Answer then
				break -- (its sound played; its Notice came, or never will)
			end
		end
		local index = table.find(awaits, a)
		if index then
			table.remove(awaits, index)
		end
	end)
end

function SandboxSounds.start()
	if started or not Config.Sandbox.On then
		return
	end
	started = true
	local listeners: { [string]: (any) -> () } = { Collection = onCollection, CollectionBook = onBook, SandboxTasks = onTasks } -- (8.3: the book, the tasks)
	for name, listener in listeners do
		task.spawn(function()
			local ok, remote = pcall(Net.get, name)
			if ok then
				remote.OnClientEvent:Connect(listener)
			else
				warn(`[SandboxSounds] no {name} remote: {remote}`)
			end
		end)
	end
	Net.get("State").OnClientEvent:Connect(onState)
	Net.get("Moving").OnClientEvent:Connect(function(kind: any)
		if kind == "result" then
			resultAt = os.clock() -- (its card plays its jingle: no fanfare for the pieces that came with it)
			SoundPlan.hold(lane, resultAt, SoundPlan.seconds("job_done")) -- (8.3: the book's chime waits for the jingle)
		end
	end)
	task.spawn(watchCars)
	if player.Character then
		task.spawn(watchFeet, player.Character)
	end
	player.CharacterAdded:Connect(watchFeet)
end

return SandboxSounds
