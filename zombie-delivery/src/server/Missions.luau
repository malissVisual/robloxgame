--!strict
-- The missions on the server (3.0, shared/Missions.luau): the MISSIONS window's state (each player's best ratings,
-- what is open, the campaigns), starting a mission (checked: open, level, no job running, not in somebody else's
-- crew; then server/Jobs.luau startMission plays it), and the rewards when one is done (Jobs.onMissionComplete,
-- wired to Missions.onComplete in Main): the first clear's reward and XP, every new star, the campaign's reward, and
-- the same for the crew who helped (Config.Missions.CrewCredit: the members and riders at the finish, and only when
-- the mission is open for them).
--
-- The "Missions" remote (shared/Net.luau):
--   client → server  ("open")               send me my missions state
--                    ("start", mission id)  start that mission (refused with a Notice and the reason)
--   server → client  ("state", MissionsState)
--                      progress = { [mission id] = best stars }, campaigns = { [campaign id] = true } (rewarded),
--                      level, stars, starsMax, active = the mission running (yours, or your crew leader's) or nil,
--                      crewOwner = your crew leader's name when you are in somebody's crew, else nil
--                    ("cleared", { id, name, stars, best, newStars, reward, starBonus, xp, campaignDone, campaignReward,
--                      crew, owner }) a mission is done: the banner (then the state follows)
-- A player who opened the window once gets the state again whenever it changes on its own (a mission starts or
-- ends, they join or leave a crew, they level up): a light check every second, nothing per frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Levels = require(Shared.Levels)
local MissionData = require(Shared.Missions)
local Net = require(Shared.Net)

local Server = script.Parent
local PlayerData = require(Server.PlayerData)
local Jobs = require(Server.Jobs)
local Crew = require(Server.Crew)

local Missions = {}

local ACTION_GAP = 0.4 -- seconds between two requests of one kind ("open", "start") of one player (a spam guard)
local WATCH_EVERY = 1 -- seconds between two checks whether a window's state changed on its own

local remote: RemoteEvent? = nil
local notice: RemoteEvent? = nil
local lastAction: { [Player]: number } = {} -- "open"
local lastStart: { [Player]: number } = {} -- "start" (its own gap: START right after the window opened still counts)
local watching: { [Player]: string } = {} -- players who opened the window → the signature of the state they have
local started: { [Player]: string } = {} -- the mission each player started here (until their job ends)
local pendingOpen: { [Player]: boolean } = {} -- an "open" that came too quickly waits for its answer

local function getRemote(): RemoteEvent
	if not remote then
		remote = Net.get("Missions")
	end
	return remote :: RemoteEvent
end

local function say(player: Player, text: string)
	if not notice then
		notice = Net.get("Notice")
	end
	(notice :: RemoteEvent):FireClient(player, text)
end

-- ── The state ──────────────────────────────────────────────────────────────

-- The mission id inside a job payload (Jobs.crewStatus: mission = { id, … }), if there is one.
local function missionIn(status: { [string]: any }?): string?
	local mission = if status then status.mission else nil
	if type(mission) == "table" and type(mission.id) == "string" then
		return mission.id
	end
	if type(mission) == "string" then
		return mission
	end
	return nil
end

-- The mission this player plays now: their own job's, or their crew leader's. nil = none.
local function activeOf(player: Player): string?
	local owner = Crew.ownerOf(player)
	local who = if owner and owner.Parent then owner else player
	if not Jobs.active(who) then
		if who == player then
			started[player] = nil
		end
		return nil
	end
	-- Jobs puts the mission into its payload; the one started here is the fallback.
	local id = missionIn(Jobs.crewStatus(who))
	return id or started[who]
end

-- The MissionsState (see the header), or nil before the save has loaded.
local function stateFor(player: Player): { [string]: any }?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	local stars, starsMax = MissionData.stars(profile.missions, nil)
	local owner = Crew.ownerOf(player)
	return {
		progress = table.clone(profile.missions),
		campaigns = table.clone(profile.campaigns),
		level = Levels.levelFor(profile.xp),
		stars = stars,
		starsMax = starsMax,
		active = activeOf(player),
		crewOwner = if owner and owner.Parent then owner.DisplayName else nil,
	}
end

-- What decides whether a watching window needs the state again (the rest changes only through this module).
local function signature(player: Player): string
	local owner = Crew.ownerOf(player)
	local stars = 0
	local profile = PlayerData.get(player)
	if profile then
		stars = MissionData.stars(profile.missions, nil)
	end
	return `{activeOf(player) or "-"}|{if owner then owner.UserId else 0}|{PlayerData.level(player)}|{stars}`
end

-- The progress a player's MISSIONS window shows (sent on "open", after every change).
function Missions.send(player: Player)
	local state = stateFor(player)
	if not state then
		return
	end
	watching[player] = signature(player)
	getRemote():FireClient(player, "state", state)
end

-- The total mission stars of a player (the leaderboard's STARS column).
function Missions.starsOf(player: Player): number
	local profile = PlayerData.get(player)
	if not profile then
		return 0
	end
	return (MissionData.stars(profile.missions, nil))
end

-- ── Starting ───────────────────────────────────────────────────────────────

-- Can this player start the mission now? nil = yes, else why not (for the Notice).
local function refusal(player: Player, def: MissionData.MissionDef): string?
	local profile = PlayerData.get(player)
	if not profile then
		return "Still loading..."
	end
	local owner = Crew.ownerOf(player)
	if owner and owner.Parent then
		return `{owner.DisplayName} leads your crew: your crew leader picks the mission.`
	end
	if Jobs.active(player) then
		return "Finish your current delivery first."
	end
	local open, why = MissionData.unlocked(def.id, profile.missions, Levels.levelFor(profile.xp))
	if not open then
		return why or "This mission is locked."
	end
	return nil
end

-- Plays the mission (Jobs.startMission); says why not. True when it started.
local function begin(player: Player, def: MissionData.MissionDef): boolean
	local ok, why = Jobs.startMission(player, def)
	if not ok then
		say(player, why or "The mission could not start here, try again.")
		Missions.send(player)
		return false
	end
	started[player] = def.id
	Missions.send(player)
	-- The crew's windows show the running mission too.
	for _, member in Crew.members(player) do
		if watching[member] then
			Missions.send(member)
		end
	end
	return true
end

local function start(player: Player, id: any)
	local def = if type(id) == "string" then MissionData.find(id) else nil
	if not def then
		say(player, "Unknown mission.")
		return
	end
	local why = refusal(player, def)
	if why then
		say(player, why)
		Missions.send(player) -- the window may be out of date: send the truth
		return
	end
	begin(player, def)
end

-- The admin tools (server/Admin.luau): start any mission now, locks ignored (a running job must be ended first).
function Missions.adminStart(player: Player, id: string): (boolean, string?)
	local def = MissionData.find(id)
	if not def then
		return false, "Unknown mission."
	end
	if not PlayerData.get(player) then
		return false, "Still loading..."
	end
	if Jobs.active(player) then
		return false, "Finish (or cancel) your current delivery first."
	end
	return begin(player, def), nil
end

-- The admin tools: every mission at 3 stars and every campaign rewarded (no money paid). Returns the count.
function Missions.adminAll(player: Player): number
	local profile = PlayerData.get(player)
	if not profile then
		return 0
	end
	for _, def in MissionData.List do
		profile.missions[def.id] = 3
	end
	for _, campaign in MissionData.Campaigns do
		profile.campaigns[campaign.id] = true
	end
	PlayerData.notify(player)
	Missions.send(player)
	return #MissionData.List
end

-- The admin tools: the mission progress and the campaign rewards cleared (to play them again from the start).
function Missions.adminReset(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	table.clear(profile.missions)
	table.clear(profile.campaigns)
	PlayerData.notify(player)
	Missions.send(player)
end

-- ── Done: the rewards ──────────────────────────────────────────────────────

-- The extra XP of a first clear: (FirstClearXp - 1) × what the job itself gave (its tier and pieces, no kills).
local function firstClearXp(def: MissionData.MissionDef): number
	local base = Levels.jobXp(def.tier, def.items, 0, false, true)
	return math.floor(math.max(0, Config.Missions.FirstClearXp - 1) * base + 0.5)
end

-- One player's credit for the mission: the best rating, the money and XP, the campaign. The "cleared" table.
local function credit(player: Player, def: MissionData.MissionDef, stars: number, owner: Player): { [string]: any }?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	local before = math.clamp(profile.missions[def.id] or 0, 0, 3)
	local best = math.max(before, stars)
	local newStars = best - before
	local first = before < 1
	profile.missions[def.id] = best

	local reward = if first then math.max(0, def.reward) else 0
	local starBonus = newStars * Config.Missions.StarBonus
	local xp = if first then firstClearXp(def) else 0

	-- The campaign: all its missions done (any rating) pays its reward once.
	local campaignDone: string? = nil
	local campaignReward = 0
	local campaign = MissionData.findCampaign(def.campaign)
	if campaign and not profile.campaigns[campaign.id] then
		local done, total = MissionData.done(profile.missions, campaign.id)
		if total > 0 and done >= total then
			profile.campaigns[campaign.id] = true
			campaignDone = campaign.name
			campaignReward = campaign.reward
		end
	end

	local money = reward + starBonus + campaignReward
	if money > 0 then
		PlayerData.addMoney(player, money) -- fires Changed (the HUD's money, the State)
	else
		PlayerData.notify(player)
	end
	local level, levelUp = PlayerData.level(player), false
	if xp > 0 then
		level, levelUp = PlayerData.addXp(player, xp)
	end
	-- A first clear (or a campaign) is worth saving right away; the autosave does the rest.
	if first or campaignDone then
		task.spawn(PlayerData.save, player)
	end
	return {
		id = def.id,
		name = def.name,
		campaign = def.campaign,
		number = def.number,
		stars = stars,
		best = best,
		newStars = newStars,
		first = first,
		reward = reward,
		starBonus = starBonus,
		xp = xp,
		level = level,
		levelUp = levelUp,
		debrief = def.debrief,
		campaignDone = campaignDone,
		campaignReward = campaignReward,
		crew = player ~= owner, -- credited as a crew member
		owner = owner.DisplayName,
	}
end

-- Jobs.onMissionComplete is wired to this in Main: the owner, the crew who were there at the finish (members), the
-- rating.
function Missions.onComplete(owner: Player, missionId: string, stars: number, members: { Player })
	local def = if type(missionId) == "string" then MissionData.find(missionId) else nil
	if not def then
		warn(`[Missions] unknown mission done: {missionId}`)
		return
	end
	started[owner] = nil
	local rating = math.clamp(math.floor(tonumber(stars) or 1), 1, 3)
	local credited: { Player } = { owner }
	if Config.Missions.CrewCredit and type(members) == "table" then
		for _, member in members do
			if typeof(member) == "Instance" and member:IsA("Player") and member.Parent and not table.find(credited, member) then
				table.insert(credited, member)
			end
		end
	end
	for _, player in credited do
		if not player.Parent then
			continue
		end
		-- A crew member gets the mission's credit only when it is open for them (its campaign, its level, the mission
		-- before it): the pay share they already have.
		if player ~= owner then
			local profile = PlayerData.get(player)
			if not profile then
				continue
			end
			local open = MissionData.unlocked(def.id, profile.missions, Levels.levelFor(profile.xp))
			if not open then
				say(player, `"{def.name}" is not open for you yet: you get your share of the pay, not the mission's stars and rewards.`)
				continue
			end
		end
		local ok, result = pcall(credit, player, def, rating, owner)
		if not ok then
			warn(`[Missions] credit for {player.Name} failed: {result}`)
		elseif result then
			getRemote():FireClient(player, "cleared", result)
			Missions.send(player)
		end
	end
end

-- ── The remote ─────────────────────────────────────────────────────────────

local function onRequest(player: Player, action: any, arg: any)
	if type(action) ~= "string" then
		return
	end
	local now = os.clock()
	local last = if action == "start" then lastStart else lastAction
	if last[player] and now - last[player] < ACTION_GAP then
		if action == "start" then
			-- Never silent: the window waits for an answer ("Starting …").
			say(player, "Too fast, try again.")
			Missions.send(player)
		elseif action == "open" and not pendingOpen[player] then
			-- A quick reopen still gets the state (a little later, once).
			pendingOpen[player] = true
			task.delay(ACTION_GAP, function()
				pendingOpen[player] = nil
				if player.Parent then
					Missions.send(player)
				end
			end)
		end
		return
	end
	last[player] = now
	if action == "open" then
		if not PlayerData.get(player) then
			say(player, "Still loading...")
			return
		end
		Missions.send(player)
	elseif action == "start" then
		start(player, arg)
	end
end

-- Every second: the windows whose state changed on its own (a mission ended, a crew joined, a level up) get it again.
local function watch()
	for player, sent in watching do
		if not player.Parent then
			watching[player] = nil
			continue
		end
		local now = signature(player)
		if now ~= sent then
			Missions.send(player)
		end
	end
end

function Missions.start()
	getRemote().OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		lastStart[player] = nil
		watching[player] = nil
		started[player] = nil
		pendingOpen[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(WATCH_EVERY)
			local ok, err = pcall(function()
				watch()
			end)
			if not ok then
				warn(`[Missions] watch failed: {err}`)
			end
		end
	end)
end

return Missions
