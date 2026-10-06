--!strict
-- The challenges, secrets and rewards on the server (3.1): counts the stats (shared/Challenges.luau Counters) from the
-- game's events, marks places visited and secret packages found (World.SecretPrompts, Map.Secrets), checks the
-- challenges and pays them, gives the campaign / secrets / all-challenges rewards (Config.Rewards: exclusive guns and
-- paints, titles), shows the chosen title over the player's head and answers the "Challenges" remote.
--
-- Counting. The other modules never require this one (no cycles): they expose hook fields that Main wires here:
--   Zombies.onKillInfo     a zombie / bandit on foot killed: headshot, brute, bandit, run over, splash
--   BanditCars.onKillInfo  a bandit car destroyed (by a gun, a ram or a blast)
--   Jobs.onStat            waves, HOLD OUT won, pieces / passengers / horses delivered, the missions' finish stats
-- Kills from a seat are told apart by what made them (Kill.from, server/Gun.luau): the roof gun = a car gun kill, a
-- passenger's gun out of the window = a gunner kill (a mine or a fire is neither). The distance driven is sampled
-- every second from the driver's car (a jump of over TELEPORT_JUMP studs is a teleport, not driving), the places
-- visited every two seconds (VISIT_RADIUS of a Map.Places point). server/Missions.luau calls Challenges.campaignDone and Challenges.check itself.
--
-- Checking. Every change marks the player dirty; a light loop checks them (twice a second at most), and every
-- CHECK_EVERY s everybody (the profile-derived stats: money earned, level, cars bought ...). A challenge reached is
-- marked done, pays its money, gives its title and sends "unlocked". Every challenge done gives
-- Config.Rewards.Challenges once (Dead End), every secret found Config.Rewards.Secrets once (Phantom). profile.rewards
-- marks each reward given (a campaign id, "secrets", "challenges"); its title alone does not (the admin title command
-- gives any title).
--
-- The "Challenges" remote (shared/Net.luau):
--   client → server  ("open")                 send me the state
--                    ("title", title or nil)  show this earned title (nil: none)
--   server → client  ("state", S)             S = { values, done, secrets, secretsTotal, visited, placesTotal,
--                                               titles, title, rewards = { campaigns, secrets, challenges } }
--                    ("unlocked", U)          U = { kind, id, name, money?, title?, weapon?, paint?, count?, total? }
-- The state goes out on "open", once the save has loaded, and after every change (at most twice a second).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)
local MissionData = require(Shared.Missions)
local Net = require(Shared.Net)
local ChallengeData = require(Shared.Challenges)

local Server = script.Parent
local PlayerData = require(Server.PlayerData)
local Vehicles = require(Server.Vehicles)
local World = require(Server.World)

local Challenges = {}

-- How a kill happened (Main fills it from Zombies.onKillInfo / BanditCars.onKillInfo).
export type Kill = {
	car: boolean?, -- a bandit car destroyed (else a zombie or a bandit on foot)
	kind: string?, -- the Config.Zombies kind
	bandit: boolean?, -- a bandit / gunner on foot
	headshot: boolean?,
	cause: string?, -- "gun" (a direct hit), "car" (rammed / run over), "splash" (a blast or a fire), "melee" (3.9), "other"
	from: string?, -- fired from a car seat (server/Gun.luau): "cargun" (the roof gun), "window" (a passenger's gun)
}

type SecretDef = Map.Secret

local STATE_GAP = 0.5 -- seconds between two states to one player (at most twice a second)
local LOOP_EVERY = 0.25 -- the loop's beat
local CHECK_EVERY = 5 -- seconds between two checks of everybody (the stats that change without telling)
local DISTANCE_EVERY = 1 -- seconds between two samples of the distance driven
local TELEPORT_JUMP = 200 -- studs between two samples: more is a teleport (CarCall, admin), not driving
local VISIT_EVERY = 2 -- seconds between two checks of the places visited
local VISIT_RADIUS = 70 -- studs from a Map.Places point
local SAVE_DELAY = 10 -- seconds after something worth keeping until it is saved (one save for a burst)
local ACTION_GAP = 0.3 -- seconds between two requests of one player
local TITLE_DISTANCE = 80 -- studs: the title over a head is seen this far
local TITLE_GOLD = Color3.fromRGB(255, 205, 80)
local SECRET_SLACK = 4 -- studs beyond a prompt's reach still accepted (lag)
local SECRET_RISE = 7 -- studs up or down from the package at most: a roof or a ledge is climbed, not reached from below

-- The stats the profile gives (shared/Challenges.luau Challenges.value), next to the counters.
local DERIVED = {
	"kills",
	"deliveries",
	"earned",
	"level",
	"stars",
	"missions",
	"campaigns",
	"secrets",
	"visited",
	"titles",
	"properties",
	"cars",
	"weapons",
}

local COUNTERS: { [string]: boolean } = {}
for _, name in ChallengeData.Counters do
	COUNTERS[name] = true
end

local remote: RemoteEvent? = nil
local notice: RemoteEvent? = nil
local dirty: { [Player]: boolean } = {} -- something changed: check and send the state
local loaded: { [Player]: boolean } = {} -- the save is here and the join was handled
local lastSent: { [Player]: number } = {} -- os.clock() of the last state
local lastSignature: { [Player]: string } = {} -- what the last state said (a change sends it again)
local lastAction: { [Player]: { [string]: number } } = {} -- per action ("open", "title"): a spam guard
local titleQueued: { [Player]: { title: string? } } = {} -- a "title" too soon: the latest one, applied after the gap
local saveQueued: { [Player]: boolean } = {}
local driving: { [Player]: { car: Vehicles.Car, at: Vector3, carry: number } } = {}
local secretPrompts: { [ProximityPrompt]: string } = {} -- World.SecretPrompts: prompt → secret id

local function getRemote(): RemoteEvent
	if not remote then
		remote = Net.get("Challenges")
	end
	return remote :: RemoteEvent
end

local function say(player: Player, text: string)
	if not notice then
		notice = Net.get("Notice")
	end
	(notice :: RemoteEvent):FireClient(player, text)
end

local function secretList(): { SecretDef }
	return Map.Secrets
end

local function findSecret(id: string): SecretDef?
	for _, def in secretList() do
		if def.id == id then
			return def
		end
	end
	return nil
end

local function placeName(id: string): string
	for _, place in Map.Places do
		if place.id == id then
			return place.name
		end
	end
	return id
end

local function count(set: { [string]: boolean }): number
	local n = 0
	for _, on in set do
		if on then
			n += 1
		end
	end
	return n
end

-- Every secret of Map.Secrets found? (false when there are none)
local function allSecrets(profile: PlayerData.Profile): (boolean, number, number)
	local list = secretList()
	local found = 0
	for _, def in list do
		if profile.secrets[def.id] then
			found += 1
		end
	end
	return #list > 0 and found >= #list, found, #list
end

local function unlocked(player: Player, info: { [string]: any })
	getRemote():FireClient(player, "unlocked", info)
end

-- Something worth keeping (a challenge, a secret, a reward): saved a little later, once for a burst.
local function saveSoon(player: Player)
	if saveQueued[player] then
		return
	end
	saveQueued[player] = true
	task.delay(SAVE_DELAY, function()
		saveQueued[player] = nil
		if player.Parent then
			PlayerData.save(player)
		end
	end)
end

-- ── The title over the head ────────────────────────────────────────────────

-- The BillboardGui "TitleTag" on the character's head shows the chosen title (everybody sees it); the player
-- attribute "Title" carries it to the clients too. Safe to call any time: it only builds what is missing.
local function updateTag(player: Player)
	local profile = PlayerData.get(player)
	local title = if profile then profile.title else nil
	if player:GetAttribute("Title") ~= title then
		player:SetAttribute("Title", title)
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local tag = head:FindFirstChild("TitleTag")
	if not title then
		if tag then
			tag:Destroy()
		end
		return
	end
	local label: TextLabel? = nil
	if tag and tag:IsA("BillboardGui") then
		local found = tag:FindFirstChild("Text")
		label = if found and found:IsA("TextLabel") then found else nil
	end
	if not label then
		if tag then
			tag:Destroy()
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "TitleTag"
		gui.Size = UDim2.fromOffset(220, 20)
		gui.StudsOffset = Vector3.new(0, 3.3, 0) -- above the name Roblox shows
		gui.MaxDistance = TITLE_DISTANCE
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false
		gui.Adornee = head
		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBold
		text.TextSize = 14
		text.TextColor3 = TITLE_GOLD
		text.TextStrokeTransparency = 0.35
		text.TextStrokeColor3 = Color3.fromRGB(40, 25, 0)
		text.Parent = gui
		gui.Parent = head
		label = text
	end
	local shown = `« {title} »`
	if label and label.Text ~= shown then
		label.Text = shown
	end
end

-- ── Giving ─────────────────────────────────────────────────────────────────

-- A title earned (the first one is shown at once).
local function giveTitle(player: Player, profile: PlayerData.Profile, title: string)
	profile.titles[title] = true
	if profile.title == nil then
		profile.title = title
		updateTag(player)
	end
end

-- An exclusive gun or paint: yours (nothing is equipped for you).
local function giveItem(profile: PlayerData.Profile, weapon: string?, paint: string?)
	if weapon then
		profile.weapons[weapon] = true
	end
	if paint then
		profile.paints[paint] = true
	end
end

local function markDirty(player: Player)
	dirty[player] = true
end

-- A campaign's reward (Config.Rewards.Campaigns), once (profile.rewards[campaignId]). True when given now.
local function campaignReward(player: Player, profile: PlayerData.Profile, campaignId: string): boolean
	local reward = Config.Rewards.Campaigns[campaignId]
	if not reward or profile.rewards[campaignId] then
		return false
	end
	profile.rewards[campaignId] = true
	giveItem(profile, reward.weapon, reward.paint)
	giveTitle(player, profile, reward.title)
	local campaign = MissionData.findCampaign(campaignId)
	unlocked(player, {
		kind = "campaign",
		id = campaignId,
		name = if campaign then campaign.name else campaignId,
		title = reward.title,
		weapon = reward.weapon,
		paint = reward.paint,
	})
	return true
end

-- The final rewards: every secret found (Config.Rewards.Secrets) and every challenge done (Config.Rewards.Challenges),
-- each once (profile.rewards.secrets, .challenges). True when something was given.
local function finalRewards(player: Player, profile: PlayerData.Profile): boolean
	local given = false
	local secrets = Config.Rewards.Secrets
	local everySecret, found, total = allSecrets(profile)
	if everySecret and not profile.rewards.secrets then
		profile.rewards.secrets = true
		giveItem(profile, nil, secrets.paint)
		giveTitle(player, profile, secrets.title)
		PlayerData.addMoney(player, secrets.money)
		unlocked(player, {
			kind = "secrets",
			id = "secrets",
			name = "Every lost package found",
			money = secrets.money,
			title = secrets.title,
			paint = secrets.paint,
			count = found,
			total = total,
		})
		given = true
	end
	local last = Config.Rewards.Challenges
	local done, all = ChallengeData.doneCount(profile :: any)
	if all > 0 and done >= all and not profile.rewards.challenges then
		profile.rewards.challenges = true
		giveItem(profile, last.weapon, nil)
		giveTitle(player, profile, last.title)
		PlayerData.addMoney(player, last.money)
		unlocked(player, {
			kind = "challenges",
			id = "challenges",
			name = "Every challenge done",
			money = last.money,
			title = last.title,
			weapon = last.weapon,
			count = done,
			total = all,
		})
		given = true
	end
	return given
end

-- Every challenge reached and not done yet: done, paid, its title, "unlocked". Then the final rewards.
local function evaluate(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local like = profile :: any
	local any = false
	-- The money paid counts toward "earned": a second pass catches a challenge it completes.
	for _ = 1, 3 do
		local newOnes = false
		for _, def in ChallengeData.List do
			if profile.challenges[def.id] or ChallengeData.value(like, def.stat) < def.goal then
				continue
			end
			profile.challenges[def.id] = true
			newOnes = true
			if def.title then
				giveTitle(player, profile, def.title)
			end
			if def.money > 0 then
				PlayerData.addMoney(player, def.money)
			end
			unlocked(player, {
				kind = "challenge",
				id = def.id,
				name = def.name,
				description = def.description,
				category = def.category,
				hidden = def.hidden,
				money = def.money,
				title = def.title,
			})
		end
		if not newOnes then
			break
		end
		any = true
	end
	if finalRewards(player, profile) then
		any = true
	end
	if any then
		PlayerData.notify(player)
		saveSoon(player)
	end
end

-- ── The state ──────────────────────────────────────────────────────────────

local function stateOf(profile: PlayerData.Profile): { [string]: any }
	local like = profile :: any
	local values: { [string]: number } = {}
	for _, name in ChallengeData.Counters do
		values[name] = ChallengeData.value(like, name)
	end
	for _, name in DERIVED do
		values[name] = ChallengeData.value(like, name)
	end
	local done: { [string]: boolean } = {}
	for _, def in ChallengeData.List do
		if profile.challenges[def.id] then
			done[def.id] = true
		end
	end
	local campaigns: { [string]: boolean } = {}
	for id in Config.Rewards.Campaigns do
		if profile.rewards[id] then
			campaigns[id] = true
		end
	end
	return {
		values = values,
		done = done,
		secrets = table.clone(profile.secrets),
		secretsTotal = #secretList(),
		visited = table.clone(profile.visited),
		placesTotal = #Map.Places,
		titles = table.clone(profile.titles),
		title = profile.title,
		rewards = {
			campaigns = campaigns,
			secrets = profile.rewards.secrets == true,
			challenges = profile.rewards.challenges == true,
		},
	}
end

-- What decides whether the client needs the state again (the values in a fixed order, the sets' sizes, the title).
local function signature(state: { [string]: any }, profile: PlayerData.Profile): string
	local parts: { string } = {}
	local values = state.values :: { [string]: number }
	for _, name in ChallengeData.Counters do
		table.insert(parts, tostring(values[name]))
	end
	for _, name in DERIVED do
		table.insert(parts, tostring(values[name]))
	end
	table.insert(parts, tostring(count(profile.challenges)))
	table.insert(parts, tostring(count(profile.secrets)))
	table.insert(parts, tostring(count(profile.visited)))
	table.insert(parts, tostring(count(profile.titles)))
	table.insert(parts, tostring(count(profile.rewards)))
	table.insert(parts, profile.title or "-")
	table.insert(parts, tostring(state.secretsTotal))
	return table.concat(parts, "|")
end

-- Sends the state when it changed (force: always). False when it has to wait (too soon after the last one).
local function sendState(player: Player, force: boolean?): boolean
	local profile = PlayerData.get(player)
	if not profile then
		return true
	end
	local now = os.clock()
	if not force and lastSent[player] and now - lastSent[player] < STATE_GAP then
		return false
	end
	local state = stateOf(profile)
	local sig = signature(state, profile)
	if force or sig ~= lastSignature[player] then
		lastSignature[player] = sig
		lastSent[player] = now
		getRemote():FireClient(player, "state", state)
	end
	return true
end

-- ── The API ────────────────────────────────────────────────────────────────

-- Count a stat (a Challenges.Counters name) for a player.
function Challenges.add(player: Player, stat: string, amount: number?)
	local n = amount or 1
	if not COUNTERS[stat] or type(n) ~= "number" or n ~= n or n <= 0 then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	profile.stats[stat] = math.min((profile.stats[stat] or 0) + n, 1e12)
	markDirty(player)
end

-- A kill (Main wires Zombies.onKillInfo and BanditCars.onKillInfo here): the combat counters.
function Challenges.onKill(player: Player, info: Kill)
	local cause = info.cause or "gun"
	if info.car then
		Challenges.add(player, "banditCars", 1)
	else
		if info.headshot then
			Challenges.add(player, "headshots", 1)
		end
		if info.kind == "brute" then
			Challenges.add(player, "brutes", 1)
		end
		if info.bandit then
			Challenges.add(player, "bandits", 1)
		end
		if cause == "car" then
			Challenges.add(player, "runOvers", 1)
		end
	end
	if cause == "splash" then
		Challenges.add(player, "explosions", 1)
	end
	-- From a seat (what fired, not where the killer sits now: a mine or a fire that kills later is neither).
	if info.from == "cargun" then
		Challenges.add(player, "carGunKills", 1)
	elseif info.from == "window" then
		Challenges.add(player, "gunnerKills", 1)
	end
end

-- A campaign was finished (server/Missions.luau): its reward (Config.Rewards.Campaigns), once.
function Challenges.campaignDone(player: Player, campaignId: string)
	local profile = PlayerData.get(player)
	if not profile or type(campaignId) ~= "string" then
		return
	end
	if campaignReward(player, profile, campaignId) then
		PlayerData.notify(player)
		saveSoon(player)
	end
	markDirty(player)
end

-- Check every challenge now (after anything that changes the profile-derived stats).
function Challenges.check(player: Player)
	local ok, err = pcall(function()
		evaluate(player)
	end)
	if not ok then
		warn(`[Challenges] check failed: {err}`)
	end
	markDirty(player)
end

-- ── Secrets and places ─────────────────────────────────────────────────────

local function foundSecret(player: Player, id: string)
	local profile = PlayerData.get(player)
	local def = findSecret(id)
	if not profile or not def then
		return
	end
	if profile.secrets[id] then
		say(player, "Empty. You already opened this one.")
		return
	end
	profile.secrets[id] = true
	local money = Config.Rewards.SecretMoney
	PlayerData.addMoney(player, money)
	local _, found, total = allSecrets(profile)
	unlocked(player, {
		kind = "secret",
		id = id,
		name = placeName(def.place),
		money = money,
		count = found,
		total = total,
	})
	Challenges.check(player)
	saveSoon(player)
end

-- A prompt was used: a SecretPrompt (World.SecretPrompts, or the attribute Secret on any prompt of that name).
local function onPrompt(prompt: ProximityPrompt, player: Player)
	local id = secretPrompts[prompt]
	if not id then
		if prompt.Name ~= "SecretPrompt" then
			return
		end
		local attribute = prompt:GetAttribute("Secret")
		if type(attribute) ~= "string" then
			return
		end
		id = attribute
	end
	-- Within reach of the package (the client could fire it from anywhere), and level with it: a package on a roof or
	-- a ledge is opened up there, not from the ground under it (the prompt needs no line of sight).
	local parent = prompt.Parent
	local at: Vector3? = if parent and parent:IsA("BasePart") then parent.Position
		elseif parent and parent:IsA("Attachment") then parent.WorldPosition
		else nil
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not at or not root or not root:IsA("BasePart") then
		return
	end
	local offset = root.Position - at
	if offset.Magnitude > prompt.MaxActivationDistance + SECRET_SLACK or math.abs(offset.Y) > SECRET_RISE then
		return
	end
	foundSecret(player, id :: string)
end

-- The places within VISIT_RADIUS: the first visit is told ("NEW PLACE DISCOVERED").
local function visit(player: Player)
	local profile = PlayerData.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not profile or not root or not root:IsA("BasePart") then
		return
	end
	local position = root.Position
	for _, place in Map.Places do
		if profile.visited[place.id] then
			continue
		end
		local dx, dz = position.X - place.x, position.Z - place.z
		if dx * dx + dz * dz <= VISIT_RADIUS * VISIT_RADIUS then
			profile.visited[place.id] = true
			unlocked(player, {
				kind = "place",
				id = place.id,
				name = place.name,
				count = count(profile.visited),
				total = #Map.Places,
			})
			markDirty(player)
			saveSoon(player)
		end
	end
end

-- The studs driven since the last sample, as the driver of the car (a teleport does not count).
local function sampleDistance(player: Player)
	local car, isDriver = Vehicles.seatedIn(player)
	if not car or not isDriver then
		driving[player] = nil
		return
	end
	local at = car.chassis.Position
	local last = driving[player]
	if not last or last.car ~= car then
		driving[player] = { car = car, at = at, carry = 0 }
		return
	end
	local step = Vector3.new(at.X - last.at.X, 0, at.Z - last.at.Z).Magnitude
	last.at = at
	if step > TELEPORT_JUMP then
		return
	end
	last.carry += step
	local whole = math.floor(last.carry)
	if whole >= 1 then
		last.carry -= whole
		Challenges.add(player, "distance", whole)
	end
end

-- ── The remote ─────────────────────────────────────────────────────────────

local function onRequest(player: Player, action: any, arg: any)
	if action ~= "open" and action ~= "title" then
		return -- only these two (an unknown one never reaches the spam guard's table)
	end
	local now = os.clock()
	local last = lastAction[player]
	if not last then
		last = {}
		lastAction[player] = last
	end
	if last[action] and now - last[action] < ACTION_GAP then
		if action == "open" then
			-- Answered by the loop a moment later, in full (another listener of the client may be asking).
			lastSignature[player] = nil
			markDirty(player)
		elseif action == "title" then
			-- The client already shows it equipped: the latest one is applied once the gap is over.
			local waiting = titleQueued[player] ~= nil
			titleQueued[player] = { title = arg }
			if not waiting then
				task.delay(ACTION_GAP - (now - last[action]) + 0.02, function()
					local queued = titleQueued[player]
					titleQueued[player] = nil
					if queued and player.Parent then
						onRequest(player, "title", queued.title)
					end
				end)
			end
		end
		return
	end
	last[action] = now
	local profile = PlayerData.get(player)
	if not profile then
		if action == "title" then
			say(player, "Still loading...")
		end
		return -- the state goes out once the save has loaded (onLoaded)
	end
	if action == "open" then
		sendState(player, true)
	elseif action == "title" then
		if arg ~= nil and (type(arg) ~= "string" or not profile.titles[arg]) then
			say(player, "You have not earned that title yet.")
			sendState(player, true)
			return
		end
		profile.title = arg
		updateTag(player)
		say(player, if arg then `Your title: {arg}` else "No title shown.")
		sendState(player, true)
		saveSoon(player)
	end
end

-- ── Joining ────────────────────────────────────────────────────────────────

-- A reward given before profile.rewards marked it: its title and its item are both yours.
local function hadReward(profile: PlayerData.Profile, title: string, weapon: string?, paint: string?): boolean
	return profile.titles[title] == true
		and (weapon == nil or profile.weapons[weapon] == true)
		and (paint == nil or profile.paints[paint] == true)
end

-- The save is here: the rewards of campaigns finished before 3.1, the title over the head, the state.
local function onLoaded(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	loaded[player] = true
	-- Early 3.1 saves had no profile.rewards (the title was the mark): never give those twice.
	for id, reward in Config.Rewards.Campaigns do
		if hadReward(profile, reward.title, reward.weapon, reward.paint) then
			profile.rewards[id] = true
		end
	end
	local secrets, last = Config.Rewards.Secrets, Config.Rewards.Challenges
	if hadReward(profile, secrets.title, nil, secrets.paint) then
		profile.rewards.secrets = true
	end
	if hadReward(profile, last.title, last.weapon, nil) then
		profile.rewards.challenges = true
	end
	local given = false
	for id, done in profile.campaigns do
		if done and campaignReward(player, profile, id) then
			given = true
		end
	end
	if profile.title and not profile.titles[profile.title] then
		profile.title = nil
	end
	updateTag(player)
	Challenges.check(player)
	if given then
		PlayerData.notify(player)
		saveSoon(player)
	end
	sendState(player, true)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		task.delay(0.5, updateTag, player)
	end)
	-- Roblox can rebuild the head when the avatar loads.
	player.CharacterAppearanceLoaded:Connect(function()
		updateTag(player)
	end)
end

-- ── Admin tools (server/Admin.luau) ────────────────────────────────────────

-- Every challenge done with its money and title, every campaign's reward and the final one (Dead End).
function Challenges.adminAll(player: Player): number
	local profile = PlayerData.get(player)
	if not profile then
		return 0
	end
	local money = 0
	for _, def in ChallengeData.List do
		if not profile.challenges[def.id] then
			profile.challenges[def.id] = true
			money += def.money
			if def.title then
				giveTitle(player, profile, def.title)
			end
		end
	end
	for _, campaign in MissionData.Campaigns do
		campaignReward(player, profile, campaign.id)
	end
	if money > 0 then
		PlayerData.addMoney(player, money)
	end
	finalRewards(player, profile)
	PlayerData.notify(player)
	markDirty(player)
	saveSoon(player)
	return #ChallengeData.List
end

-- Every secret package found (no money each), and its reward (Phantom).
function Challenges.adminSecrets(player: Player): number
	local profile = PlayerData.get(player)
	if not profile then
		return 0
	end
	for _, def in secretList() do
		profile.secrets[def.id] = true
	end
	evaluate(player)
	PlayerData.notify(player)
	markDirty(player)
	saveSoon(player)
	return #secretList()
end

-- Start over: the stats, secrets, challenges, places, titles and rewards cleared and the exclusive guns and paints
-- taken back. What the profile itself still reaches (kills, money earned, level, missions, stars, cars, properties ...)
-- cannot be cleared here: those challenges stay done, quietly (their title kept, no money, no popup), so a reset
-- never pays them twice. Returns how many stayed done. (The campaigns stay done: their rewards come back on the next
-- join.)
function Challenges.adminReset(player: Player): number
	local profile = PlayerData.get(player)
	if not profile then
		return 0
	end
	table.clear(profile.stats)
	table.clear(profile.secrets)
	table.clear(profile.challenges)
	table.clear(profile.visited)
	table.clear(profile.titles)
	table.clear(profile.rewards)
	profile.title = nil
	-- 4.6: the career's titles stay (the levels' rewards given, Config.Levels.Rewards).
	for key in profile.levelRewards do
		local reward = Config.Levels.Rewards[tonumber(key) or 0]
		if reward and reward.title then
			profile.titles[reward.title] = true
		end
	end
	for _, weapon in Config.Weapons do
		if weapon.exclusive then
			profile.weapons[weapon.id] = nil
			if profile.weapon == weapon.id then
				profile.weapon = Config.Weapons[1].id
			end
		end
	end
	local exclusivePaints: { [string]: boolean } = {}
	for _, paint in Config.Paints do
		if paint.exclusive and paint.exclusive ~= "career" then -- (4.6: the career's paints stay: profile.levelRewards)
			exclusivePaints[paint.id] = true
			profile.paints[paint.id] = nil
		end
	end
	for carId, paintId in table.clone(profile.carPaint) do
		if exclusivePaints[paintId] then
			profile.carPaint[carId] = nil
		end
	end
	driving[player] = nil
	-- The ones still reached, done again without a payout (a few passes: a title can reach the "titles" one).
	local kept = 0
	local like = profile :: any
	for _ = 1, 3 do
		local more = false
		for _, def in ChallengeData.List do
			if not profile.challenges[def.id] and ChallengeData.value(like, def.stat) >= def.goal then
				profile.challenges[def.id] = true
				if def.title then
					profile.titles[def.title] = true
				end
				kept += 1
				more = true
			end
		end
		if not more then
			break
		end
	end
	updateTag(player)
	Vehicles.repaint(player)
	PlayerData.notify(player)
	sendState(player, true)
	saveSoon(player)
	return kept
end

-- A title given and shown ("none" or "": no title shown, the earned ones stay). The title, or nil. A reward's title
-- comes without its reward (profile.rewards): the reward is still given when it is earned.
function Challenges.adminTitle(player: Player, title: string): string?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	if title == "" or string.lower(title) == "none" then
		profile.title = nil
	else
		profile.titles[title] = true
		profile.title = title
	end
	updateTag(player)
	sendState(player, true)
	saveSoon(player)
	return profile.title
end

-- ── The loop ───────────────────────────────────────────────────────────────

-- The beat: dirty players checked and sent, the distance every DISTANCE_EVERY s, the places every VISIT_EVERY s,
-- everybody checked every CHECK_EVERY s (and the title tags kept).
local function loop()
	local sinceDistance, sinceVisit, sinceCheck = 0, 0, 0
	while true do
		local dt = task.wait(LOOP_EVERY)
		sinceDistance += dt
		sinceVisit += dt
		sinceCheck += dt
		local players = Players:GetPlayers()
		if sinceDistance >= DISTANCE_EVERY then
			sinceDistance = 0
			for _, player in players do
				if loaded[player] then
					local ok, err = pcall(function()
						sampleDistance(player)
					end)
					if not ok then
						warn(`[Challenges] distance failed: {err}`)
					end
				end
			end
		end
		if sinceVisit >= VISIT_EVERY then
			sinceVisit = 0
			for _, player in players do
				if loaded[player] then
					local ok, err = pcall(function()
						visit(player)
					end)
					if not ok then
						warn(`[Challenges] places failed: {err}`)
					end
				end
			end
		end
		if sinceCheck >= CHECK_EVERY then
			sinceCheck = 0
			for _, player in players do
				if loaded[player] then
					dirty[player] = true
					updateTag(player)
				end
			end
		end
		for player in table.clone(dirty) do
			if not player.Parent then
				dirty[player] = nil
				continue
			end
			if not loaded[player] then
				continue
			end
			local ok, result = pcall(function(): boolean
				evaluate(player)
				return sendState(player, false)
			end)
			if not ok then
				warn(`[Challenges] update failed: {result}`)
				dirty[player] = nil
			elseif result then
				dirty[player] = nil
			end
		end
	end
end

function Challenges.start()
	getRemote().OnServerEvent:Connect(onRequest)
	-- The secret packages World built (World.SecretPrompts); late or unlisted ones are known by their name and
	-- attribute (onPrompt).
	for _, entry in World.SecretPrompts do
		secretPrompts[entry.prompt] = entry.id
	end
	ProximityPromptService.PromptTriggered:Connect(onPrompt)

	PlayerData.Changed:Connect(function(player: Player)
		if not loaded[player] then
			if PlayerData.get(player) then
				onLoaded(player)
			end
			return
		end
		dirty[player] = true
	end)
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
		if PlayerData.get(player) and not loaded[player] then
			task.spawn(onLoaded, player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		loaded[player] = nil
		lastSent[player] = nil
		lastSignature[player] = nil
		lastAction[player] = nil
		titleQueued[player] = nil
		driving[player] = nil
		-- saveQueued stays until its delay runs (it checks player.Parent): PlayerData.release saves anyway.
	end)
	task.spawn(loop)
end

return Challenges
