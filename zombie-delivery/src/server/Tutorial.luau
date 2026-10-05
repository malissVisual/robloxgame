--!strict
-- 3.7: the first-day tutorial. Marge, the dispatcher (Config.Tutorial: an R15 person from server/Npcs.luau with a name
-- tag, the idle animation and a "Talk" prompt), stands at the depot by the job board. She is there for everybody.
--
-- A player whose profile.tutorial is false (a new save; PlayerData counts an older save with a delivery as done):
--   wait     until PLAY was pressed: their car came (Main gives it on PLAY; Tutorial.onPlay when Main calls it), then
--            Config.Tutorial.StartDelay s for the start screen to fade
--   welcome  her greeting (client/TutorialUi.luau shows the dialog at once, a marker over her). "Let's go" in the
--            dialog or talking to her (E): Jobs.startTutorialJob, the easiest ★ ordinary job, as if taken from the board
--   board    no job could be made: take any ★ job from the board (J)
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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)
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
	return profile ~= nil and not profile.tutorial and (Tuning.InStudio or not RunService:IsStudio())
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
			session.readyAt = now + Tuning.StartDelay -- the car comes on PLAY (Main giveCar)
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
			end
		end
	end
end

local function track(player: Player)
	if not sessions[player] then
		sessions[player] = { phase = "wait", nextGo = 0, lastAsk = 0 }
	end
end

-- PLAY was pressed (Main may call this from its Play handler; without it the arriving car tells the same).
function Tutorial.onPlay(player: Player)
	local session = sessions[player]
	if session and session.phase == "wait" and not session.readyAt then
		session.readyAt = os.clock() + Tuning.StartDelay
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
	end)
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
