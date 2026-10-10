--!strict
-- 3.7: the first-day tutorial. Marge, the dispatcher (Config.Tutorial: an R15 person from server/Npcs.luau with a name
-- tag, the idle animation and a "Talk" prompt), stands at the depot by the job board. She is there for everybody.
--
-- 6.7, a tutorial that never annoys (the owner: "It should simply show with an arrow where things are in the menu,
-- then that you take one job, and you either say yes or skip tutorial. But don't automatically give a job."). A player
-- whose profile.tutorial is false (a new save; PlayerData counts an older save with a delivery as done):
--   wait     until PLAY was pressed (Tutorial.onPlay when Main calls it; or their car came), then
--            Config.Tutorial.StartDelay s for the start screen to fade
--   welcome  her one-page greeting shows on its own (client/TutorialUi.luau). SHOW ME ("tour" from the client) gives
--            the PHONE (5.0) and starts the arrow tour; SKIP TUTORIAL ("skip") ends it. Talking to her (E) shows the
--            greeting again.
--   tour     the client's arrow tour of the screen runs (client/TutorialArrow.luau). Its last page, TAKE A JOB
--            ("board"), opens the phone's JOBS; SKIP TUTORIAL ("skip") ends it.
--   board    she waits for your first job: any one, from the board or the phone (she gives none: Jobs.startTutorialJob
--            stays callable but unused). Talking to her: one page with OPEN THE BOARD ("say", board = true).
--   job      a job runs: the HUD's goal card shows the hints (shared/TutorialSteps.luau)
-- A failed or cancelled job (Jobs.onDelivered false, or the job vanished without a result) goes back to "board" with no
-- page of hers ("retry" is never sent any more). Jobs.onDelivered with ok, in any phase (whichever job, a crew mate
-- helping is fine: the job is the owner's): profile.tutorial = true, Config.Tutorial.Reward on top and a toast "First
-- delivery! +$50" ("done": no page). "skip" ends it at once (no reward). Talking to her afterwards gets a short line.
-- Nothing is saved but profile.tutorial: leaving and coming back before the first delivery starts again at the welcome;
-- a save that finished or skipped it never sees it again.
--
-- Remote "Tutorial": server → client (phase, data?) with data.npc = her model (the marker), data.reward (done),
-- data.text / data.board (say); (nil) = over (skipped). Client → server: ("tour") her welcome's SHOW ME (6.5's "go"
-- counts the same), ("board") the tour's TAKE A JOB, ("skip").
-- 5.0, the phone: profile.phone = true at SHOW ME (6.7; or when the tutorial ends, delivered or skipped; a player
-- without the tutorial gets it at once), and the message ("phone", { npc }): client/Phone.luau shows its "NEW PHONE"
-- moment (TutorialUi ignores it: not a phase; 6.7: the tour opens the phone itself, the moment's pop-up waits for it).
-- 5.1, Spoke & Chain (6.12.7: Dead End Motors' BIKES counter): when a player reaches Career.BIKE_LEVEL while playing
-- and owns no bike, Marge texts them (Config.BikeShop.Unlock with the cheapest bike's price: the Tutorial remote's
-- "message" with the GPS to the shop, client/Phone.luau, and a toast). On PLAY between that level and the van's, still without a bike: her reminder
-- (the phone's messages are not saved).
-- 6.13: her welcome showing (on its own, or when you talk to her first) is the onboarding funnel's WelcomeSeen
-- (server/Analytics.luau).
-- 6.0, Lead & Co.: no free gun; Marge texted a player with the pistol's price and no gun. 6.7: gone: every profile has
-- the pistol since 6.0.2 (server/PlayerData.luau newProfile, the starterKit flag), so that text could never come.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Career = require(Shared.Career)
local Config = require(Shared.Config)
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
	phase: string, -- wait | welcome | tour | board | job (6.7)
	readyAt: number?, -- wait: PLAY was pressed, she speaks at this os.clock()
	goneAt: number?, -- job: the job disappeared at (no onDelivered yet)
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

-- The tutorial is over for this player: the first delivery (with the reward) or skipped.
local function finish(player: Player, delivered: boolean)
	local profile = PlayerData.get(player)
	sessions[player] = nil
	if not profile or profile.tutorial then
		return
	end
	profile.tutorial = true
	givePhone(player) -- 5.0: the phone all the same (6.7: also after a first job taken before her welcome)
	if delivered then
		PlayerData.addMoney(player, Tuning.Reward, "TutorialReward") -- (fires PlayerData.Changed: the HUD's money)
		-- 6.7: a toast, no page (the delivery's own result shows); "done" ends the phase on the client
		notice:FireClient(player, `First delivery! +${Tuning.Reward} from {Tuning.NpcName}.`)
		send(player, "done", { reward = Tuning.Reward })
	else
		send(player, nil)
		notice:FireClient(player, `Tutorial skipped. {Tuning.NpcName} is by the job board if you need her.`)
	end
end

-- 6.7: SHOW ME: her phone (the tour opens it) and the arrow tour on the client.
local function startTour(player: Player, session: Session)
	givePhone(player)
	session.phase = "tour"
	send(player, "tour")
	bubble(TutorialSteps.Bubble.tour)
end

-- 6.7: she waits for your first job (any one; she gives none). A job that already runs counts at once.
local function toBoard(player: Player, session: Session)
	session.goneAt = nil
	if Jobs.active(player) then
		session.phase = "job"
		send(player, "job")
		return
	end
	session.phase = "board"
	send(player, "board")
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
	if session.phase == "wait" or session.phase == "welcome" then
		session.phase = "welcome" -- (6.7: her greeting again, or before PLAY's delay ran out)
		send(player, "welcome")
		PlayerData.track("step", player, "WelcomeSeen") -- 6.13 (once for life: a second time does nothing)
	elseif session.phase == "tour" then
		bubble(TutorialSteps.Bubble.tour) -- (the arrows are on screen: no page)
	else
		session.phase = "board"
		send(player, "say", { board = true, reward = Tuning.Reward })
		bubble(TutorialSteps.Bubble.board)
	end
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
	elseif action == "tour" or action == "go" then
		if session.phase == "welcome" then
			startTour(player, session)
		end
	elseif action == "board" then
		if session.phase == "welcome" or session.phase == "tour" then
			toBoard(player, session)
		end
	end
end

-- Set on Jobs.onDelivered (chained): a job of `player` ended, delivered and paid (ok) or not.
local function onDelivered(player: Player, ok: boolean)
	local session = sessions[player]
	if not session or not pending(player) then
		return
	end
	if ok then
		finish(player, true) -- 6.7: the first delivery of any job, in any phase
	else
		toBoard(player, session) -- 6.7: no page: the goal card says "Take your first job" again
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
			PlayerData.track("step", player, "WelcomeSeen") -- 6.13: the onboarding funnel
		end
	elseif session.phase == "job" then
		if Jobs.active(player) then
			session.goneAt = nil
			return
		end
		-- Gone without onDelivered (a special job or a mission ended, an admin cancelled it): back to "board".
		local goneAt = session.goneAt or now
		session.goneAt = goneAt
		if now - goneAt >= Tuning.RetryAfter then
			toBoard(player, session)
		end
	elseif Jobs.active(player) then
		session.phase = "job" -- welcome / tour / board: a job taken from the board or the phone counts
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
		sessions[player] = { phase = "wait", lastAsk = 0 }
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
	-- 6.4: a level that opens a bag you don't own (Config.Kit `extra`): Marge texts once, the shop on the GPS (the
	-- biggest such bag when one level opens two)
	local opened: Config.KitDef? = nil
	for _, def in Config.Kit do
		if def.extra and def.level > before and def.level <= level and not profile.bags[def.id] then -- (6.23: this game's)
			opened = def
		end
	end
	if opened and remote then
		local shop = Map.Shops.bags -- 6.6: the bags are sold at ZDC Bags, the depot's kiosk
		local words = string.gsub(string.gsub(string.gsub(Config.Courier.BagUnlock, "{name}", opened.name), "{room}", tostring(opened.extra)), "{price}", `${opened.price}`)
		remote:FireClient(player, "message", { from = "Marge", text = words, gps = { x = shop.x, z = shop.z, id = "bags" } })
		notice:FireClient(player, `📱 Marge: {words}`)
	end
end

-- 6.0.1: Marge about the plastic bag (Kit "bag"): once a player with the phone and the first day behind them has its
-- price and no bag, she texts them about Last Stop Supplies with the shop on the GPS (6.0.2: about the vest; 6.6: the
-- text names ZDC Bags for the bags; 6.7: the vest's tips). Once a session.
local bagTold: { [Player]: boolean } = {}

local function bagCheck(player: Player): boolean
	local profile = PlayerData.get(player)
	if bagTold[player] or bikeLevels[player] == nil or not profile or not profile.tutorial or not profile.phone then
		return false
	end
	local bag: Config.KitDef? = nil
	for _, def in Config.Kit do
		if def.id == Config.Courier.VestKit then -- 6.0.2: the bag comes with the start: her text is about the vest
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
	bagCheck(player) -- (6.7: the pistol's text is gone: every courier starts with it)
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
	-- 6.6: a save that owned a backpack got its price back (server/PlayerData.luau, Config.RetiredKit): Marge says so,
	-- once (profile.packRefund is never saved), the bag kiosk on the GPS. 6.7: the Thermal Jacket's the same way
	-- (profile.jacketRefund, Config.Courier.JacketRefund). 6.12.2: the Running Shoes' (profile.shoeRefund,
	-- Config.Courier.ShoeRefund), Last Stop Supplies (the gear stall's GEAR counter) on the GPS
	for _, retired in {
		{ money = if profile then profile.packRefund else nil, text = Config.Courier.PackRefund, shop = "bags" },
		{ money = if profile then profile.jacketRefund else nil, text = Config.Courier.JacketRefund, shop = "bags" },
		{ money = if profile then profile.shoeRefund else nil, text = Config.Courier.ShoeRefund, shop = "supplies" },
		-- 6.23: the bags owned for good before (bags are bought for each game now: profile.bagRefund, never saved)
		{ money = if profile then profile.bagRefund else nil, text = Config.BagShop.Refunded, shop = "bags" },
	} do
		local refund = retired.money
		if profile and refund and refund > 0 then
			task.delay(BIKE_DELAY, function()
				if not player.Parent or not remote then
					return
				end
				local shop = Map.Shops[retired.shop]
				local words = string.gsub(retired.text, "{money}", `${refund}`)
				remote:FireClient(player, "message", { from = "Marge", text = words, gps = if shop then { x = shop.x, z = shop.z, id = retired.shop } else nil })
				notice:FireClient(player, `📱 Marge: {words}`)
			end)
		end
	end
	if profile then
		profile.packRefund = nil
		profile.jacketRefund = nil
		profile.shoeRefund = nil
	end
	task.delay(BIKE_DELAY + 4, tips, player) -- 6.0.1: the vest's price in your pocket, not owned: her text
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
		bagTold[player] = nil
	end)
	PlayerData.Changed:Connect(bikeCheck) -- 5.1: Marge about Spoke & Chain
	PlayerData.Changed:Connect(tips) -- 6.0.1: Marge about the vest (6.7: the pistol's text is gone)
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
