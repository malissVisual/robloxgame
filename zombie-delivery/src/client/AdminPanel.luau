--!strict
-- The admin panel (P or the small ADMIN button top right; only for players with the "Admin" attribute, see
-- server/Admin.luau, which checks every command and argument again). The answers come back as toasts (the Notice
-- remote), and in the window's footer while it is open (the toasts are behind it). While it is open the mouse is free
-- (Main: CameraRig.mouseNeeded checks AdminPanel.isOpen()), so the mouse wheel scrolls the panel, not the camera.
-- 3.8 (the contract UI, design/ui-contract/): the charcoal window (Ui.window, its ✕ closes it) with the sections as a
-- sidebar of flat tabs (the selected one with the red rule).
-- 4.5, the OP admin: a TARGET picker at the top (you and every player in the server, by display name; you by default):
-- every command that changes a profile or a character goes to the target (the server sends the target's UserId on).
-- The sections:
--   PLAYER           GIVE ALL, unlock everything, max upgrades, heal, 5.4: refuel / empty the tank; money, XP, the driver level, items, guns, cars,
--                    car stages, upgrade tracks, the car gun, paint; RESET MY SAVE (you only, asks twice)
--   OP               the toggles with their ON / OFF state (god, fly, noclip, super jump, car boost, hidden, one-hit
--                    kills; the attributes the server set on the target), the walk 1× / 2× / 4×, bring / go to, clear
--                    the target's wanted
--   WORLD            the time of day, enemies near you, a horde, a bandit car, traffic, clear / kill all / FREEZE,
--                    teleport the target to any landmark
--   JOBS & MISSIONS  any special job or ordinary tier, finish the stop / the whole job, the missions (all at 3 stars,
--                    reset, start any), the challenges, secrets and titles
--   ESTATE           properties, the home, teleport to a property, the company's safe
--   BUDDIES          NPC companions (server/Buddy.luau): + ADD, FOLLOW / STAY / GUARD, DISMISS, how many

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local MissionData = require(Shared.Missions)
local ChallengeData = require(Shared.Challenges)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)

local C = Ui.Colors
local P = Theme.Postage
local AdminPanel = {}

local player = Players.LocalPlayer
local remote: RemoteEvent? = nil

-- The window's parts (one table: the 200-register limit).
local parts: { [string]: any } = {}
local tabButtons: { [string]: any } = {}
local section = "player"
local targetId = player.UserId -- 4.5: who the commands go to (a player in this server)
local spawnCount = 1
local missionProgress: { [string]: number } = {} -- your best ratings (the Missions remote's "state"), for the colours
-- 3.1: your challenges' state (the Challenges remote's "state", asked when the tab opens).
local challengeState: { done: number, secrets: number, secretsTotal: number, visited: number, placesTotal: number, title: string?, titles: { [string]: boolean } } =
	{ done = 0, secrets = 0, secretsTotal = 0, visited = 0, placesTotal = 0, title = nil, titles = {} }

-- In a Studio Play test everybody is an admin (Config.Admin.InStudio): the panel opens even before the server's
-- "Admin" attribute arrives. The server checks every command again anyway.
local function isAdmin(): boolean
	return player:GetAttribute("Admin") == true or (Config.Admin.InStudio and RunService:IsStudio())
end

-- The target: the picked player while they are in the server, else you.
local function target(): Player
	local found = Players:GetPlayerByUserId(targetId)
	if found and found.Parent == Players then
		return found
	end
	targetId = player.UserId
	return player
end

local function send(name: string, arg: any?)
	if not remote then
		remote = Net.get("Admin")
	end
	if remote then
		remote:FireServer(name, arg, targetId)
	end
end

-- ── Building blocks ────────────────────────────────────────────────────────

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function heading(text: string, hint: string?)
	Ui.label(parts.content, text, UDim2.new(1, -10, 0, 26), { LayoutOrder = nextOrder(), TextSize = 18, Font = Theme.DisplayFont, TextColor3 = C.text })
	if hint then
		Ui.label(parts.content, hint, UDim2.new(1, -10, 0, 0), {
			LayoutOrder = nextOrder(),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = 14,
			Font = Theme.Font,
			TextColor3 = C.dim,
		})
	end
end

-- A block of equal buttons that wraps.
local function grid(cellWidth: number): any
	local frame = Ui.make("Frame", {
		Size = UDim2.new(1, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
	}, parts.content)
	Ui.make("UIGridLayout", {
		CellSize = UDim2.fromOffset(cellWidth, 40),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, frame)
	return frame
end

local function action(parent: any, text: string, color: Color3, onClick: () -> ()): any
	local button = Ui.button(parent, text, UDim2.fromOffset(150, 40), color, onClick)
	button.TextSize = 15
	button.TextWrapped = true
	button.LayoutOrder = nextOrder()
	return button
end

-- An ON / OFF toggle: ON is the main look (the raised face and its red rule), OFF a quiet grey one.
local function toggle(parent: any, label: string, on: boolean, onClick: () -> ()): any
	return action(parent, `{label}  ·  {if on then "ON" else "OFF"}`, if on then C.yellow else C.grey, onClick)
end

-- A row: a name on the left and small buttons after it (levels, stages, counts).
local function row(title: string): any
	local frame = Ui.make("Frame", {
		Size = UDim2.new(1, -10, 0, 40),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
	}, parts.content)
	Ui.list(frame, false, 6)
	local layout = frame:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	Ui.label(frame, title, UDim2.fromOffset(190, 40), {
		LayoutOrder = 0,
		TextSize = 14,
		Font = Theme.HeadingFont,
		TextColor3 = C.dim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return frame
end

local function small(parent: any, text: string, color: Color3, onClick: () -> ()): any
	local button = Ui.button(parent, text, UDim2.fromOffset(if #text > 3 then 72 else 48, 36), color, onClick)
	button.TextSize = 14
	button.LayoutOrder = nextOrder()
	return button
end

local function leftAligned(button: any)
	button.TextXAlignment = Enum.TextXAlignment.Left
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 6) }, button)
end

-- A name for the hints: "you" or the target's display name.
local function whom(): string
	local who = target()
	return if who == player then "you" else who.DisplayName
end

-- ── Sections ───────────────────────────────────────────────────────────────

local SECTIONS = {
	{ "player", "PLAYER" },
	{ "op", "OP" },
	{ "world", "WORLD" },
	{ "jobs", "JOBS & MISSIONS" },
	{ "estate", "ESTATE" },
	{ "buddies", "BUDDIES" },
}

local render: (keepScroll: boolean?) -> ()
local R: { [string]: () -> () } = {} -- the sections' renderers

-- PLAYER: everything to give the target.
R.player = function()
	local who = target()
	local isSelf = who == player
	heading(`Player · {who.DisplayName}{if isSelf then " (you)" else ""}`, "Every button here goes to the TARGET picked at the top. The target gets a notice from you.")
	local quick = grid(200)
	action(quick, "GIVE ALL (+ $1M)", C.yellow, function()
		send("giveAll")
	end)
	action(quick, "UNLOCK EVERYTHING", C.green, function()
		send("unlockAll")
	end)
	action(quick, "MAX UPGRADES + STAGES", C.blue, function()
		send("maxUpgrades")
	end)
	action(quick, "HEAL (AND THE CAR)", C.green, function()
		send("heal")
	end)
	-- 5.4: the car's tank (server/Fuel.luau): full, or empty to try the crawl and the phone's TOW.
	action(quick, "REFUEL THE CAR", C.green, function()
		send("refuel", 1)
	end)
	action(quick, "EMPTY THE TANK", C.grey, function()
		send("refuel", 0)
	end)

	heading("Money")
	local amounts = grid(150)
	for _, amount in { 1_000, 10_000, 100_000, 1_000_000 } do
		action(amounts, "+" .. Ui.money(amount), C.green, function()
			send("money", amount)
		end)
	end

	local level = tonumber(who:GetAttribute("Level")) or 1
	heading(`XP and driver level · LV {level} · {Levels.rank(level)}`, "+XP adds to the driver XP (a level up as usual). LV sets the XP to exactly what that level needs.")
	local xp = grid(150)
	for _, amount in { 100, 1_000, 10_000, 100_000 } do
		action(xp, `+{amount} XP`, C.blue, function()
			send("xp", amount)
		end)
	end
	local levels = grid(80)
	local picks: { number } = {}
	for _, n in { 1, 2, 3, 4, 5, 6, 8, 10, 12 } do
		if n < Config.Levels.MaxLevel then
			table.insert(picks, n)
		end
	end
	table.insert(picks, Config.Levels.MaxLevel)
	for _, n in picks do
		action(levels, `LV {n}`, if n == level then C.yellow else C.grey, function()
			send("setLevel", n)
		end)
	end

	heading("Items", "+1, +5, FILL (to its most) or EMPTY.")
	for _, def in Config.Items do
		local line = row(`{def.icon} {def.name} (max {def.max})`)
		small(line, "+1", C.green, function()
			send("item", { id = def.id, count = 1 })
		end)
		small(line, "+5", C.green, function()
			send("item", { id = def.id, count = 5 })
		end)
		small(line, "FILL", C.blue, function()
			send("item", { id = def.id, count = def.max })
		end)
		small(line, "EMPTY", C.grey, function()
			send("item", { id = def.id, count = -def.max })
		end)
	end

	heading("Guns", "Given and put in the hand (yellow = earned from an employer).")
	local guns = grid(150)
	for _, def in Config.Weapons do
		action(guns, def.name, if def.earned then C.yellow else C.blue, function()
			send("weapon", def.id)
		end)
	end

	heading("Spawn a car", "It comes right now on the road next to the target (yellow = an employer's company vehicle).")
	local cars = grid(150)
	for _, def in Config.Cars do
		action(cars, def.name, if def.company then C.yellow else C.blue, function()
			send("car", def.id)
		end)
	end

	heading("Car stages", "The car at that stage (given first if the target lacks it). The equipped car is rebuilt now, during a job after it.")
	for _, def in Config.Cars do
		local top = Economy.maxStage(def.id)
		if top > 0 then
			local line = row(def.name)
			for stage = 0, top do
				small(line, `S{stage}`, if stage == top then C.yellow else C.grey, function()
					send("carStage", { car = def.id, stage = stage })
				end)
			end
		end
	end

	heading("Upgrade tracks", "One track at a level (0 = none). The car tracks go on the target's equipped car; the gun tracks count for all guns.")
	for _, def in Config.Upgrades do
		local line = row(`{def.name}{if def.car then " · car" else " · guns"}`)
		for lv = 0, def.maxLevel do
			small(line, tostring(lv), if lv == def.maxLevel then C.yellow else C.grey, function()
				send("upgrade", { id = def.id, level = lv })
			end)
		end
	end

	heading("Car gun", "The gun on the roof of the target's equipped car (every dealer car, the monster truck, the armored truck).")
	local carGuns = grid(150)
	action(carGuns, "No car gun", C.red, function()
		send("carGun", "none")
	end)
	for _, def in Config.CarGuns do
		action(carGuns, def.name, C.blue, function()
			send("carGun", def.id)
		end)
	end

	heading("Paint", "Given and put on the target's equipped car (yellow = an exclusive reward).")
	local paints = grid(150)
	for _, def in Config.Paints do
		action(paints, def.name, if def.exclusive then C.yellow else C.blue, function()
			send("paint", def.id)
		end)
	end

	-- 4.0.5: start over as a new player (asks twice: it cannot be undone). Only your own save.
	if isSelf then
		heading("Start over", "Your save goes back to a new player's: $, level, cars, missions, the map and the tutorial. You are taken out of the game; join again (in Studio: Play again). A Studio test without saving already starts fresh every time.")
		local reset = grid(200)
		local armedUntil = 0
		local button: any
		button = action(reset, "RESET MY SAVE", C.red, function()
			if os.clock() < armedUntil then
				send("resetSave")
				return
			end
			armedUntil = os.clock() + 4
			button.Text = "SURE? PRESS AGAIN"
			task.delay(4, function()
				if button.Parent then
					button.Text = "RESET MY SAVE"
				end
			end)
		end)
	end
end

-- The OP toggles: the target's player attributes (the server sets them).
local FLAGS: { { command: string, attribute: string, label: string } } = {
	{ command = "god", attribute = "God", label = "GOD MODE" },
	{ command = "fly", attribute = "AdminFly", label = "FLY" },
	{ command = "noclip", attribute = "AdminNoclip", label = "NOCLIP" },
	{ command = "jump", attribute = "AdminJump", label = "SUPER JUMP" },
	{ command = "carBoost", attribute = "AdminCarBoost", label = "CAR BOOST ×2" },
	{ command = "hidden", attribute = "AdminHidden", label = "HIDDEN" },
	{ command = "oneHit", attribute = "AdminOneHit", label = "ONE-HIT KILLS" },
}

R.op = function()
	local who = target()
	heading(
		`OP tools · {who.DisplayName}`,
		"FLY: WASD where the camera looks, Space up, Ctrl down, Shift faster (the stick on a phone). NOCLIP: through walls. HIDDEN: zombies and bandits ignore the target. ONE-HIT KILLS: every round kills. GOD: no damage to the target or their car. (The guns have no ammo or reload, so there is nothing to make infinite.)"
	)
	local toggles = grid(200)
	for _, flag in FLAGS do
		local on = who:GetAttribute(flag.attribute) == true
		toggle(toggles, flag.label, on, function()
			send(flag.command, not on)
		end)
	end
	local speed = tonumber(who:GetAttribute("AdminSpeed")) or 1
	local walk = row("Walking speed")
	for _, n in { 1, 2, 4 } do
		small(walk, `{n}×`, if n == speed then C.yellow else C.grey, function()
			send("speed", n)
		end)
	end
	heading("Players", if who == player then "Pick another player as the TARGET at the top to bring them or go to them." else `BRING: {who.DisplayName} to you. GO TO: you to {who.DisplayName}.`)
	local moves = grid(200)
	if who ~= player then
		action(moves, "BRING TO ME", C.yellow, function()
			send("bring")
		end)
		action(moves, "GO TO THEM", C.blue, function()
			send("goto")
		end)
	end
	action(moves, "HEAL", C.green, function()
		send("heal")
	end)
	action(moves, "CLEAR WANTED", C.grey, function()
		send("clearWanted")
	end)
end

-- WORLD: the clock, the enemies, the traffic, the landmarks.
R.world = function()
	local night = Config.DayNight
	heading("Time of day", string.format("The clock runs (a day is %d min). Night from %02d:%02d to %02d:%02d: dark, more zombies, bigger waves, better pay, the lamps and headlights on.", math.floor(night.DayLength / 60), math.floor(night.NightFrom), math.floor(night.NightFrom % 1 * 60), math.floor(night.NightTo), math.floor(night.NightTo % 1 * 60)))
	local cells = grid(150)
	local times: { { hour: number, label: string } } = {
		{ hour = 0, label = "00:00 Midnight" },
		{ hour = 5.5, label = "05:30 Dawn" },
		{ hour = 9, label = "09:00 Morning" },
		{ hour = 12, label = "12:00 Noon" },
		{ hour = 15, label = "15:00 Afternoon" },
		{ hour = 17.75, label = "17:45 Dusk" },
		{ hour = 20, label = "20:00 Evening" },
		{ hour = 22, label = "22:00 Night" },
	}
	for _, entry in times do
		local hour = entry.hour
		local dark = hour >= night.NightFrom or hour < night.NightTo
		action(cells, entry.label, if dark then P.violet elseif hour >= 7 and hour <= 17 then C.blue else P.bronze, function()
			send("time", hour)
		end)
	end

	local frozen = workspace:GetAttribute("AdminFrozen") == true
	heading("Enemies on the map", "KILL ALL kills every enemy and bandit car on the whole map. FREEZE stops them all where they stand (off again when you leave).")
	local map = grid(200)
	action(map, "KILL ALL ON THE MAP", C.red, function()
		send("killAll")
	end)
	toggle(map, "FREEZE", frozen, function()
		send("freeze", not frozen)
	end)
	action(map, "CLEAR NEAR ME", C.grey, function()
		send("clear")
	end)
	action(map, "BANDIT CAR", C.red, function()
		send("banditCar")
	end)
	local horde = row("Horde around you")
	for _, n in { 10, 20, 30 } do
		small(horde, `×{n}`, C.red, function()
			send("horde", n)
		end)
	end
	local counts = row("How many of a kind")
	for _, n in { 1, 3, 5, 10 } do
		small(counts, `×{n}`, if spawnCount == n then C.yellow else C.grey, function()
			spawnCount = n
			render(true)
		end)
	end
	local kinds = {}
	for kind in Config.Zombies do
		table.insert(kinds, kind)
	end
	table.sort(kinds, function(a, b)
		return Config.Zombies[a].health < Config.Zombies[b].health
	end)
	local spawn = grid(150)
	for _, kind in kinds do
		local def = Config.Zombies[kind]
		action(spawn, def.name, if def.ranged then C.red else C.green, function()
			send("spawn", { kind = kind, count = spawnCount })
		end)
	end

	heading("Traffic", "Civilian cars on the lanes near you.")
	local traffic = grid(150)
	action(traffic, "+1 CAR", C.blue, function()
		send("traffic", 1)
	end)
	action(traffic, "+5 CARS", C.blue, function()
		send("traffic", 5)
	end)

	heading(`Teleport · {whom()}`, "To the road at the place. A driver's car comes along.")
	local places = grid(232)
	local kindColors: { [string]: Color3 } = { shop = C.blue, employer = P.gold, place = P.violet }
	for _, landmark in Map.Landmarks do
		leftAligned(action(places, `{landmark.icon} {landmark.name}`, kindColors[landmark.kind] or C.grey, function()
			send("teleport", landmark.id)
		end))
	end
end

-- JOBS & MISSIONS: the jobs, the missions (shared/Missions.luau) and the challenges (shared/Challenges.luau).
R.jobs = function()
	heading(`Jobs · {whom()}`, "Starts it now with its vehicle (a running job is cancelled). FINISH THE JOB pays the whole job as delivered.")
	local testing = grid(200)
	action(testing, "FINISH THIS STOP", C.blue, function()
		send("finishStop")
	end)
	action(testing, "FINISH THE JOB", C.yellow, function()
		send("finishJob")
	end)
	-- 4.8: a road event on the running job (it comes as you drive on).
	for _, kind in { "survivor", "addon", "roadblock" } do
		action(testing, `EVENT: {string.upper(kind)}`, C.grey, function()
			send("roadEvent", kind)
		end)
	end
	local special = grid(150)
	for _, def in Config.JobTypes do
		action(special, def.name, C.yellow, function()
			send("job", def.id)
		end)
	end
	local ordinary = grid(150)
	local colors = { C.green, C.yellow, C.red, P.violet }
	for index, tier in Config.Jobs.Tiers do
		action(ordinary, `{string.rep("★", tier.stars)} {tier.name}`, colors[index] or C.grey, function()
			send("job", `ordinary{index}`)
		end)
	end
	action(ordinary, "🚶 On foot", C.green, function()
		send("job", "foot") -- 5.0: an ON FOOT job (Jobs.adminStart)
	end)

	local got, most = MissionData.stars(missionProgress, nil)
	heading(`Missions · your {got} / {most} ★`, "ALL 3 ★: every mission done at 3 stars (no money). RESET: the progress cleared. A mission button starts it now (locks ignored; NIGHT ONLY turns the clock to night). The stars shown are yours.")
	local all = grid(200)
	action(all, "ALL MISSIONS 3 ★", C.yellow, function()
		send("missionsAll")
	end)
	action(all, "RESET MISSIONS", C.red, function()
		send("missionsReset")
	end)
	for _, campaign in MissionData.Campaigns do
		local done = MissionData.done(missionProgress, campaign.id)
		local rgb = campaign.color
		local color = Color3.fromRGB(rgb[1] or 200, rgb[2] or 200, rgb[3] or 200)
		heading(`{campaign.icon} {campaign.name} · LV {campaign.level} · {done}/10`, campaign.client)
		local missions = grid(232)
		for _, def in MissionData.ofCampaign(campaign.id) do
			local best = missionProgress[def.id] or 0
			local twists = ""
			local twistList: { string } = def.twists or {}
			for _, twist in twistList do
				local info = Config.Missions.Twists[twist]
				twists ..= if info then info.icon else ""
			end
			local mark = if best > 0 then " " .. string.rep("★", best) else ""
			local button = action(missions, `{def.number}. {def.name}{if def.coop then " 👥" else ""} {twists}{mark}`, if best > 0 then C.green else C.panelLight, function()
				send("missionStart", def.id)
			end)
			leftAligned(button)
			-- The campaign's colour on the button's own border (one UIStroke per button).
			local border = button:FindFirstChildOfClass("UIStroke")
			if border then
				border.Color = color
				border.Thickness = 1.5
			end
		end
	end

	local state = challengeState
	heading(
		`Challenges · your {state.done} / {#ChallengeData.List} · secrets {state.secrets} / {state.secretsTotal} · places {state.visited} / {state.placesTotal}`,
		"ALL CHALLENGES gives every challenge's money and title, every campaign's reward and Dead End. RESET takes the exclusive guns and paints back too."
	)
	local challenges = grid(200)
	action(challenges, "ALL CHALLENGES", C.yellow, function()
		send("challengesAll")
	end)
	action(challenges, "ALL SECRETS FOUND", C.blue, function()
		send("secretsAll")
	end)
	action(challenges, "RESET CHALLENGES", C.red, function()
		send("challengesReset")
	end)
	heading(`Title · {whom()}`, "Given and shown over the head and on the leaderboard (TOP). The marks are your own titles.")
	local titles = grid(232)
	action(titles, "NO TITLE", C.grey, function()
		send("title", "none")
	end)
	for _, title in ChallengeData.allTitles() do
		local mine = target() == player
		action(titles, title, if mine and state.title == title then C.yellow elseif mine and state.titles[title] then C.green else C.panelLight, function()
			send("title", title)
		end)
	end
end

-- The real estate (Config.Estate) and the company's safe (Config.Business). The target's attributes Estates
-- ("id,id,…") and Home (server/Estate.luau) mark what they own: yellow = the home, green = owned.
local ESTATE_KINDS = { mansion = "🏰", villa = "🏡", house = "🏠", garage = "🅿️", office = "🏢" }

R.estate = function()
	local who = target()
	local owned: { [string]: boolean } = {}
	local list = who:GetAttribute("Estates")
	if type(list) == "string" then
		for id in string.gmatch(list, "[^,]+") do
			owned[id] = true
		end
	end
	local home = who:GetAttribute("Home")
	local slots = tonumber(who:GetAttribute("CarSlots")) or Config.Estate.BaseCarSlots
	heading(`Real estate · {whom()}`, `Homes, garages and offices for free (green = owned, yellow = the home). Car slots now: {slots}. Players open the list with H or the ESTATE button.`)
	local all = grid(200)
	action(all, "GIVE EVERY PROPERTY", C.yellow, function()
		send("giveEstate", "all")
	end)
	action(all, "TAKE THEM ALL AWAY", C.red, function()
		send("clearEstate")
	end)
	action(all, "SPAWN AT THE DEPOT", C.grey, function()
		send("setHome", "depot")
	end)
	heading("Give a property", "Click: it is the target's (no money). A first home becomes the home.")
	local cells = grid(232)
	for _, def in Config.Estate.Properties do
		local color = if home == def.id then C.yellow elseif owned[def.id] then C.green else C.blue
		leftAligned(action(cells, `{ESTATE_KINDS[def.kind] or "🏠"} {def.name}`, color, function()
			send("giveEstate", def.id)
		end))
	end
	heading("Set the home", "The target spawns there after every death (and after PLAY). It is given first if not owned.")
	local homes = grid(232)
	for _, def in Config.Estate.Properties do
		if def.kind == "mansion" or def.kind == "villa" or def.kind == "house" then
			local on = home == def.id
			action(homes, `{if on then "★ " else ""}{def.name}`, if on then C.yellow else C.panelLight, function()
				send("setHome", def.id)
			end)
		end
	end
	heading("Teleport to a property", "Inside at its door (homes, offices), else the road at its plot.")
	local places = grid(232)
	for _, def in Config.Estate.Properties do
		leftAligned(action(places, `{ESTATE_KINDS[def.kind] or "🏠"} {def.name}`, P.violet, function()
			send("estateTeleport", def.id)
		end))
	end
	heading("Company safe", `The company's earnings wait in the safe (up to {Ui.money(Config.Business.SafeCap)}) until they are COLLECTED at the office computer.`)
	local safe = grid(200)
	action(safe, "FILL THE SAFE", C.green, function()
		send("businessCash")
	end)
	action(safe, "+" .. Ui.money(50_000), C.green, function()
		send("businessCash", 50_000)
	end)
	action(safe, "EMPTY THE SAFE", C.grey, function()
		send("businessCash", -Config.Business.SafeCap)
	end)
end

-- BUDDIES (server/Buddy.luau): NPC companions that play along with the target.
R.buddies = function()
	local who = target()
	local count = tonumber(who:GetAttribute("AdminBuddies")) or 0
	local mode = who:GetAttribute("AdminBuddyMode")
	heading(
		`Buddies · {whom()} · {count} now`,
		"NPC companions. FOLLOW: with the owner, on foot and in the car. STAY: they stand where they are (and still fight). GUARD: they hold the spot and fight anything that comes near."
	)
	local add = grid(150)
	action(add, "+ ADD 1", C.yellow, function()
		send("buddy", 1)
	end)
	action(add, "+ ADD 3", C.green, function()
		send("buddy", 3)
	end)
	action(add, "DISMISS ALL", C.red, function()
		send("buddyDismiss")
	end)
	heading("Mode")
	local modes = grid(150)
	for _, entry in { { "follow", "FOLLOW" }, { "stay", "STAY" }, { "guard", "GUARD" } } do
		local id = entry[1]
		action(modes, entry[2], if mode == id then C.yellow else C.grey, function()
			send("buddyMode", id)
		end)
	end
end

render = function(keepScroll: boolean?)
	local content = parts.content
	if not content then
		return
	end
	local scroll = content.CanvasPosition
	Ui.clear(content)
	order = 0
	for id, button in tabButtons do
		local selected = id == section
		-- The section tabs: the selected one raised with the narrow red rule, the others quiet rows.
		Ui.selectRow(button, selected)
		button.TextColor3 = if selected then C.text else C.dim
	end
	-- The target picker's selection, and the target in the header.
	local who = target()
	for _, button in parts.picker:GetChildren() do
		if button:IsA("TextButton") then
			local on = button:GetAttribute("UserId") == targetId
			Ui.selectRow(button, on)
			button.TextColor3 = if on then C.text else C.dim
		end
	end
	parts.chrome.subtitle.Text = `Testing tools · P · target: {who.DisplayName}`
	local renderer = R[section]
	if renderer then
		renderer()
	end
	if keepScroll then
		task.defer(function()
			if content.Parent then
				content.CanvasPosition = scroll
			end
		end)
	else
		content.CanvasPosition = Vector2.zero
	end
end

-- One re-render per frame at most (several attributes may change at once), keeping the scroll.
local renderQueued = false
local function rerender()
	if renderQueued or not parts.window or not parts.window.Visible then
		return
	end
	renderQueued = true
	task.defer(function()
		renderQueued = false
		if parts.window.Visible then
			render(true)
		end
	end)
end

-- ── The target picker ──────────────────────────────────────────────────────

local function buildPicker()
	local picker = parts.picker
	if not picker then
		return
	end
	for _, child in picker:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		if a == player or b == player then
			return a == player
		end
		return string.lower(a.DisplayName) < string.lower(b.DisplayName)
	end)
	for index, other in list do
		local id = other.UserId
		local name = if other == player then `{other.DisplayName} (you)` else other.DisplayName
		local button = Ui.button(picker, name, UDim2.fromOffset(150, 34), P.lavenderDeep, function()
			targetId = id
			render(true)
		end)
		button.TextSize = 14
		button.TextWrapped = false
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.LayoutOrder = index
		button:SetAttribute("UserId", id)
	end
end

-- ── The window ─────────────────────────────────────────────────────────────

local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera or not parts.scale then
		return
	end
	local size = camera.ViewportSize
	parts.scale.Scale = math.clamp(math.min(size.X / 1150, size.Y / 680), 0.55, 1.1)
end

local function setOpen(open: boolean)
	local window = parts.window
	if not window then
		return
	end
	window.Visible = open and isAdmin()
	if window.Visible then
		buildPicker()
		render()
	end
end

local WINDOW_SIZE = Vector2.new(880, 600)
local PICKER_HEIGHT = 50
local SIDEBAR_WIDTH = 190

local function build()
	local gui = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryAdmin",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
	}, player:WaitForChild("PlayerGui"))
	parts.gui = gui

	local window, inner, chrome = Ui.window(gui, "Admin", "Testing tools · P", "🛠", UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y))
	window.Visible = false
	chrome.onClose = function()
		setOpen(false)
	end
	parts.window = window
	parts.chrome = chrome
	parts.scale = Ui.make("UIScale", {}, window)
	-- The server's last answer, in the footer (the toasts are behind the window).
	parts.status = chrome.context
	parts.status.TextColor3 = C.text

	-- 4.5: the target picker: a strip over everything (you first, then everybody by name), a fine line under it.
	local strip = Ui.make("Frame", {
		Name = "Target",
		Size = UDim2.new(1, -28, 0, PICKER_HEIGHT - 8),
		Position = UDim2.fromOffset(14, 6),
		BackgroundTransparency = 1,
	}, inner)
	Ui.label(strip, "TARGET", UDim2.new(0, 70, 1, 0), {
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = C.dim,
		TextWrapped = false,
	})
	parts.picker = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -76, 1, 0),
		Position = UDim2.fromOffset(76, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = P.ink2,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
	}, strip)
	Ui.list(parts.picker, false, 6)
	local pickerLayout = parts.picker:FindFirstChildOfClass("UIListLayout")
	if pickerLayout then
		pickerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	Ui.make("Frame", {
		Name = "Line",
		Size = UDim2.new(1, -28, 0, 1),
		Position = UDim2.fromOffset(14, PICKER_HEIGHT),
		BackgroundColor3 = Theme.Contract.rule,
		BorderSizePixel = 0,
	}, inner)

	-- The sections: a recessed sidebar of tabs (the Dispatch board's filters).
	local sidebar = Ui.make("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, SIDEBAR_WIDTH, 1, -(PICKER_HEIGHT + 1)),
		Position = UDim2.fromOffset(0, PICKER_HEIGHT + 1),
		BackgroundColor3 = P.lavenderDeep,
		BorderSizePixel = 0,
	}, inner)
	local tabs = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, -20),
		Position = UDim2.fromOffset(14, 12),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, sidebar)
	Ui.list(tabs, true, 6)
	for index, entry in SECTIONS do
		local id = entry[1]
		local button = Ui.button(tabs, entry[2], UDim2.new(1, -4, 0, 40), P.lavenderDeep, function()
			section = id
			render()
			if id == "jobs" then
				Net.get("Missions"):FireServer("open")
				Net.get("Challenges"):FireServer("open")
			end
		end)
		button.TextSize = 15
		button.TextXAlignment = Enum.TextXAlignment.Left
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 8) }, button)
		button.LayoutOrder = index
		tabButtons[id] = button
	end

	local content = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -(SIDEBAR_WIDTH + 30), 1, -(PICKER_HEIGHT + 14)),
		Position = UDim2.fromOffset(SIDEBAR_WIDTH + 18, PICKER_HEIGHT + 10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = P.ink2,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, inner)
	Ui.list(content, true, 8)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 10), PaddingRight = UDim.new(0, 8) }, content)
	parts.content = content

	-- The small button top right (under Roblox's own buttons; a phone opens the panel with it).
	-- A quiet dark action (only admins see it), the red is just its accent and text.
	local openButton = Ui.button(gui, "🛠  ADMIN", UDim2.fromOffset(96, 32), C.red, function()
		setOpen(not window.Visible)
	end)
	openButton.AnchorPoint = Vector2.new(1, 0)
	openButton.Position = UDim2.new(1, -16, 0, 56)
	openButton.TextSize = 13
	openButton.TextColor3 = C.red
	openButton.Visible = false
	Ui.make("UIScale", {}, openButton)
	parts.openButton = openButton
end

-- The ADMIN button shows for admins once the game's interface is on (after PLAY on the start screen).
local function refreshButton()
	local openButton = parts.openButton
	if not openButton then
		return
	end
	local playerGui = player:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	local hudOn = not (hud and hud:IsA("ScreenGui")) or hud.Enabled
	openButton.Visible = isAdmin() and hudOn
	if not isAdmin() and parts.window and parts.window.Visible then
		parts.window.Visible = false
	end
end

-- The attributes the sections show (on the target): a change re-renders the open panel.
local WATCHED: { [string]: boolean } = {
	Level = true,
	God = true,
	AdminFly = true,
	AdminNoclip = true,
	AdminJump = true,
	AdminCarBoost = true,
	AdminHidden = true,
	AdminOneHit = true,
	AdminSpeed = true,
	AdminBuddies = true,
	AdminBuddyMode = true,
	Estates = true,
	Home = true,
	CarSlots = true,
}

local function watchPlayer(other: Player)
	other.AttributeChanged:Connect(function(name: string)
		if WATCHED[name] and other.UserId == targetId then
			rerender()
		end
	end)
end

function AdminPanel.start()
	build()
	updateScale()
	local stamp = 0
	Net.get("Notice").OnClientEvent:Connect(function(text: any)
		local status = parts.status
		if not status then
			return
		end
		stamp += 1
		local mine = stamp
		status.Text = tostring(text)
		task.delay(4, function()
			if stamp == mine then
				status.Text = ""
			end
		end)
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	player:GetAttributeChangedSignal("Admin"):Connect(refreshButton)
	-- 4.5: everybody in the server can be the target; the picker follows who comes and goes.
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(function(other: Player)
		watchPlayer(other)
		if parts.window.Visible then
			buildPicker()
			render(true)
		end
	end)
	Players.PlayerRemoving:Connect(function(other: Player)
		task.defer(function()
			if other.UserId == targetId then
				targetId = player.UserId
			end
			if parts.window.Visible then
				buildPicker()
				render(true)
			end
		end)
	end)
	workspace:GetAttributeChangedSignal("AdminFrozen"):Connect(function()
		if section == "world" then
			rerender()
		end
	end)
	-- Your mission ratings (the same "state" the MISSIONS window gets), asked when the JOBS & MISSIONS tab opens.
	Net.get("Missions").OnClientEvent:Connect(function(kind: any, state: any)
		if kind ~= "state" or type(state) ~= "table" or type(state.progress) ~= "table" then
			return
		end
		missionProgress = {}
		for id, stars in state.progress do
			if type(id) == "string" and type(stars) == "number" then
				missionProgress[id] = stars
			end
		end
		if section == "jobs" then
			rerender()
		end
	end)
	-- 3.1: your challenges' state (the same "state" the MISSIONS window's tabs get).
	Net.get("Challenges").OnClientEvent:Connect(function(kind: any, state: any)
		if kind ~= "state" or type(state) ~= "table" then
			return
		end
		local function size(set: any): number
			local n = 0
			if type(set) == "table" then
				for _ in set do
					n += 1
				end
			end
			return n
		end
		local titles: { [string]: boolean } = {}
		if type(state.titles) == "table" then
			for title, on in state.titles do
				if type(title) == "string" and on then
					titles[title] = true
				end
			end
		end
		challengeState = {
			done = size(state.done),
			secrets = size(state.secrets),
			secretsTotal = tonumber(state.secretsTotal) or 0,
			visited = size(state.visited),
			placesTotal = tonumber(state.placesTotal) or 0,
			title = if type(state.title) == "string" then state.title else nil,
			titles = titles,
		}
		if section == "jobs" then
			rerender()
		end
	end)
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = playerGui:FindFirstChild("ZombieDeliveryHud")
	if hud and hud:IsA("ScreenGui") then
		hud:GetPropertyChangedSignal("Enabled"):Connect(refreshButton)
	end
	refreshButton()

	-- P opens and closes the panel (not while typing in a text box, e.g. the chat). Bound at a high priority, so no
	-- other binding of the game or of Roblox can swallow it.
	ContextActionService:BindActionAtPriority("ZombieDeliveryAdmin", function(_name, state, _input)
		if state ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if isAdmin() then
			setOpen(not parts.window.Visible)
			print(`[AdminPanel] P: the panel is {if parts.window.Visible then "open" else "closed"}`)
			return Enum.ContextActionResult.Sink
		end
		warn("[AdminPanel] P pressed, but you are not an admin (Config.Admin)")
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 100, Enum.KeyCode.P)
	print(`[AdminPanel] ready: press P (admin: {isAdmin()})`)
end

function AdminPanel.isOpen(): boolean
	local window = parts.window
	return window ~= nil and window.Visible == true
end

return AdminPanel
