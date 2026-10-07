--!strict
-- 3.7: the first-day tutorial. Marge, the dispatcher (Config.Tutorial: an R15 person from server/Npcs.luau with a name
-- tag, the idle animation and a "Talk" prompt), stands at the depot by the job board. She is there for everybody.
--
-- A player whose profile.tutorial is false (a new save; PlayerData counts an older save with a delivery as done):
--   wait     until PLAY was pressed (Tutorial.onPlay when Main calls it; or their car came), then
--            Config.Tutorial.StartDelay s for the start screen to fade
--   welcome  her greeting (client/TutorialUi.luau shows the dialog at once, a marker over her). "Let's go" in the
--            dialog or talking to her (E): she gives the PHONE (5.0) and Jobs.startTutorialJob, the first delivery ON
--            FOOT (two letters on one street), as if taken from the board
--   board    no job could be made: take an ON FOOT job from the board (J)
--   job      a job runs: the client reads the Job payload for its hints (shared/TutorialSteps.luau)
--   retry    it failed or was cancelled (Jobs.onDelivered false, or the job vanished without a result): she offers
--            another, over the radio or when you talk to her
-- Jobs.onDelivered with ok (an ordinary job delivered and paid, whichever one): profile.tutorial = true, the
-- Config.Tutorial.Reward on top and her last pages about the rest of the game ("done"). "skip" ends it at once (no
-- reward). Talking to her afterwards gets a short line. A crew mate helping is fine: the job is the owner's.
-- Nothing is saved but profile.tutorial: leaving and coming back before the delivery starts again at the welcome.
--
-- Remote "Tutorial": server → client (phase, data?) with data.npc = her model (the marker), data.given (the job is
-- hers), data.reward (done), data.text (say); (nil) = over (skipped). Client → server: ("go") = her dialog's
-- "Let's go" / "Another job", ("skip").
-- 5.0, the phone: profile.phone = true when she gives you the first job (or the tutorial is skipped; a player without
-- the tutorial gets it at once), and the message ("phone", { npc }) right before the job's: client/Phone.luau shows
-- its "NEW PHONE" moment (TutorialUi ignores it: not a phase).
-- 5.1, Spoke & Chain: when a player reaches Career.BIKE_LEVEL while playing and owns no bike, Marge texts them
-- (Config.BikeShop.Unlock with the cheapest bike's price: the Tutorial remote's "message" with the GPS to the shop,
-- client/Phone.luau, and a toast). On PLAY between that level and the van's, still without a bike: her reminder
-- (the phone's messages are not saved).
-- 6.0, Lead & Co.: no free gun. Once a player has the pistol's price and no gun, Marge texts them (Config.Arms.Tip, the
-- GPS to the gun shop), once a session.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Career = require(Shared.Career)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local Map = require(Shared.Map)
local TransportRules = require(Shared.Transport)
local VanQuestRules = require(Shared.VanQuest)
local Net = require(Shared.Net)
local TutorialSteps = require(Shared.TutorialSteps)
local PlayerData = require(script.Parent.PlayerData)
local Jobs = require(script.Parent.Jobs)
local Vehicles = require(script.Parent.Vehicles)
local Npcs = require(script.Parent.Npcs)

local Tuning = Config.Tutorial
local Tutorial = {}

type Session = {
	phase: string, -- wait | welcome | board | job | retry
	readyAt: number?, -- wait: PLAY was pressed, she speaks at this os.clock()
	goneAt: number?, -- job: the job disappeared at (no onDelivered yet)
	nextGo: number, -- a double "go" (a click and a key) starts one job
	lastAsk: number, -- the remote's throttle
}

local sessions: { [Player]: Session } = {}
local talked: { [Player]: number } = {} -- the last Talk (E held down or spammed: one answer a second)
local remote: RemoteEvent
local notice: RemoteEvent
local marge: Model? = nil
local nextCheck = 0 -- when her model is checked again (rebuilt if it was removed)
local started = false

-- Does this player still have the tutorial ahead? (A Studio test runs it only with Config.Tutorial.InStudio.)
local function pending(player: Player): boolean
	local profile = PlayerData.get(player)
	-- (Outside Studio only a save that was read: a veteran whose save failed to load gets no first day.)
	return profile ~= nil
		and not profile.tutorial
		and if RunService:IsStudio() then Tuning.InStudio else PlayerData.loaded(player)
end

local function send(player: Player, phase: string?, data: { [string]: any }?)
	local out: { [string]: any } = data or {}
	out.npc = marge
	remote:FireClient(player, phase, if phase then out else nil)
end

local function bubble(text: string)
	local npc = marge
	if npc and npc.Parent then
		Npcs.say(npc, text)
	end
end

-- 5.0: the phone is yours (profile.phone; the state goes to the client) and the client hears it ("phone"). Once.
local function givePhone(player: Player)
	local profile = PlayerData.get(player)
	if not profile or profile.phone then
		return
	end
	profile.phone = true
	PlayerData.notify(player)
	send(player, "phone")
end

-- The tutorial is over for this player: delivered (with the reward and her last pages) or skipped.
local function finish(player: Player, delivered: boolean)
	local profile = PlayerData.get(player)
	sessions[player] = nil
	if not profile or profile.tutorial then
		return
	end
	profile.tutorial = true
	if delivered then
		PlayerData.addMoney(player, Tuning.Reward) -- (fires PlayerData.Changed: the HUD's money)
		notice:FireClient(player, `+${Tuning.Reward} from {Tuning.NpcName}: your first delivery!`)
		-- Her last pages a moment later, over the radio: the delivery's own result shows first.
		task.delay(Tuning.DoneDelay, function()
			if player.Parent then
				send(player, "done", { reward = Tuning.Reward })
			end
		end)
	else
		send(player, nil)
		notice:FireClient(player, `Tutorial skipped. {Tuning.NpcName} is by the job board if you need her.`)
		givePhone(player) -- 5.0: the phone all the same
	end
end

-- Her first job (Jobs.startTutorialJob), or the board when none could be made.
local function giveJob(player: Player, session: Session)
	local now = os.clock()
	if now < session.nextGo then
		return
	end
	session.nextGo = now + 1
	session.goneAt = nil
	if Jobs.active(player) then
		session.phase = "job"
		send(player, "job")
		return
	end
	givePhone(player) -- 5.0: "take this phone" (before the job's own dialog)
	local ok, given = pcall(Jobs.startTutorialJob, player)
	if not ok then
		warn(`[Tutorial] startTutorialJob: {given}`)
	end
	if ok and given == true then
		session.phase = "job"
		send(player, "job", { given = true })
		bubble(TutorialSteps.Bubble.give)
	else
		session.phase = "board"
		send(player, "board")
		bubble(TutorialSteps.Bubble.board)
	end
end

-- The Talk prompt (E at Marge).
local function onTalk(player: Player)
	local now = os.clock()
	if now - (talked[player] or 0) < 1 then
		return
	end
	talked[player] = now
	local npc = marge
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if npc and root and root:IsA("BasePart") then
		Npcs.glance(npc, root.Position)
	end
	local session = sessions[player]
	if not pending(player) or not session then
		send(player, "say", { text = TutorialSteps.Bubble.done })
		bubble(TutorialSteps.Bubble.done)
		return
	end
	if Jobs.active(player) then
		session.phase = "job"
		send(player, "say", { text = TutorialSteps.Bubble.busy })
		bubble(TutorialSteps.Bubble.busy)
		return
	end
	giveJob(player, session)
end

local function onRemote(player: Player, action: any)
	if type(action) ~= "string" then
		return
	end
	local session = sessions[player]
	if not session or not pending(player) then
		return
	end
	local now = os.clock()
	if now - session.lastAsk < 0.25 then
		return
	end
	session.lastAsk = now
	if action == "skip" then
		finish(player, false)
	elseif action == "go" then
		if session.phase == "welcome" or session.phase == "board" or session.phase == "retry" then
			giveJob(player, session)
		end
	end
end

-- Set on Jobs.onDelivered (chained): an ordinary job of `player` ended, delivered and paid (ok) or not.
local function onDelivered(player: Player, ok: boolean)
	local session = sessions[player]
	if not session or not pending(player) then
		return
	end
	if ok then
		finish(player, true)
	else
		session.phase = "retry"
		session.goneAt = nil
		send(player, "retry")
	end
end

-- ── Marge ──────────────────────────────────────────────────────────────────

local function spawnMarge()
	local depot = Map.Shops.depot
	local spot = Tuning.NpcSpot
	local feet = Vector3.new(depot.x + spot[1], Map.WalkTop, depot.z + spot[2])
	-- A dispatcher: a clerk's shirt, the company's yellow cap and vest, grey hair.
	local look = Npcs.look("clerk", Tuning.NpcName, Tuning.NpcTitle)
	look.hat, look.hatColor = "cap", { 255, 190, 60 }
	look.shirt, look.vest, look.pants = { 236, 236, 240 }, { 240, 170, 50 }, { 52, 56, 70 }
	look.hair, look.skin = { 160, 156, 150 }, { 241, 194, 160 }
	local ok, model = pcall(Npcs.spawn, look, CFrame.lookAt(feet, feet + Vector3.new(0, 0, 1)))
	if not ok or not model then
		warn(`[Tutorial] {Tuning.NpcName} could not be built: {model}`)
		return
	end
	model:SetAttribute("Dispatcher", true)
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TalkPrompt"
		prompt.ActionText = "Talk"
		prompt.ObjectText = `{Tuning.NpcName}, {Tuning.NpcTitle}`
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = Tuning.TalkRange
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = root
		prompt.Triggered:Connect(onTalk)
	end
	marge = model
end

-- ── The loop ───────────────────────────────────────────────────────────────

local function check(player: Player, session: Session, now: number)
	if session.phase == "wait" then
		if Jobs.active(player) then
			session.phase = "job" -- (took one from the board before she spoke)
			send(player, "job")
			return
		end
		if not session.readyAt and Vehicles.get(player) then
			session.readyAt = now + Tuning.StartDelay -- (a car came on PLAY: Main giveCar; 5.0: a new player has none)
		end
		local readyAt = session.readyAt
		if readyAt and now >= readyAt then
			session.phase = "welcome"
			send(player, "welcome")
		end
	elseif session.phase == "job" then
		if Jobs.active(player) then
			session.goneAt = nil
			return
		end
		-- Gone without onDelivered (a special job or a mission ended, an admin cancelled it): offer another.
		local goneAt = session.goneAt or now
		session.goneAt = goneAt
		if now - goneAt >= Tuning.RetryAfter then
			session.phase = "retry"
			session.goneAt = nil
			send(player, "retry")
		end
	elseif Jobs.active(player) then
		session.phase = "job" -- welcome / board / retry: a job taken from the board counts as well
		send(player, "job")
	end
end

local function update()
	local now = os.clock()
	if now >= nextCheck then
		nextCheck = now + 5
		local npc = marge
		if not npc or not npc.Parent then
			marge = nil
			task.spawn(spawnMarge) -- (Npcs.spawn may yield: the loop does not wait for it)
		end
	end
	for player, session in sessions do
		if not player.Parent then
			sessions[player] = nil
		elseif PlayerData.get(player) then
			if pending(player) then
				check(player, session, now)
			else
				sessions[player] = nil -- done (an older save, an admin, skipped): never shown
				givePhone(player) -- 5.0: no tutorial ahead (a Studio test without it, a save not read): the phone at once
			end
		end
	end
end

local function track(player: Player)
	if not sessions[player] then
		sessions[player] = { phase = "wait", nextGo = 0, lastAsk = 0 }
	end
end

-- ── 5.1: Marge about Spoke & Chain ─────────────────────────────────────────

local bikeLevels: { [Player]: number } = {} -- the level last seen while playing (from PLAY on)
local BIKE_DELAY = 8 -- seconds after PLAY before her reminder (after the welcome and Earl's text)

-- Does the player own a bike?
local function ownsBike(player: Player): boolean
	local profile = PlayerData.get(player)
	if profile then
		for id, owned in profile.cars do
			if owned and TransportRules.isBike(id) then
				return true
			end
		end
	end
	return false
end

-- Her text (the cheapest bike's price in it) and a toast; the phone sets the GPS to the shop.
local function tellBikes(player: Player, text: string)
	local cheapest: number? = nil
	for _, def in Config.Cars do
		if def.bike and (cheapest == nil or def.price < cheapest) then
			cheapest = def.price
		end
	end
	local shop = Map.Shops.bikes
	local words = string.gsub(text, "{price}", if cheapest then `${cheapest}` else "a few hundred")
	remote:FireClient(player, "message", { from = "Marge", text = words, gps = { x = shop.x, z = shop.z, id = "bikes" } })
	notice:FireClient(player, `📱 Marge: {words}`)
end

-- A level-up to the bikes' level while playing (PlayerData.Changed), without a bike: her text.
local function bikeCheck(player: Player)
	local before = bikeLevels[player]
	local profile = PlayerData.get(player)
	if before == nil or not profile then
		return
	end
	local level = Levels.levelFor(profile.xp)
	bikeLevels[player] = level
	if before < Career.BIKE_LEVEL and level >= Career.BIKE_LEVEL and not ownsBike(player) then
		tellBikes(player, Config.BikeShop.Unlock)
	end
end

-- ── 6.0: Marge about the pistol ────────────────────────────────────────────
-- No free gun (Config.Arms): once a player with the phone and the first day behind them has the pistol's price and
-- owns no gun, Marge texts them about Lead & Co. with the shop on the GPS. Once a session (from PLAY on).

local gunTold: { [Player]: boolean } = {}

local function gunCheck(player: Player)
	local profile = PlayerData.get(player)
	if gunTold[player] or bikeLevels[player] == nil or not profile or not profile.tutorial or not profile.phone then
		return
	end
	local pistol = Economy.findWeapon(Config.Arms.Starter)
	if not pistol or next(profile.weapons) ~= nil or profile.money < pistol.price then
		return
	end
	gunTold[player] = true
	local shop = Map.Shops.guns
	local words = string.gsub(Config.Arms.Tip, "{price}", `${pistol.price}`)
	remote:FireClient(player, "message", { from = "Marge", text = words, gps = { x = shop.x, z = shop.z, id = "guns" } })
	notice:FireClient(player, `📱 Marge: {words}`)
end

-- 6.0.1: Marge about the plastic bag (Kit "bag"): once a player with the phone and the first day behind them has its
-- price and no bag, she texts them about Last Stop Supplies with the shop on the GPS. Once a session; before the pistol.
local bagTold: { [Player]: boolean } = {}

local function bagCheck(player: Player): boolean
	local profile = PlayerData.get(player)
	if bagTold[player] or bikeLevels[player] == nil or not profile or not profile.tutorial or not profile.phone then
		return false
	end
	local bag: Config.KitDef? = nil
	for _, def in Config.Kit do
		if def.id == "bag" then
			bag = def
		end
	end
	if not bag or (profile.kit :: any)[bag.id] == true or profile.money < bag.price then
		return false
	end
	bagTold[player] = true
	local shop = Map.Shops.supplies
	local words = string.gsub(Config.Arms.BagTip, "{price}", `${bag.price}`)
	remote:FireClient(player, "message", { from = "Marge", text = words, gps = { x = shop.x, z = shop.z, id = "supplies" } })
	notice:FireClient(player, `📱 Marge: {words}`)
	return true
end

local function tips(player: Player)
	if not bagCheck(player) then
		gunCheck(player)
	end
end

-- PLAY was pressed (Main may call this from its Play handler; without it the arriving car tells the same).
function Tutorial.onPlay(player: Player)
	local session = sessions[player]
	if session and session.phase == "wait" and not session.readyAt then
		session.readyAt = os.clock() + Tuning.StartDelay
	end
	-- 5.1: from now on a level-up to the bikes' level brings Marge's text; between it and the van's, her reminder.
	local profile = PlayerData.get(player)
	local level = if profile then Levels.levelFor(profile.xp) else 1
	bikeLevels[player] = level
	task.delay(BIKE_DELAY + 4, tips, player) -- 6.0: the bag's (6.0.1) or the pistol's price in your pocket, none owned: her text
	if level >= Career.BIKE_LEVEL and level < VanQuestRules.level() and remote then
		task.delay(BIKE_DELAY, function()
			if player.Parent and not ownsBike(player) then
				tellBikes(player, Config.BikeShop.Reminder)
			end
		end)
	end
end

function Tutorial.start()
	if started then
		return
	end
	started = true
	remote = Net.get("Tutorial")
	notice = Net.get("Notice")
	remote.OnServerEvent:Connect(onRemote)
	-- Jobs.onDelivered belongs to server/Jobs.luau (3.7): chained, so another listener keeps working.
	local hooks = Jobs :: any
	local previous = hooks.onDelivered
	hooks.onDelivered = function(player: Player, ok: boolean)
		if previous then
			previous(player, ok)
		end
		onDelivered(player, ok == true)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		talked[player] = nil
		bikeLevels[player] = nil
		gunTold[player] = nil
		bagTold[player] = nil
	end)
	PlayerData.Changed:Connect(bikeCheck) -- 5.1: Marge about Spoke & Chain
	PlayerData.Changed:Connect(tips) -- 6.0: Marge about the pistol (6.0.1: the bag first)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	task.spawn(spawnMarge)
	nextCheck = os.clock() + 5
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(function()
				update()
			end)
			if not ok then
				warn(`[Tutorial] {err}`)
			end
		end
	end)
end

return Tutorial
