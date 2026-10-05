--!strict
-- The MISSIONS window (3.0, key U and the Hud's MISSIONS button), in the Dead End Dispatch look: the campaigns of
-- shared/Missions.luau (3.2: ten stories and the DUO campaign, 110 story jobs; every count comes from the data), taken
-- from anywhere.
--
--   * Left: the campaigns (icon, name, the client, missions done X/10, stars; a locked one says what it waits for:
--     "🔒 Finish Code Red first · LEVEL 5", or "🔒 LEVEL 5"; the DUO campaign has a 🤝 DUO badge).
--   * Right: the selected campaign's pitch and progress, then its ten missions as cards: the number, the name, the
--     status (locked / open / done with ★★☆), the twist chips (icon and name; hovering one shows what it does), the
--     CO-OP badge, the tier, the cargo, the lent vehicle and a pay hint. A card opens below itself: the client's
--     briefing in a speech bubble, the route, the twists explained, the rewards and START. A member of somebody
--     else's crew sees "Your crew leader picks the mission" instead (server/Missions.luau checks everything).
--   * A co-op card has FIND CREW: it puts you on the crew board (the CrewBoard remote) and opens the crew panel
--     through MissionsUi.onFindCrew (Main may wire it; without it CrewPanel.open is called directly).
--   * The header: every star you have (X / 330) and the filter tabs ALL / CO-OP.
--   * 3.2: a locked mission card says its own level ("🔒 LEVEL 7"); a DUO mission has the 🤝 DUO chip (only with a
--     crew: Config.Missions.Duo.MinCrew members with you at START). START on one without a crew says why and FIND
--     CREW is right next to it; the banner shows DUO and the TWIN SWITCHES levers (gatePulled 0 – 2).
--   * 3.4: a mission with more cargo than your car holds (the state's capacity and carName, Economy.cargoNeed) has a
--     red "📦 needs N slots" chip, a line in its card and START says why (unless it lends a vehicle).
--   * The campaign's header also shows its 3.1 reward (Config.Rewards.Campaigns: an exclusive gun or paint and a title).
-- 3.1, the other tabs (the Challenges remote's "state"; ("open") is sent when one of them shows):
--   * CHALLENGES: the final reward on top (Dead End, a dark silhouette with ??? until earned, "Complete every
--     challenge (X/40)"), then shared/Challenges.luau List by category: the name, the description, a progress bar
--     value/goal, the money and the title, ✓ when done; a hidden one shows ??? until it is done.
--   * SECRETS: the lost packages found X/30 and the money so far, the final reward (the Phantom paint and a title),
--     every package by place: ✓ when found, else its hint (or "Visit <place> first" before you have been there).
--   * REWARDS: the ten campaign rewards (a click opens the campaign), your titles with EQUIP (("title", t), or none),
--     the exclusive guns and paints (yours with an EXCLUSIVE badge, the others with how to get them).
-- Outside the window:
--   * 3.1: the Challenges remote's "unlocked" as a celebratory card in the Hud's top stack (Hud.topSlot("unlocked"),
--     the 3.0 cleared card's style), one at a time from a queue: a strip for a new place, a card for a lost package
--     or a challenge, a BIG card with a glow and confetti for a campaign's, every package's and every challenge's
--     reward. They all wait while the DELIVERY result, the cleared card (or one on its way) or this window is up, so
--     nothing covers them. A click dismisses one.
--   * During a mission a compact banner in the Hud's top stack (Hud.topSlot("mission")): "MISSION 3/10 · Name", the
--     twists, the CO-OP crew count and the HOLD OUT countdown. It follows your own job (the Job remote's `mission`)
--     or, for a crew member, the leader's (CrewState status.mission).
--   * When a mission is done (the Missions remote's "cleared"): a celebration card with the stars flying in, the
--     client's debrief, the rewards, a finished campaign and NEXT MISSION.
-- The window is built on the first open. The server answers START with a Notice; while the window is open it shows
-- in the subtitle too (the toasts are behind the window). While it is open the mouse is free (Main:
-- CameraRig.mouseNeeded checks MissionsUi.isOpen()).
-- 3.8 (the contract UI, design/ui-contract/; it replaced 3.6's paper tickets): the charcoal window (Ui.window: a
-- small caps label and the title, a small ✕, a slim footer with ESC and your stars; ESC closes it), the page tabs as
-- flat text tabs (the open one raised, a red rule under it), the campaigns as flat rows with their colour as a thin
-- rule on the left, the missions as rows (a numbered spine, a payout column behind a fine line with the pay and the
-- status; hover brightens them, the selected one has the red rule, locked ones sit a step darker), the twists as
-- compact tags, the briefing as a note in the open card. Outside the window the same: the banner a compact charcoal
-- scrim under the objective, the celebration card and the unlock popups charcoal cards with their colour as a fine
-- rim. Light text on charcoal throughout (Theme.Postage is remapped to the contract values; the accents
-- Theme.Colors green / red / yellow / money read on charcoal).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local Missions = require(Shared.Missions)
local Challenges = require(Shared.Challenges)
local Icons = require(Shared.Icons)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local Hud = require(script.Parent.Hud)
local CrewPanel = require(script.Parent.CrewPanel)

type MissionDef = Missions.MissionDef
type Campaign = Missions.Campaign

local C = Ui.Colors
local P = Theme.Postage -- 3.8: remapped to the contract values (see Theme)
local K = Theme.Contract
local T = Config.Missions
local MissionsUi = {}

-- Set by Main: opening this window closes the others.
MissionsUi.onOpen = nil :: (() -> ())?
-- Set by Main: FIND CREW on a co-op mission opens the crew panel (CrewPanel.open); the mission id it was for.
-- Without it FIND CREW opens the crew panel itself.
MissionsUi.onFindCrew = nil :: ((missionId: string) -> ())?

local player = Players.LocalPlayer

local BASE_W, BASE_H = 900, 640 -- the window's design size (smaller on small screens, see updateScale)
local LEFT_W = 262 -- the campaign list
local TOP = 88 -- where the lists start in the window's content, under the page tabs (the extra pages: TOP - 32)
local NOTICE_TIME = 4
local CLEARED_TIME = 22 -- seconds the celebration card stays
local SUBTITLE = `{#Missions.Campaigns} stories · {#Missions.List} jobs · play them with your crew · U`
local CARGO_EMOJI: { [string]: string } = {
	crate = "📦", ammo = "🧨", sack = "🛍️", barrel = "🛢️", icebox = "🧊", furniture = "🛋️", soup = "🍲", horse = "🐴",
	kid = "🧒", patient = "🤕", pizza = "🍕", parcel = "📦", medicine = "💊", vaccine = "💉", sample = "🧪",
	groceries = "🛒", tools = "🧰", bread = "🍞", cake = "🎂", cash = "💰", water = "💧", generator = "🔌",
	battery = "🔋", tnt = "🧨", documents = "💼", electronics = "📻", weapons = "🔫", painting = "🖼️", mail = "✉️",
	tires = "🛞", plants = "🌱", survivor = "🧍",
}

-- ── State ──────────────────────────────────────────────────────────────────

local progress: { [string]: number } = {} -- best stars per mission (the server's state)
local serverLevel: number? = nil
local active: string? = nil -- my mission running (the server's state)
local crewOwner: string? = nil -- the leader's name when I am in somebody else's crew
local ownJob = false -- a job of my own runs (the Job remote)
local jobMission: any = nil -- my job's mission (the Job remote's `mission`)
local jobCrew = 0 -- paid besides me on my job (the Job remote's crewCount)
local crewMission: any = nil -- the leader's mission when I am a member (CrewState status.mission)
local crewCount = 0
local defendAt = 0 -- os.clock() when the HOLD OUT seconds came

local selectedCampaign = Missions.Campaigns[1].id
local selectedMission: string? = nil
local filter = "all" -- "all" | "coop"
local pendingStart: string? = nil -- START was pressed for this one: the window closes when it runs
local hasState = false -- the server's state came at least once
local blindPick = false -- the window opened before it did: the first state picks the campaign again
local remote: RemoteEvent? = nil

-- The window's parts (built on the first open) and the banner's / the card's.
local refs: { [string]: any } = {}

-- ── Small helpers ──────────────────────────────────────────────────────────

local function getRemote(): RemoteEvent
	if not remote then
		remote = Net.get("Missions")
	end
	return remote :: RemoteEvent
end

local function ask(action: string, arg: any?)
	getRemote():FireServer(action, arg)
end

-- Is the game's interface on (after PLAY on the start screen)?
local function hudOn(): boolean
	local playerGui = player:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	return not (hud and hud:IsA("ScreenGui")) or hud.Enabled
end

local function myLevel(): number
	return serverLevel or tonumber(player:GetAttribute("Level")) or 1
end

local function colorOf(campaign: Campaign?): Color3
	if not campaign then
		return C.yellow
	end
	local rgb = campaign.color
	return Color3.fromRGB(rgb[1] or 255, rgb[2] or 255, rgb[3] or 255)
end

local function campaignOf(def: MissionDef): Campaign?
	return Missions.findCampaign(def.campaign)
end

-- Text from the data in a RichText label: &, < and > as entities.
local function esc(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

local function placeName(id: string?): string?
	if not id then
		return nil
	end
	for _, place in Map.Places do
		if place.id == id then
			return place.name
		end
	end
	return (string.gsub(id, "^%l", string.upper))
end

local function vehicleName(id: string?): string?
	if not id then
		return nil
	end
	local car = Economy.findCar(id)
	return if car then car.name else id
end

local function cargoEmoji(def: MissionDef): string
	return CARGO_EMOJI[def.itemKind] or "📦"
end

local function pieceName(def: MissionDef): string
	local kind = Config.Cargo.Kinds[def.itemKind]
	if not kind then
		return string.lower(def.cargo)
	end
	return if def.items == 1 then kind.piece else kind.plural
end

-- About what the mission pays (before the bonuses, the crew and the condition): the tier's pay for an average route,
-- its stops, the twists.
local function payHint(def: MissionDef): number
	local tier = Config.Jobs.Tiers[def.tier] or Config.Jobs.Tiers[1]
	local base = Economy.jobPay(tier, (tier.minDistance + tier.maxDistance) / 2) + def.payPerStop * (def.pickups + def.drops)
	return math.floor(base * Missions.twistPay(def) / 10 + 0.5) * 10
end

local function twistsOf(def: { twists: { string }? }): { string }
	return def.twists or {}
end

-- The stars of a mission (0 = not done).
local function best(id: string): number
	return math.clamp(progress[id] or 0, 0, 3)
end

-- "open" | "done" | "locked" (with why) | "active".
local function statusOf(def: MissionDef): (string, string?)
	if active == def.id or (jobMission and jobMission.id == def.id) then
		return "active", nil
	end
	local ok, why = Missions.unlocked(def.id, progress, myLevel())
	if not ok then
		return "locked", why
	end
	return if best(def.id) > 0 then "done" else "open", nil
end

-- 3.2: shut until the campaigns it requires are finished and you have its level (Missions.campaignOpen).
local function campaignLocked(campaign: Campaign): boolean
	return not (Missions.campaignOpen(campaign.id, progress, myLevel()))
end

local function visible(def: MissionDef): boolean
	return filter ~= "coop" or def.coop == true
end

-- The mission to show first in a campaign: the first open one not done yet, else the first one.
local function currentMission(campaignId: string): string?
	local list = Missions.ofCampaign(campaignId)
	for _, def in list do
		if visible(def) and best(def.id) == 0 and Missions.unlocked(def.id, progress, myLevel()) then
			return def.id
		end
	end
	for _, def in list do
		if visible(def) then
			return def.id
		end
	end
	return nil
end

-- The campaign to show first: the first open one that is not finished.
local function currentCampaign(): string
	local fallback = Missions.Campaigns[1].id
	for _, campaign in Missions.Campaigns do
		-- 3.2: the story first (the DUO campaign is a side story for when you have a crew).
		if not campaignLocked(campaign) and not campaign.duo then
			fallback = campaign.id
			local done, total = Missions.done(progress, campaign.id)
			if done < total then
				return campaign.id
			end
		end
	end
	return fallback
end

-- The mission after this one (the next in its campaign, else the next campaign's first).
local function nextMission(id: string): MissionDef?
	local def = Missions.find(id)
	if not def then
		return nil
	end
	local following = Missions.find(`{def.campaign}_{def.number + 1}`)
	if following then
		return following
	end
	for index, campaign in Missions.Campaigns do
		if campaign.id == def.campaign then
			-- 3.2: the next story campaign (the DUO one is a side story you pick yourself).
			for after = index + 1, #Missions.Campaigns do
				local candidate = Missions.Campaigns[after]
				if not candidate.duo then
					return Missions.ofCampaign(candidate.id)[1]
				end
			end
			return nil
		end
	end
	return nil
end

-- A main action on (its pastel `color`, ink) or off (the disabled lavender, the quiet ink).
local function paintButton(button: any, text: string, color: Color3, enabled: boolean)
	button.Text = text
	button.BackgroundColor3 = if enabled then color else P.lavenderDeep
	button.TextColor3 = if enabled then P.ink else P.ink2
	button.AutoButtonColor = false
end

-- ── 3.1: challenges, secrets, rewards (the state and the small helpers) ─────

-- The Challenges remote's "state" (S in the 3.1 spec), checked and flattened: what the CHALLENGES / SECRETS / REWARDS
-- tabs, the campaign headers and the popups show. Empty until the server's first state.
type ChallengeState = {
	values: { [string]: number }, -- every stat any challenge uses
	done: { [string]: boolean }, -- challenge id → done
	secrets: { [string]: boolean }, -- secret id → found
	secretsTotal: number,
	visited: { [string]: boolean }, -- place id → visited
	placesTotal: number,
	titles: { [string]: boolean }, -- earned titles
	title: string?, -- the one shown over your head
	campaigns: { [string]: boolean }, -- rewards.campaigns: campaign id → its reward given
	secretsReward: boolean, -- rewards.secrets
	challengesReward: boolean, -- rewards.challenges
}
type SecretEntry = { id: string, place: string, hint: string }
type RewardItem = { weapon: string?, paint: string? }
type ExclusiveItem = { kind: string, id: string, name: string, exclusive: string, reward: RewardItem }

-- Everything 3.1 adds to this module lives in one table (one top-level register; the file is big).
local Extras = {}
Extras.tab = "missions" -- the window's page: "missions" | "challenges" | "secrets" | "rewards"
Extras.hasState = false
Extras.remote = nil :: RemoteEvent?
Extras.secretCache = nil :: { SecretEntry }?
Extras.clearedPending = 0 -- "cleared" cards on their way (waiting for the DELIVERY result to close): popups wait too
Extras.pumpPopups = nil :: (() -> ())? -- shows the next waiting popup (set by the popups' block)
Extras.crewSize = 0 -- 3.2: members of my own crew (the server's state, CrewState as the owner): DUO missions need some
Extras.DUO_COLOR = P.danger -- 3.2: the DUO badge (the Partners in Crime red; 3.6: the danger ink on paper)
Extras.DUO_REFUSAL = "DUO mission: invite a friend first (K) and bring them here."
Extras.capacity = nil :: number? -- 3.4: the cargo slots of my equipped car (3.5: at its stage; the server's state)
Extras.carName = "car"
Extras.carId = "van" -- 3.5: my equipped car and its stage (the advice in the "too small" texts)
Extras.carStage = 0
Extras.state = {
	values = {},
	done = {},
	secrets = {},
	secretsTotal = 0,
	visited = {},
	placesTotal = #Map.Places,
	titles = {},
	title = nil,
	campaigns = {},
	secretsReward = false,
	challengesReward = false,
} :: ChallengeState
Extras.PURPLE = Color3.fromRGB(190, 80, 255) -- Dead End's colour (Config.Weapons deadend): rims and glows, not text
Extras.GOLD = C.yellow -- the titles (an amber that reads on charcoal)
Extras.SILHOUETTE = K.track -- an item you may not see yet: a dim grey shape on charcoal
-- The compact tags (3.8: a dark, barely tinted face from the consumable tags' set and a text that reads on it).
Extras.CHIP = {
	twist = { face = P.tags[2], ink = P.ink }, -- butter
	coop = { face = P.tags[1], ink = P.violet }, -- lilac
	duo = { face = P.tags[4], ink = P.danger }, -- rose
	warn = { face = P.tags[4], ink = P.danger },
	good = { face = P.sage, ink = P.ink },
	quiet = { face = P.lavenderDeep, ink = P.ink2 },
}
Extras.PAGES = {
	{ id = "missions", text = "🎯 MISSIONS", width = 140 },
	{ id = "challenges", text = "🏅 CHALLENGES", width = 196 },
	{ id = "secrets", text = "📦 SECRETS", width = 160 },
	{ id = "rewards", text = "🎁 REWARDS", width = 140 },
}
-- The challenge categories in the order the CHALLENGES tab shows them (an unknown one goes last).
Extras.CATEGORIES = {
	{ id = "combat", name = "COMBAT", icon = "⚔️" },
	{ id = "driving", name = "DRIVING", icon = "🚗" },
	{ id = "missions", name = "MISSIONS", icon = "🎯" },
	{ id = "explorer", name = "EXPLORER", icon = "🧭" },
	{ id = "coop", name = "CO-OP", icon = "👥" },
	{ id = "wealth", name = "WEALTH", icon = "💰" },
}

function Extras.ask(action: string, arg: any?)
	if not Extras.remote then
		Extras.remote = Net.get("Challenges")
	end
	(Extras.remote :: RemoteEvent):FireServer(action, arg)
end

-- ── The shapes this window uses (the window, the lines and the bars are Ui's; 3.8: flat contract shapes) ──

-- A compact tag that grows with its text (the twists, CO-OP, DUO, "needs N slots", EQUIPPED): `kind` is one of
-- Extras.CHIP.
function Extras.chip(parent: Instance, text: string, kind: string, order: number?): any
	local look = Extras.CHIP[kind] or Extras.CHIP.quiet
	local chip = Ui.label(parent, text, UDim2.new(0, 0, 1, 0), {
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = look.face,
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = look.ink,
		TextWrapped = false,
		LayoutOrder = order or 0,
	})
	Ui.corner(chip)
	Ui.stroke(chip, if look.ink == P.danger then P.danger else P.line, 1).Transparency = if look.ink == P.danger then 0.4 else 0
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, chip)
	return chip
end

-- A flat surface (a row, a card, a note): `face` (default the row), square, a fine line (`line`, a meaning's colour
-- for a selected / earned one). `radius` is ignored since 3.8 (kept for the callers).
function Extras.paper(frame: GuiObject, face: Color3?, line: Color3?, thickness: number?, radius: number?)
	local _ = radius
	frame.BackgroundColor3 = face or P.ticket
	frame.BackgroundTransparency = 0
	Ui.corner(frame)
	Ui.stroke(frame, line or P.line, math.min(thickness or 1, 1.5)).Transparency = 0
end

-- Something locked: 3.8 draws no hatching; the surface steps down (Theme.Postage.hatch) and its words say why.
function Extras.hatch(frame: GuiObject)
	frame.BackgroundColor3 = P.hatch
end

-- A page tab or a filter (raised with a red rule under it when on, quiet when off): Extras.paintTab sets which.
function Extras.tabButton(parent: Instance, text: string, width: number, order: number, onClick: () -> ()): any
	local button = Ui.make("TextButton", {
		Size = UDim2.fromOffset(width, 32),
		BackgroundColor3 = P.lavenderDeep,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = text,
		TextColor3 = P.ink2,
		Font = Theme.HeadingFont,
		TextSize = 14,
		LayoutOrder = order,
	}, parent)
	Ui.corner(button)
	Ui.stroke(button, P.line, 1).Transparency = 0
	Ui.make("Frame", {
		Name = "Rule",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = K.red,
		BorderSizePixel = 0,
		Visible = false,
	}, button)
	-- Hover / focus: the label brightens (the open tab is already bright).
	local function hover(on: boolean)
		if button:GetAttribute("On") ~= true then
			button.TextColor3 = if on then K.text else P.ink2
		end
	end
	button.MouseEnter:Connect(function() hover(true) end)
	button.MouseLeave:Connect(function() hover(false) end)
	button.SelectionGained:Connect(function() hover(true) end)
	button.SelectionLost:Connect(function() hover(false) end)
	button.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		onClick()
	end)
	return button
end

function Extras.paintTab(button: any, on: boolean)
	button:SetAttribute("On", on)
	button.BackgroundColor3 = if on then P.paper else P.lavenderDeep
	button.TextColor3 = if on then P.ink else P.ink2
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = P.line
	end
	local rule = button:FindFirstChild("Rule")
	if rule and rule:IsA("GuiObject") then
		rule.Visible = on
	end
end

-- A colour as RichText's "#RRGGBB".
function Extras.hex(color: Color3): string
	return "#" .. color:ToHex()
end

-- 12,345 (Ui.money without the $).
function Extras.num(amount: number): string
	return string.sub(Ui.money(amount), 2)
end

function Extras.count(set: { [string]: boolean }): number
	local n = 0
	for _, on in set do
		if on then
			n += 1
		end
	end
	return n
end

function Extras.categoryIcon(id: string): string
	for _, category in Extras.CATEGORIES do
		if category.id == id then
			return category.icon
		end
	end
	return "⭐"
end

-- The lost packages (Map.Secrets).
function Extras.secretList(): { SecretEntry }
	local cached = Extras.secretCache
	if cached then
		return cached
	end
	local list: { SecretEntry } = {}
	for _, entry in Map.Secrets do
		table.insert(list, { id = entry.id, place = entry.place, hint = entry.hint })
	end
	Extras.secretCache = list
	return list
end

-- A reward item's name and colour: "Reyes' Carbine", "Volt Neon paint".
function Extras.itemName(reward: RewardItem): string
	if reward.weapon then
		local def = Economy.findWeapon(reward.weapon)
		return if def then def.name else reward.weapon
	elseif reward.paint then
		local def = Economy.findPaint(reward.paint)
		return if def then `{def.name} paint` else reward.paint
	end
	return "?"
end

function Extras.itemColor(reward: RewardItem): Color3
	local rgb: { number }? = nil
	if reward.weapon then
		local def = Economy.findWeapon(reward.weapon)
		rgb = if def then def.color else nil
	elseif reward.paint then
		local def = Economy.findPaint(reward.paint)
		rgb = if def then def.color else nil
	end
	return if rgb then Color3.fromRGB(rgb[1] or 255, rgb[2] or 255, rgb[3] or 255) else C.yellow
end

-- 3.2: what a locked campaign waits for, short: "🔒 Finish Code Red first · LEVEL 5" or "🔒 LEVEL 5".
function Extras.lockLine(campaign: Campaign): string
	local missing = Missions.missing(campaign.id, progress)
	local first = missing[1]
	if first then
		local more = if #missing > 1 then ` +{#missing - 1}` else ""
		return `🔒 Finish {first.name}{more} first · LEVEL {campaign.level}`
	end
	return `🔒 LEVEL {campaign.level}`
end

-- 3.4: the cargo slots this mission needs when my car is too small for it (it lends no vehicle), else nil. Not in
-- somebody else's crew: the leader's car does the mission (the server checks that one).
function Extras.slotsShort(def: MissionDef): number?
	local need = Economy.cargoNeed(def.load, def.items)
	local holds = Extras.capacity
	if def.vehicle or crewOwner ~= nil or need <= 0 or holds == nil or need <= holds then
		return nil
	end
	return need
end

-- 3.4: what START says when the car is too small (the server's words).
function Extras.slotsText(need: number): string
	return `This mission needs a vehicle with {need} slots (your {Extras.carName} holds {Extras.capacity or 0}). {Economy.roomAdvice(Extras.carId, Extras.carStage, need)}`
end

-- 3.2: is a DUO mission short of a crew right now (not in somebody else's crew: the leader decides there)?
function Extras.needsCrew(def: MissionDef): boolean
	return def.duo == true and crewOwner == nil and Extras.crewSize < Config.Missions.Duo.MinCrew
end

-- A campaign's reward as a line: "Reyes' Carbine + title “Quartermaster”" (nil for a campaign without one).
function Extras.rewardLine(campaignId: string): string?
	local reward = Config.Rewards.Campaigns[campaignId]
	if not reward then
		return nil
	end
	return `{Extras.itemName(reward)} + title “{reward.title}”`
end

-- A reward item's picture: the gun's icon (tinted its colour) or a round paint swatch with a shine.
-- mode: "shown" | "dim" (not yours yet) | "silhouette" (a dark shape: you may not even know what it is).
function Extras.itemIcon(parent: Instance, reward: RewardItem, px: number, mode: string, props: { [string]: any }?): GuiObject
	local color = Extras.itemColor(reward)
	local given: { [string]: any } = props or {}
	if reward.weapon then
		local options: { [string]: any } = {
			ImageColor3 = if mode == "silhouette" then Extras.SILHOUETTE else color,
			ImageTransparency = if mode == "dim" then 0.45 else 0,
			TextSize = math.floor(px * 0.62),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTransparency = if mode == "dim" then 0.45 else 0,
		}
		for key, value in given do
			options[key] = value
		end
		return Ui.icon(parent, Icons.weapon(reward.weapon), if mode == "silhouette" then "❔" else "🔫", UDim2.fromOffset(px, px), options)
	end
	local holder = Ui.make("Frame", { Size = UDim2.fromOffset(px, px), BackgroundTransparency = 1 }, parent)
	for key, value in given do
		if string.sub(key, 1, 4) ~= "Text" and string.sub(key, 1, 5) ~= "Image" and key ~= "Font" then
			holder[key] = value
		end
	end
	local paint = if reward.paint then Economy.findPaint(reward.paint) else nil
	local swatch = Ui.make("Frame", {
		Size = UDim2.fromScale(0.86, 0.86),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = if mode == "silhouette" then Extras.SILHOUETTE else color,
		BackgroundTransparency = if mode == "dim" then 0.5 elseif paint and paint.material == "Glass" then 0.15 else 0,
		BorderSizePixel = 0,
	}, holder)
	Ui.corner(swatch)
	-- 3.8: a flat square swatch; a fine rim (a thicker one in its own colour for the neon ones).
	local neon = paint ~= nil and paint.material == "Neon" and mode == "shown"
	local rim = Ui.stroke(swatch, if neon then color else color:Lerp(K.text, 0.3), if neon then 2 else 1)
	rim.Transparency = if mode == "dim" then 0.6 else 0
	return holder
end

-- How you get an exclusive item ("finish Iron Supply", "find every lost package", "???").
function Extras.howToGet(exclusive: string): string
	if exclusive == "secrets" then
		return "find every lost package"
	elseif exclusive == "challenges" then
		return "??? · a secret reward"
	end
	local campaign = Missions.findCampaign(exclusive)
	return `finish {if campaign then campaign.name else exclusive}`
end

-- Is the reward of this exclusive key yours (a campaign id, "secrets" or "challenges")?
function Extras.owned(exclusive: string): boolean
	local S = Extras.state
	if exclusive == "secrets" then
		return S.secretsReward
	elseif exclusive == "challenges" then
		return S.challengesReward
	end
	return S.campaigns[exclusive] == true
end

-- Every exclusive gun and paint (Config.Weapons / Config.Paints with `exclusive`), the guns first.
function Extras.exclusives(): { ExclusiveItem }
	local list: { ExclusiveItem } = {}
	for _, def in Config.Weapons do
		if def.exclusive then
			table.insert(list, { kind = "weapon", id = def.id, name = def.name, exclusive = def.exclusive, reward = { weapon = def.id } })
		end
	end
	for _, def in Config.Paints do
		if def.exclusive then
			table.insert(list, { kind = "paint", id = def.id, name = def.name, exclusive = def.exclusive, reward = { paint = def.id } })
		end
	end
	return list
end

-- Where a title comes from (the REWARDS tab): "Iron Supply", "a challenge: Headhunter", "every lost package" …
function Extras.titleSource(title: string): string
	for campaignId, reward in Config.Rewards.Campaigns do
		if reward.title == title then
			local campaign = Missions.findCampaign(campaignId)
			return `campaign: {if campaign then campaign.name else campaignId}`
		end
	end
	if Config.Rewards.Secrets.title == title then
		return "every lost package"
	elseif Config.Rewards.Challenges.title == title then
		return "every challenge"
	end
	for _, def in Challenges.List do
		if def.title == title then
			return `challenge: {def.name}`
		end
	end
	return ""
end

-- ── The subtitle's notices ─────────────────────────────────────────────────

local noticeStamp = 0
local function say(text: string, color: Color3?)
	local subtitle = refs.subtitle
	if not subtitle then
		return
	end
	noticeStamp += 1
	local mine = noticeStamp
	subtitle.Text = text
	subtitle.TextColor3 = color or P.ink
	task.delay(NOTICE_TIME, function()
		if noticeStamp == mine and refs.subtitle then
			refs.subtitle.Text = SUBTITLE
			refs.subtitle.TextColor3 = P.ink2
		end
	end)
end

-- ── The tooltip (a twist chip's description) ───────────────────────────────

local tipOwner: any = nil

local function hideTip(owner: any?)
	local tip = refs.tip
	if tip and (owner == nil or owner == tipOwner) then
		tip.Visible = false
		tipOwner = nil
	end
end

local function showTip(owner: any, title: string, text: string)
	local tip, window = refs.tip, refs.window
	if not tip or not window then
		return
	end
	tipOwner = owner
	refs.tipTitle.Text = title
	refs.tipText.Text = text
	local s = if refs.scale then refs.scale.Scale else 1
	local at = (owner.AbsolutePosition - window.AbsolutePosition) / s
	local width = window.AbsoluteSize.X / s
	tip.Position = UDim2.fromOffset(math.clamp(at.X, 8, math.max(8, width - 288)), at.Y + owner.AbsoluteSize.Y / s + 6)
	tip.Visible = true
end

-- A twist as a chip: icon and name (or only the icon), its description on hover.
local function twistChip(parent: any, id: string, compact: boolean?, order: number?): any
	local info = T.Twists[id]
	if not info then
		return nil
	end
	local chip = Extras.chip(parent, if compact then info.icon else `{info.icon} {info.name}`, "twist", order)
	chip.MouseEnter:Connect(function()
		showTip(chip, `{info.icon}  {info.name}  ·  +{math.floor((info.pay - 1) * 100 + 0.5)} % pay`, info.description)
	end)
	chip.MouseLeave:Connect(function()
		hideTip(chip)
	end)
	return chip
end

local function coopChip(parent: any, order: number?): any
	local chip = Extras.chip(parent, "👥 CO-OP", "coop", order)
	chip.MouseEnter:Connect(function()
		showTip(chip, "👥  CO-OP", `Made for a crew: every member adds +{math.floor(T.CoopPayPerMember * 100 + 0.5)} % pay and +{math.floor(T.CoopEnemyPerMember * 100 + 0.5)} % enemies. You can still play it alone.`)
	end)
	chip.MouseLeave:Connect(function()
		hideTip(chip)
	end)
	return chip
end

-- 3.2: the 🤝 DUO chip (a card, a campaign row), what it means on hover.
function Extras.duoChip(parent: Instance, order: number?): any
	local chip = Extras.chip(parent, "🤝 DUO", "duo", order)
	local need = Config.Missions.Duo.MinCrew
	chip.MouseEnter:Connect(function()
		showTip(chip, "🤝  DUO", `Only with a crew: {need} {if need == 1 then "partner" else "partners"} with you at START (invite with K). Made for two: pair lifts and twin levers. If your partner leaves, the mission fails.`)
	end)
	chip.MouseLeave:Connect(function()
		hideTip(chip)
	end)
	return chip
end

-- ── Building the window ────────────────────────────────────────────────────

local render: () -> ()
local renderQueued = false

local function queueRender()
	if renderQueued then
		return
	end
	renderQueued = true
	task.delay(0.15, function()
		renderQueued = false
		if refs.window and refs.window.Visible then
			render()
		end
	end)
end

local function updateScale()
	local camera = workspace.CurrentCamera
	local window, scale = refs.window, refs.scale
	if not camera or not window or not scale then
		return
	end
	local size = Ui.screenSize() -- (under the top bar: the ScreenGui does not ignore the inset)
	local s = math.clamp(math.min(size.X / (BASE_W + 40), size.Y / (BASE_H + 40)), 0.55, 1.1)
	scale.Scale = s
	window.Size = UDim2.fromOffset(math.floor(math.min(BASE_W, (size.X - 16) / s)), math.floor(math.min(BASE_H, (size.Y - 16) / s)))
	hideTip()
end

local function scrolling(parent: any, size: UDim2, position: UDim2, gap: number): any
	local frame = Ui.make("ScrollingFrame", {
		Size = size,
		Position = position,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = P.ink2,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, parent)
	Ui.list(frame, true, gap)
	-- Room above and beside the paper for the hover lift and the outline.
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 8) }, frame)
	frame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		hideTip()
	end)
	return frame
end

local function setFilter(id: string)
	if filter == id then
		return
	end
	filter = id
	local current = selectedMission and Missions.find(selectedMission)
	if not current or not visible(current) then
		selectedMission = currentMission(selectedCampaign)
	end
	render()
end

local function build()
	if refs.gui then
		return
	end
	local gui = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryMissions",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 3,
	}, player:WaitForChild("PlayerGui"))
	refs.gui = gui
	local window, content, chrome = Ui.window(gui, "Missions", SUBTITLE, "🎯", UDim2.fromOffset(BASE_W, BASE_H))
	window.Visible = false
	refs.window = window
	refs.chrome = chrome
	refs.scale = window:FindFirstChildOfClass("UIScale") or Ui.make("UIScale", {}, window)
	refs.subtitle = chrome.subtitle
	chrome.onClose = function()
		MissionsUi.close()
	end

	-- ── The page tabs (MISSIONS | CHALLENGES | SECRETS | REWARDS) and the count on the right ──
	do
		local pages = Ui.make("Frame", { Size = UDim2.new(1, -220, 0, 32), Position = UDim2.fromOffset(16, 12), BackgroundTransparency = 1 }, content)
		Ui.list(pages, false, 8)
		refs.pages = {}
		for order, page in Extras.PAGES do
			local id = page.id
			refs.pages[id] = Extras.tabButton(pages, page.text, page.width, order, function()
				Extras.setTab(id)
			end)
		end
	end
	refs.stars = Ui.label(content, `★ 0 / {#Missions.List * 3}`, UDim2.fromOffset(190, 32), {
		Position = UDim2.new(1, -206, 0, 12),
		TextSize = 21,
		Font = Theme.DisplayFont,
		TextColor3 = P.ink,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})

	-- ── The campaigns (left, on a deeper lavender column) and the selected campaign's missions (right) ──
	local column = Ui.make("Frame", { Name = "Column", Size = UDim2.new(0, LEFT_W + 22, 1, -52), Position = UDim2.fromOffset(4, 52), BackgroundColor3 = P.lavenderDeep, BackgroundTransparency = 0.45, BorderSizePixel = 0 }, content)
	Ui.corner(column)
	refs.column = column
	Ui.caps(column, "Stories", UDim2.fromOffset(90, 28), { Position = UDim2.fromOffset(12, 6), TextSize = 12, TextColor3 = P.ink2 })
	local tabs = Ui.make("Frame", { Size = UDim2.fromOffset(160, 28), Position = UDim2.new(1, -10, 0, 6), AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 1 }, column)
	Ui.list(tabs, false, 6, Enum.HorizontalAlignment.Right)
	refs.filterTabs = tabs
	refs.tabs = {}
	for order, tab in { { id = "all", text = "ALL", width = 54 }, { id = "coop", text = "👥 CO-OP", width = 94 } } do
		local id = tab.id
		local button = Extras.tabButton(tabs, tab.text, tab.width, order, function()
			setFilter(id)
		end)
		button.Size = UDim2.fromOffset(tab.width, 28)
		button.TextSize = 12
		refs.tabs[id] = button
	end
	refs.campaigns = scrolling(content, UDim2.new(0, LEFT_W, 1, -(TOP + 10)), UDim2.fromOffset(14, TOP), 8)
	refs.missions = scrolling(content, UDim2.new(1, -(LEFT_W + 44), 1, -(TOP - 26)), UDim2.fromOffset(LEFT_W + 32, TOP - 32), 10)
	-- 3.1: the CHALLENGES / SECRETS / REWARDS pages (one full-width list, rebuilt by render).
	refs.extra = scrolling(content, UDim2.new(1, -28, 1, -(TOP - 26)), UDim2.fromOffset(14, TOP - 32), 8)
	refs.extra.Visible = false

	-- ── The tooltip (over everything in the window): a paper slip ──
	local tip = Ui.make("Frame", {
		Name = "Tooltip",
		Size = UDim2.fromOffset(280, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = P.paper,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 50,
	}, window)
	Ui.corner(tip)
	Ui.stroke(tip, P.ink2, 1).Transparency = 0
	Ui.padding(tip, 10)
	Ui.list(tip, true, 4)
	refs.tip = tip
	refs.tipTitle = Ui.label(tip, "", UDim2.new(1, 0, 0, 18), { TextSize = 14, Font = Theme.DisplayFont, TextColor3 = P.ink, LayoutOrder = 1, ZIndex = 51 })
	refs.tipText = Ui.label(tip, "", UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 14,
		Font = Theme.Font,
		TextColor3 = P.ink2,
		LayoutOrder = 2,
		ZIndex = 51,
	})

	updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
end

-- ── The campaign list ──────────────────────────────────────────────────────

local function selectCampaign(id: string)
	if selectedCampaign == id then
		return
	end
	selectedCampaign = id
	selectedMission = currentMission(id)
	blindPick = false
	render()
	if refs.missions then
		refs.missions.CanvasPosition = Vector2.zero
	end
end

local function campaignRow(campaign: Campaign, order: number)
	local color = colorOf(campaign)
	local locked = campaignLocked(campaign)
	local selected = campaign.id == selectedCampaign
	local done, total = Missions.done(progress, campaign.id)
	local got, most = Missions.stars(progress, campaign.id)
	local id = campaign.id
	-- 3.6: a paper ticket, the campaign's colour on its spine; the selected one is the cream paper with a violet
	-- outline, a locked one hatched.
	local row = Ui.make("TextButton", {
		Size = UDim2.new(1, -2, 0, 70),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
	}, refs.campaigns)
	Extras.paper(row, if selected then P.paper elseif locked then P.lavender else P.ticket, P.line, 1)
	if locked then
		Extras.hatch(row)
	end
	if selected then
		Ui.selectRow(row, true) -- the quiet highlight and the narrow red rule
	end
	Ui.tactile(row)
	row.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		selectCampaign(id)
	end)
	local stripe = Ui.make("Frame", { Size = UDim2.new(0, 5, 1, -16), Position = UDim2.fromOffset(6, 8), BackgroundColor3 = if locked then P.line else color, BorderSizePixel = 0 }, row)
	Ui.corner(stripe)
	Ui.label(row, campaign.icon, UDim2.fromOffset(34, 34), {
		Position = UDim2.fromOffset(16, 17),
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = if locked then 0.5 else 0,
	})
	if campaign.duo then
		local badge = Extras.duoChip(row)
		badge.Size = UDim2.fromOffset(0, 18)
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, -8, 0, 7)
	end
	Ui.label(row, campaign.name, UDim2.new(1, if campaign.duo then -130 else -66, 0, 20), {
		Position = UDim2.fromOffset(56, 6),
		TextSize = 16,
		Font = Theme.DisplayFont,
		TextColor3 = if locked then P.ink2 else P.ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.label(row, campaign.client, UDim2.new(1, -66, 0, 16), {
		Position = UDim2.fromOffset(56, 26),
		TextSize = 12,
		Font = Theme.Font,
		TextColor3 = P.ink2,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local line = if locked then Extras.lockLine(campaign)
		elseif done >= total and total > 0 then `🏆 DONE · ★ {got}/{most}`
		else `{done}/{total} done · ★ {got}/{most}`
	if filter == "coop" then
		local coop = 0
		for _, def in Missions.ofCampaign(campaign.id) do
			if def.coop then
				coop += 1
			end
		end
		line ..= `  ·  👥 {coop}`
	end
	Ui.label(row, line, UDim2.new(1, -66, 0, 16), {
		Position = UDim2.fromOffset(56, 43),
		TextSize = 12,
		Font = Theme.HeadingFont,
		TextColor3 = if locked then P.danger elseif done >= total then C.yellow else P.ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local back, fill = Ui.bar(row, UDim2.new(1, -66, 0, 4), color)
	back.Position = UDim2.new(0, 56, 1, -9)
	fill.Size = UDim2.fromScale(if total > 0 then done / total else 0, 1)
end

-- ── The selected campaign ──────────────────────────────────────────────────

local function campaignHeader(campaign: Campaign, order: number)
	local color = colorOf(campaign)
	local done, total = Missions.done(progress, campaign.id)
	local got, most = Missions.stars(progress, campaign.id)
	-- 3.6: a paper note, the campaign's colour as its edge.
	local frame = Ui.make("Frame", {
		Size = UDim2.new(1, -2, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, refs.missions)
	Extras.paper(frame, P.paper, P.line, 1, 12)
	Ui.edge(frame, color)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12) }, frame)
	Ui.list(frame, true, 4)
	local title = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 1 }, frame)
	Ui.label(title, `{campaign.icon}  {campaign.name}`, UDim2.new(1, -150, 1, 0), {
		TextSize = 22,
		Font = Theme.DisplayFont,
		TextColor3 = P.ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.label(title, `★ {got}/{most}`, UDim2.fromOffset(140, 30), {
		Position = UDim2.new(1, -140, 0, 0),
		TextSize = 20,
		Font = Theme.DisplayFont,
		TextColor3 = C.yellow,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	Ui.caps(frame, campaign.client, UDim2.new(1, 0, 0, 16), { TextSize = 12, TextColor3 = P.ink2, LayoutOrder = 2 })
	Ui.label(frame, campaign.pitch, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 14,
		Font = Theme.Font,
		TextColor3 = P.ink,
		LayoutOrder = 3,
	})
	local locked = campaignLocked(campaign)
	local finished = done >= total and total > 0
	local missing = Missions.missing(campaign.id, progress)
	local waitsFor = if #missing > 0 then `{Missions.missingText(missing)}  ·  ` else ""
	local status = if locked then `🔒 {waitsFor}Opens at driver level {campaign.level} (you are level {myLevel()}).`
		elseif finished then `🏆 Campaign complete! The {Ui.money(campaign.reward)} campaign reward is yours.`
		else `{done}/{total} done  ·  finish all ten for {Ui.money(campaign.reward)}  ·  every new star pays {Ui.money(T.StarBonus)}`
	Ui.label(frame, status, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 14,
		Font = Theme.HeadingFont,
		TextColor3 = if locked then P.danger elseif finished then C.yellow else C.money,
		LayoutOrder = 4,
	})
	-- 3.2: the DUO campaign: only with a crew.
	if campaign.duo then
		local need = Config.Missions.Duo.MinCrew
		Ui.label(frame, `🤝 DUO: every mission needs a crew: {need} {if need == 1 then "partner" else "partners"} with you at START. Invite a friend with K.`, UDim2.new(1, 0, 0, 0), {
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = 14,
			Font = Theme.HeadingFont,
			TextColor3 = Extras.DUO_COLOR,
			LayoutOrder = 5,
		})
	end
	-- 3.1: the campaign's own reward (an exclusive gun or paint and a title).
	local rewardLine = Extras.rewardLine(campaign.id)
	if rewardLine then
		local earned = Extras.state.campaigns[campaign.id] == true
		Ui.label(frame, if earned then `🎁 Reward: {rewardLine}  ·  ✓ yours` else `🎁 Reward: {rewardLine}`, UDim2.new(1, 0, 0, 0), {
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = 14,
			Font = Theme.HeadingFont,
			TextColor3 = if earned then C.green else Extras.GOLD,
			LayoutOrder = 6,
		})
	end
	local back, fill = Ui.bar(frame, UDim2.new(1, 0, 0, 6), color)
	back.LayoutOrder = 7
	fill.Size = UDim2.fromScale(if total > 0 then done / total else 0, 1)
end

-- The line under a card's title: the cargo, the vehicle, the clock, the first-clear reward (the tier is in the label
-- above the title, the pay in the stub).
local function cardInfo(def: MissionDef): string
	local parts = {
		`{cargoEmoji(def)} {def.items} {pieceName(def)}`,
	}
	local vehicle = vehicleName(def.vehicle)
	if vehicle then
		table.insert(parts, `🚚 {vehicle}`)
	end
	if def.timeLimit then
		table.insert(parts, `⏱ {Ui.clock(def.timeLimit)}`)
	end
	if best(def.id) == 0 then
		table.insert(parts, `🏁 +{Ui.money(def.reward)}`)
	end
	return table.concat(parts, "  ·  ")
end

local function selectMission(id: string)
	selectedMission = if selectedMission == id then nil else id
	render()
end

-- 3.6: a mission as a paper ticket (dispatch.png's job ticket): the campaign's colour on the left edge, a numbered
-- spine and a perforation, the tier and the name, the twist chips, the cargo line; on the right a perforated stub with
-- the pay and the status. Hover lifts it; a locked one is hatched.
local STUB_W = 116
local SPINE_W = 66
local function missionCard(def: MissionDef, campaign: Campaign, order: number)
	local color = colorOf(campaign)
	local status = statusOf(def)
	local locked = status == "locked"
	local selected = selectedMission == def.id
	local stars = best(def.id)
	local id = def.id
	local card = Ui.make("TextButton", {
		Size = UDim2.new(1, -4, 0, 98),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
	}, refs.missions)
	Extras.paper(card, if locked then P.lavender elseif selected then P.paper else P.ticket, if status == "active" then K.secondary else P.line, 1)
	if locked then
		Extras.hatch(card)
	end
	if selected and not locked then
		Ui.selectRow(card, true) -- the quiet highlight and the narrow red rule
	end
	card.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		selectMission(id)
	end)
	Ui.tactile(card, 3, 1.012)
	local edge = Ui.make("Frame", { Size = UDim2.new(0, 4, 1, -18), Position = UDim2.fromOffset(6, 9), BackgroundColor3 = if locked then P.line else color, BorderSizePixel = 0 }, card)
	Ui.corner(edge)
	-- The spine: the number badge (filled when done, outlined when open, quiet when locked), a perforation after it.
	local badge = Ui.make("Frame", {
		Size = UDim2.fromOffset(42, 42),
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = if stars > 0 then color elseif locked then P.lavenderDeep else P.paper,
		BorderSizePixel = 0,
	}, card)
	Ui.corner(badge)
	Ui.stroke(badge, if locked then P.line else color, 2).Transparency = 0
	Ui.label(badge, if locked then "🔒" else tostring(def.number), UDim2.fromScale(1, 1), {
		TextSize = if locked then 17 else 20,
		Font = Theme.DisplayFont,
		TextColor3 = if stars > 0 then Theme.textOn(color) else P.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Ui.dashes(card, true, 8, P.line, UDim2.new(0, 1, 1, -16), UDim2.fromOffset(SPINE_W, 8))
	-- The body: the label (the tier, the finale), the name, the chips, the cargo line.
	local x = SPINE_W + 12
	local bodyW = -(x + STUB_W + 10)
	Ui.caps(card, `MISSION {def.number}{if def.number == 10 then " · FINALE" else ""}  ·  {string.rep("★", def.tier)}{string.rep("☆", math.max(0, 4 - def.tier))}`, UDim2.new(1, bodyW, 0, 16), {
		Position = UDim2.fromOffset(x, 9),
		TextSize = 12,
		TextColor3 = P.ink2,
	})
	Ui.label(card, def.name, UDim2.new(1, bodyW, 0, 22), {
		Position = UDim2.fromOffset(x, 25),
		TextSize = 17,
		Font = Theme.DisplayFont,
		TextColor3 = if locked then P.ink2 else P.ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	-- The chips: the twists, the CO-OP / DUO badge, the slots your car lacks.
	local chips = Ui.make("Frame", { Size = UDim2.new(1, bodyW, 0, 20), Position = UDim2.fromOffset(x, 51), BackgroundTransparency = 1, ClipsDescendants = true }, card)
	Ui.list(chips, false, 6)
	local count = 0
	for index, twist in twistsOf(def) do
		if twistChip(chips, twist, false, index) then
			count += 1
		end
	end
	if def.duo then
		Extras.duoChip(chips, 10)
		count += 1
	elseif def.coop then
		coopChip(chips, 10)
		count += 1
	end
	-- 3.4: your car is too small for it: the slots it needs.
	local short = Extras.slotsShort(def)
	if short then
		Extras.chip(chips, `📦 needs {short} slots`, "warn", 11)
		count += 1
	end
	if count == 0 then
		Ui.label(chips, "a plain delivery", UDim2.new(1, 0, 1, 0), { TextSize = 12, Font = Theme.Font, TextColor3 = P.ink2 })
	end
	Ui.label(card, cardInfo(def), UDim2.new(1, bodyW, 0, 18), {
		Position = UDim2.fromOffset(x, 75),
		TextSize = 14,
		Font = Theme.Font,
		TextColor3 = P.ink2,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	-- The payout column behind a fine line: the pay, the status.
	Ui.dashes(card, true, 8, P.line, UDim2.new(0, 1, 1, -16), UDim2.new(1, -STUB_W, 0, 8))
	Ui.label(card, `≈ {Ui.money(payHint(def))}`, UDim2.new(0, STUB_W - 12, 0, 26), {
		Position = UDim2.new(1, -STUB_W + 6, 0, 16),
		TextSize = 19,
		Font = Theme.DisplayFont,
		TextColor3 = if locked then P.ink2 else P.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
	})
	local statusText, statusKind = "OPEN", "good"
	if status == "done" then
		statusText, statusKind = Ui.stars(stars), "twist"
	elseif status == "locked" then
		-- 3.2: a mission above your level says which (a campaign still shut says it on its row and header).
		local needLevel = def.level or 0
		local campaignShut = campaignLocked(campaign)
		statusText, statusKind = if needLevel > myLevel() and not campaignShut then `🔒 LEVEL {needLevel}` else "🔒 LOCKED", "quiet"
	elseif status == "active" then
		statusText, statusKind = "▶ PLAYING", "coop"
	end
	local stub = Ui.make("Frame", { Size = UDim2.new(0, STUB_W - 12, 0, 24), Position = UDim2.new(1, -STUB_W + 6, 0, 52), BackgroundTransparency = 1 }, card)
	Ui.list(stub, false, 0, Enum.HorizontalAlignment.Center)
	local chip = Extras.chip(stub, statusText, statusKind)
	chip.TextSize = if status == "done" then 15 else 12
end

-- ── The selected mission (under its card) ──────────────────────────────────

local function detailLine(parent: any, text: string, color: Color3?, order: number, size: number?): any
	return Ui.label(parent, text, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = size or 14,
		Font = Theme.Font,
		TextColor3 = color or P.ink,
		RichText = true,
		LayoutOrder = order,
	})
end

-- The client's briefing as a note in the card (3.8: a flat dark note with a red rule on its left, no tape): the
-- client's icon in a square badge, the words and their name under them like a signature.
local function briefingNote(parent: any, def: MissionDef, campaign: Campaign, order: number)
	local color = colorOf(campaign)
	local holder = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order }, parent)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 4) }, holder)
	local note = Ui.make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = P.tags[2],
		BorderSizePixel = 0,
	}, holder)
	Ui.corner(note)
	Ui.stroke(note, P.line, 1).Transparency = 0
	-- The red rule (the contract accent) and the client's badge (in the left margin).
	Ui.make("Frame", { Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = K.red, BorderSizePixel = 0 }, note)
	local avatar = Ui.make("Frame", { Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(14, 14), BackgroundColor3 = P.paper, BorderSizePixel = 0 }, note)
	Ui.corner(avatar)
	Ui.stroke(avatar, color, 2).Transparency = 0
	Ui.label(avatar, campaign.icon, UDim2.fromScale(1, 1), { TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center })
	-- The words and the signature (the note grows with them).
	local words = Ui.make("Frame", { Size = UDim2.new(1, -88, 0, 0), Position = UDim2.fromOffset(72, 14), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, note)
	Ui.list(words, true, 6)
	Ui.make("UIPadding", { PaddingBottom = UDim.new(0, 12) }, words)
	Ui.label(words, `“{def.briefing}”`, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 15,
		Font = Theme.Font,
		TextColor3 = P.ink,
		LayoutOrder = 1,
	})
	Ui.label(words, `— {campaign.client}`, UDim2.new(1, 0, 0, 18), {
		TextSize = 14,
		Font = Theme.HeadingFont,
		TextColor3 = P.ink2,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
	})
end

-- Where the mission goes: "Pick up at the Old Farm → the Harbor Docks (2 drops)".
local function routeText(def: MissionDef): string
	local from = if def.pickups == 0 then "Starts loaded"
		elseif def.pickupAt then `Pick up at <b>{esc(placeName(def.pickupAt) or "")}</b>`
		else "Pick up near you"
	local to = if def.dropAt then `<b>{esc(placeName(def.dropAt) or "")}</b>` else "an address in town"
	local stops = {}
	if def.pickups > 1 then
		table.insert(stops, `{def.pickups} pick-ups`)
	end
	if def.drops > 1 then
		table.insert(stops, `{def.drops} drops`)
	end
	local extra = if #stops > 0 then `  ({table.concat(stops, ", ")})` else ""
	return `📍 {from}  →  {to}{extra}`
end

-- START (or why not), FIND CREW on a co-op mission.
local function actionRow(parent: any, def: MissionDef, order: number)
	local status, why = statusOf(def)
	local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	Ui.list(row, false, 10)
	local id = def.id
	local member = crewOwner ~= nil
	local note: string? = nil
	if member then
		note = `👥 Your crew leader picks the mission ({crewOwner}). Leave the crew (K) to play your own.`
	else
		local enabled = status ~= "locked" and status ~= "active" and not ownJob
		local text = if status == "done" then "PLAY AGAIN  →" elseif status == "active" then "▶ PLAYING" else "START  →"
		local start = Ui.button(row, text, UDim2.fromOffset(170, 44), P.sage, function()
			MissionsUi.startMission(id)
		end)
		start.TextSize = 16
		start.LayoutOrder = 1
		paintButton(start, text, P.sage, enabled)
		if enabled then
			Ui.tactile(start, 3, 1.03)
		end
		if status == "locked" then
			note = `🔒 {why or "Locked."}`
		elseif status == "active" then
			note = "You are on this mission right now."
		elseif ownJob then
			note = "Finish your current delivery first."
		elseif Extras.needsCrew(def) then
			note = `🤝 {Extras.DUO_REFUSAL}`
		elseif Extras.slotsShort(def) then
			note = `📦 needs {Extras.slotsShort(def)} slots: your {Extras.carName} holds {Extras.capacity or 0}.`
		elseif table.find(twistsOf(def), "night") and workspace:GetAttribute("Night") == false then
			note = "🌙 Night only: come back after dark."
		end
	end
	if def.coop and not member then
		local find = Ui.button(row, "🔎 FIND CREW", UDim2.fromOffset(150, 44), if Extras.needsCrew(def) then Extras.DUO_COLOR else P.violet, function()
			MissionsUi.findCrew(id)
		end)
		find.TextSize = 15
		find.LayoutOrder = 2
	end
	if note then
		Ui.label(row, note, UDim2.new(1, if member then 0 elseif def.coop then -340 else -180, 1, 0), {
			LayoutOrder = 3,
			TextSize = 14,
			Font = Theme.HeadingFont,
			TextColor3 = if member then P.violet else P.ink,
		})
	end
end

-- 3.6: the open card's back: a quiet lavender sheet under the ticket with the note, the facts and START.
local function missionDetail(def: MissionDef, campaign: Campaign, order: number)
	local color = colorOf(campaign)
	local frame = Ui.make("Frame", {
		Size = UDim2.new(1, -4, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, refs.missions)
	Extras.paper(frame, P.lavender:Lerp(P.paper, 0.5), color, 1.5, 10)
	Ui.padding(frame, 14)
	Ui.list(frame, true, 8)
	briefingNote(frame, def, campaign, 1)
	detailLine(frame, esc(def.description), P.ink2, 2)
	detailLine(frame, routeText(def), P.ink, 3)
	-- The people, the clock, the bandits.
	local facts = { `🙋 {esc(def.giver)}  →  {esc(def.receiver)}` }
	table.insert(facts, if def.timeLimit then `⏱ RUSH: {Ui.clock(def.timeLimit)} on the clock` else "⏱ the clock goes by the distance")
	if def.banditBoost and def.banditBoost > 1 then
		table.insert(facts, `🏴 bandits want it: ×{def.banditBoost}`)
	end
	local vehicle = vehicleName(def.vehicle)
	local slotsNeed = Economy.cargoNeed(def.load, def.items)
	table.insert(facts, if vehicle then `🚚 lent: {esc(vehicle)}` elseif slotsNeed > 0 then `🚗 your own car · 📦 {slotsNeed} slots` else "🚗 your own car")
	detailLine(frame, table.concat(facts, "   ·   "), P.ink2, 4)
	-- 3.4: too much cargo for the car you have.
	local short = Extras.slotsShort(def)
	if short then
		detailLine(frame, `<b>📦 needs {short} slots</b>  {esc(Extras.slotsText(short))}`, P.danger, 19)
	end
	-- The twists, explained (touch players have no hover).
	local line = 5
	local good = Extras.hex(C.money)
	for _, twist in twistsOf(def) do
		local info = T.Twists[twist]
		if info then
			detailLine(frame, `<b>{info.icon} {info.name}</b>  {esc(info.description)}  <font color="{good}">+{math.floor((info.pay - 1) * 100 + 0.5)} %</font>`, P.ink, line)
			line += 1
		end
	end
	if def.duo then
		local need = Config.Missions.Duo.MinCrew
		detailLine(frame, `<b>🤝 DUO</b>  Only with a crew: {need} {if need == 1 then "partner" else "partners"} with you at START. +{math.floor(T.CoopPayPerMember * 100 + 0.5)} % pay and +{math.floor(T.CoopEnemyPerMember * 100 + 0.5)} % enemies for every crew member. If your partner leaves, the mission fails.`, Extras.DUO_COLOR, line)
		line += 1
	elseif def.coop then
		detailLine(frame, `<b>👥 CO-OP</b>  +{math.floor(T.CoopPayPerMember * 100 + 0.5)} % pay and +{math.floor(T.CoopEnemyPerMember * 100 + 0.5)} % enemies for every crew member. Playable alone; your crew earns the stars too.`, P.violet, line)
		line += 1
	end
	-- The rewards.
	local stars = best(def.id)
	local rewards = if stars > 0
		then `Best: <font color="{Extras.hex(C.yellow)}">{Ui.stars(stars)}</font>  ·  {if stars < 3 then `every new star pays {Ui.money(T.StarBonus)}` else "all stars collected"}`
		else `First clear: <font color="{good}"><b>{Ui.money(def.reward)}</b></font> + {Ui.money(T.StarBonus)} a star  ·  about {Ui.money(payHint(def))} pay  ·  ★★ cargo ≥ {math.floor(T.TwoStarCondition * 100)} %, ★★★ and {math.floor(T.ThreeStarTime * 100)} % of the clock left`
	detailLine(frame, rewards, P.ink, 20)
	actionRow(frame, def, 21)
end

-- ── 3.1: the CHALLENGES / SECRETS / REWARDS pages ──────────────────────────

-- A section's heading: the name on the left, a count on the right.
function Extras.section(parent: Instance, text: string, right: string, order: number)
	local frame = Ui.make("Frame", { Size = UDim2.new(1, -2, 0, 30), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	Ui.label(frame, text, UDim2.new(1, -160, 1, 0), {
		Position = UDim2.fromOffset(2, 4),
		TextSize = 17,
		Font = Theme.DisplayFont,
		TextColor3 = P.ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.label(frame, right, UDim2.fromOffset(156, 26), {
		Position = UDim2.new(1, -158, 0, 4),
		TextSize = 14,
		Font = Theme.HeadingFont,
		TextColor3 = P.ink2,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
end

-- A plain line of text in a page.
function Extras.note(parent: Instance, text: string, order: number, color: Color3?)
	Ui.label(parent, text, UDim2.new(1, -2, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 14,
		Font = Theme.Font,
		TextColor3 = color or P.ink2,
		RichText = true,
		LayoutOrder = order,
	})
end

-- The big card of a final reward (Dead End, the Phantom paint): its picture in a glow on the left, the ribbon, the
-- name, a few lines and a progress bar (share 0 … 1) on the right.
function Extras.finalCard(parent: Instance, order: number, info: {
	reward: RewardItem,
	color: Color3,
	earned: boolean,
	mystery: boolean, -- a dark silhouette and ??? until earned
	ribbon: string,
	name: string,
	body: string,
	share: number,
})
	local color = info.color
	local frame = Ui.make("Frame", {
		Size = UDim2.new(1, -2, 0, 140),
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	Extras.paper(frame, P.paper:Lerp(color, if info.earned then 0.1 else 0.04), if info.earned then color else color:Lerp(P.paper, 0.5), 2, 12)
	-- The picture on a dark square with a fine frame in its colour (3.8: no glow).
	local art = Ui.make("Frame", { Size = UDim2.fromOffset(112, 112), Position = UDim2.fromOffset(12, 12), BackgroundColor3 = K.charcoal, BorderSizePixel = 0 }, frame)
	Ui.stroke(art, if info.earned then color else P.line, 1).Transparency = 0
	local hidden = info.mystery and not info.earned
	Extras.itemIcon(art, info.reward, 84, if hidden then "silhouette" elseif info.earned then "shown" else "dim", {
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
	})
	if hidden then
		Ui.label(art, "???", UDim2.fromScale(1, 1), {
			TextSize = 30,
			Font = Theme.DisplayFont,
			TextColor3 = K.text,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
	end
	Ui.caps(frame, info.ribbon, UDim2.new(1, -150, 0, 16), {
		Position = UDim2.fromOffset(138, 12),
		TextSize = 12,
		TextColor3 = P.violet,
	})
	Ui.label(frame, info.name, UDim2.new(1, -150, 0, 30), {
		Position = UDim2.fromOffset(138, 28),
		TextSize = 26,
		Font = Theme.DisplayFont,
		TextColor3 = if info.earned then P.ink else P.ink2,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.label(frame, info.body, UDim2.new(1, -150, 0, 44), {
		Position = UDim2.fromOffset(138, 60),
		TextSize = 14,
		Font = Theme.Font,
		TextColor3 = P.ink2,
		RichText = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local back, fill = Ui.bar(frame, UDim2.new(1, -152, 0, 8), if info.earned then C.green else color)
	back.Position = UDim2.fromOffset(138, 116)
	fill.Size = UDim2.fromScale(math.clamp(info.share, 0, 1), 1)
end

-- One challenge: the badge (✓ when done), the name, the description, the progress, the money and the title.
function Extras.challengeRow(parent: Instance, def: Challenges.ChallengeDef, order: number)
	local S = Extras.state
	local isDone = S.done[def.id] == true
	local secret = def.hidden == true and not isDone
	local value = S.values[def.stat] or 0
	if isDone then
		value = math.max(value, def.goal)
	end
	local row = Ui.make("Frame", {
		Size = UDim2.new(1, -2, 0, 68),
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	Extras.paper(row, if isDone then P.tags[3] elseif secret then P.lavender else P.ticket, P.line)
	if secret then
		Extras.hatch(row)
	end
	local badge = Ui.make("Frame", {
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromOffset(12, 14),
		BackgroundColor3 = if isDone then P.sage else P.paper,
		BorderSizePixel = 0,
	}, row)
	Ui.corner(badge)
	Ui.stroke(badge, if isDone then C.green else P.line, 2).Transparency = 0
	Ui.label(badge, if isDone then "✓" elseif secret then "?" else Extras.categoryIcon(def.category), UDim2.fromScale(1, 1), {
		TextSize = if isDone then 22 else 18,
		Font = Theme.DisplayFont,
		TextColor3 = if isDone then P.ink else P.ink2,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Ui.label(row, if secret then "???" else def.name, UDim2.new(1, -236, 0, 20), {
		Position = UDim2.fromOffset(64, 7),
		TextSize = 16,
		Font = Theme.DisplayFont,
		TextColor3 = if secret then P.ink2 else P.ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.label(row, if secret then "A secret challenge: it shows itself when you do it." else def.description, UDim2.new(1, -236, 0, 18), {
		Position = UDim2.fromOffset(64, 27),
		TextSize = 14,
		Font = Theme.Font,
		TextColor3 = P.ink2,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if not secret then
		local back, fill = Ui.bar(row, UDim2.new(1, -336, 0, 6), if isDone then C.green else P.violet)
		back.Position = UDim2.fromOffset(64, 52)
		fill.Size = UDim2.fromScale(math.clamp(value / math.max(def.goal, 1), 0, 1), 1)
		Ui.label(row, `{Extras.num(math.min(value, def.goal))} / {Extras.num(def.goal)}`, UDim2.fromOffset(98, 16), {
			Position = UDim2.new(1, -268, 0, 47),
			TextSize = 12,
			Font = Theme.HeadingFont,
			TextColor3 = if isDone then C.green else P.ink,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextWrapped = false,
		})
	end
	-- The reward, on the right.
	Ui.label(row, if isDone then `✓ +{Ui.money(def.money)}` elseif secret then "+$???" else `+{Ui.money(def.money)}`, UDim2.fromOffset(156, 22), {
		Position = UDim2.new(1, -166, 0, 9),
		TextSize = 17,
		Font = Theme.DisplayFont,
		TextColor3 = if isDone then C.green else C.money,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
	if def.title and not secret then
		Ui.label(row, `🎖 “{def.title}”`, UDim2.fromOffset(156, 18), {
			Position = UDim2.new(1, -166, 0, 34),
			TextSize = 12,
			Font = Theme.HeadingFont,
			TextColor3 = Extras.GOLD,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
end

function Extras.challengesPage(parent: Instance)
	local S = Extras.state
	local list = Challenges.List
	local done = 0
	for _, def in list do
		if S.done[def.id] then
			done += 1
		end
	end
	local final = Config.Rewards.Challenges
	local earned = S.challengesReward
	local weapon = Economy.findWeapon(final.weapon)
	Extras.finalCard(parent, 1, {
		reward = { weapon = final.weapon },
		color = Extras.PURPLE,
		earned = earned,
		mystery = true,
		ribbon = if earned then "☠  THE LAST REWARD · YOURS" else "☠  THE LAST REWARD",
		name = if earned and weapon then string.upper(weapon.name) else "???",
		body = if earned
			then `{if weapon then esc(weapon.description) else ""}\n<font color="{Extras.hex(Extras.GOLD)}">Title “{final.title}”</font>  ·  {Ui.money(final.money)}`
			else `Complete every challenge ({done}/{#list}).\nA gun nobody else has, a title and {Ui.money(final.money)}.`,
		share = if #list > 0 then done / #list else 0,
	})
	-- The challenges by category (the known ones in order, then any other).
	local categories = table.clone(Extras.CATEGORIES)
	for _, def in list do
		local known = false
		for _, category in categories do
			if category.id == def.category then
				known = true
				break
			end
		end
		if not known then
			table.insert(categories, { id = def.category, name = string.upper(def.category), icon = "⭐" })
		end
	end
	local order = 10
	for _, category in categories do
		local defs: { Challenges.ChallengeDef } = {}
		local got = 0
		for _, def in list do
			if def.category == category.id then
				table.insert(defs, def)
				if S.done[def.id] then
					got += 1
				end
			end
		end
		if #defs > 0 then
			order += 1
			Extras.section(parent, `{category.icon}  {category.name}`, `{got} / {#defs} done`, order)
			for _, def in defs do
				order += 1
				Extras.challengeRow(parent, def, order)
			end
		end
	end
	if not Extras.hasState then
		Extras.note(parent, "Loading your progress…", 2)
	end
end

-- One lost package: ✓ when found, else its hint (or "Visit <place> first" before you have been there).
function Extras.secretRow(parent: Instance, entry: SecretEntry, label: string, order: number)
	local S = Extras.state
	local found = S.secrets[entry.id] == true
	local isPlace = false
	for _, place in Map.Places do
		if place.id == entry.place then
			isPlace = true
			break
		end
	end
	local visited = not isPlace or S.visited[entry.place] == true
	local row = Ui.make("Frame", {
		Size = UDim2.new(1, -2, 0, 50),
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	Extras.paper(row, if found then P.tags[3] elseif visited then P.ticket else P.lavender, P.line)
	if not (visited or found) then
		Extras.hatch(row)
	end
	Ui.label(row, if found then "✓" elseif visited then "📦" else "🔒", UDim2.fromOffset(36, 50), {
		Position = UDim2.fromOffset(8, 0),
		TextSize = if found then 22 else 18,
		Font = Theme.DisplayFont,
		TextColor3 = if found then C.green else P.ink2,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Ui.label(row, label, UDim2.new(1, -170, 0, 20), {
		Position = UDim2.fromOffset(50, 5),
		TextSize = 15,
		Font = Theme.DisplayFont,
		TextColor3 = if visited or found then P.ink else P.ink2,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local line = if found then "Found."
		elseif visited then `“{entry.hint}”`
		else `Visit {placeName(entry.place) or entry.place} first.`
	Ui.label(row, line, UDim2.new(1, -170, 0, 18), {
		Position = UDim2.fromOffset(50, 26),
		TextSize = 14,
		Font = Theme.Font,
		TextColor3 = if found then C.green elseif visited then P.ink else P.ink2,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.label(row, if found then `✓ +{Ui.money(Config.Rewards.SecretMoney)}` else `+{Ui.money(Config.Rewards.SecretMoney)}`, UDim2.fromOffset(110, 50), {
		Position = UDim2.new(1, -120, 0, 0),
		TextSize = 15,
		Font = Theme.DisplayFont,
		TextColor3 = if found then C.green else C.money,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
end

function Extras.secretsPage(parent: Instance)
	local S = Extras.state
	local R = Config.Rewards
	local list = Extras.secretList()
	local total = math.max(S.secretsTotal, #list)
	local found = Extras.count(S.secrets)
	local earnedMoney = found * R.SecretMoney + (if S.secretsReward then R.Secrets.money else 0)
	-- The count, and what they paid.
	local head = Ui.make("Frame", {
		Size = UDim2.new(1, -2, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		LayoutOrder = 1,
	}, parent)
	Extras.paper(head, P.paper, P.line, 1, 12)
	Ui.padding(head, 14)
	Ui.list(head, true, 4)
	Ui.label(head, `📦  Lost packages  ·  {found} / {total} found`, UDim2.new(1, 0, 0, 26), {
		TextSize = 21,
		Font = Theme.DisplayFont,
		TextColor3 = P.ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 1,
	})
	Ui.label(head, `Couriers lost packages all over the map: one at every place. Look behind buildings, on roofs and under stairs for a faint glow and a “?”. Each one pays {Ui.money(R.SecretMoney)}.`, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 14,
		Font = Theme.Font,
		TextColor3 = P.ink2,
		LayoutOrder = 2,
	})
	Ui.label(head, `Earned so far: {Ui.money(earnedMoney)}`, UDim2.new(1, 0, 0, 18), {
		TextSize = 14,
		Font = Theme.HeadingFont,
		TextColor3 = C.money,
		LayoutOrder = 3,
	})
	local back, fill = Ui.bar(head, UDim2.new(1, 0, 0, 6), P.violet)
	back.LayoutOrder = 4
	fill.Size = UDim2.fromScale(if total > 0 then found / total else 0, 1)
	-- The reward for all of them.
	local paint = Economy.findPaint(R.Secrets.paint)
	Extras.finalCard(parent, 2, {
		reward = { paint = R.Secrets.paint },
		color = Extras.itemColor({ paint = R.Secrets.paint }):Lerp(Extras.PURPLE, 0.45),
		earned = S.secretsReward,
		mystery = false,
		ribbon = if S.secretsReward then "📦  EVERY LOST PACKAGE · YOURS" else "📦  FIND EVERY LOST PACKAGE",
		name = string.upper(if paint then `{paint.name} paint` else "Phantom paint"),
		body = `An exclusive paint nobody can buy, <font color="{Extras.hex(Extras.GOLD)}">the title “{R.Secrets.title}”</font> and {Ui.money(R.Secrets.money)}.\n{if S.secretsReward then "✓ Yours: paint a car at Wrench Garage." else `Find every lost package ({found}/{total}).`}`,
		share = if total > 0 then found / total else 0,
	})
	-- Every package, by place (Map.Places order; the extras after their place).
	Extras.section(parent, "🗺  WHERE THEY ARE", `{Extras.count(S.visited)} / {S.placesTotal} places visited`, 3)
	if #list == 0 then
		Extras.note(parent, "The lost packages are not out yet. Come back after the next update.", 4)
		return
	end
	local rank: { [string]: number } = {}
	for index, place in Map.Places do
		rank[place.id] = index
	end
	local sorted = table.clone(list)
	local position: { [string]: number } = {}
	for index, entry in list do
		position[entry.id] = index
	end
	table.sort(sorted, function(a, b)
		local ra, rb = rank[a.place] or 999, rank[b.place] or 999
		if ra ~= rb then
			return ra < rb
		end
		return position[a.id] < position[b.id]
	end)
	local perPlace: { [string]: number } = {}
	for _, entry in sorted do
		perPlace[entry.place] = (perPlace[entry.place] or 0) + 1
	end
	local seen: { [string]: number } = {}
	for index, entry in sorted do
		seen[entry.place] = (seen[entry.place] or 0) + 1
		local name = placeName(entry.place) or entry.place
		local label = if (perPlace[entry.place] or 0) > 1 then `{name}  ·  #{seen[entry.place]}` else name
		Extras.secretRow(parent, entry, label, 10 + index)
	end
end

-- A campaign's reward card (the REWARDS grid): a click opens that campaign on the MISSIONS page.
function Extras.campaignCard(parent: Instance, campaign: Campaign, order: number)
	local reward = Config.Rewards.Campaigns[campaign.id]
	if not reward then
		return
	end
	local color = colorOf(campaign)
	local earned = Extras.state.campaigns[campaign.id] == true
	local id = campaign.id
	local card = Ui.make("TextButton", {
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
	}, parent)
	Extras.paper(card, if earned then P.paper else P.ticket, if earned then color else P.line, if earned then 2 else 1)
	Ui.padding(card, 8)
	Ui.list(card, true, 3, Enum.HorizontalAlignment.Center)
	card.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		Extras.tab = "missions"
		if selectedCampaign ~= id then
			selectCampaign(id)
		else
			render()
		end
	end)
	Ui.label(card, `{campaign.icon} {campaign.name}`, UDim2.new(1, 0, 0, 16), {
		TextSize = 12,
		Font = Theme.DisplayFont,
		TextColor3 = P.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 1,
	})
	Extras.itemIcon(card, reward, 44, if earned then "shown" else "dim", { LayoutOrder = 2 })
	Ui.label(card, Extras.itemName(reward), UDim2.new(1, 0, 0, 30), {
		TextSize = 12,
		Font = Theme.HeadingFont,
		TextColor3 = if earned then P.ink else P.ink2,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 3,
	})
	Ui.label(card, `“{reward.title}”`, UDim2.new(1, 0, 0, 16), {
		TextSize = 12,
		Font = Theme.HeadingFont,
		TextColor3 = if earned then Extras.GOLD else P.ink2,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 4,
	})
	Ui.label(card, if earned then "✓ EARNED" else `🔒 finish {campaign.name}`, UDim2.new(1, 0, 0, 16), {
		TextSize = 12,
		Font = Theme.DisplayFont,
		TextColor3 = if earned then C.green else P.ink2,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 5,
	})
end

-- Equip a title (nil = none): the server checks it is yours (a quick second click is applied after its spam gap, and
-- its state corrects the page if it refuses); the page shows it at once.
function Extras.equip(title: string?)
	Extras.ask("title", title)
	Extras.state.title = title
	say(if title then `Title equipped: “{title}”` else "No title shown.", Extras.GOLD)
	render()
end

-- One title row: the title, where it came from, EQUIP (or EQUIPPED).
function Extras.titleRow(parent: Instance, title: string?, order: number)
	local equipped = Extras.state.title == title
	local row = Ui.make("Frame", {
		Size = UDim2.new(1, -2, 0, 46),
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	Extras.paper(row, if equipped then P.tags[2] else P.ticket, if equipped then Extras.GOLD else P.line, if equipped then 1.5 else 1)
	Ui.label(row, if title then `🎖  {title}` else "No title", UDim2.new(1, -330, 1, 0), {
		Position = UDim2.fromOffset(12, 0),
		TextSize = 16,
		Font = Theme.DisplayFont,
		TextColor3 = if title then P.ink else P.ink2,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.label(row, if title then Extras.titleSource(title) else "nothing over your head", UDim2.fromOffset(190, 46), {
		Position = UDim2.new(1, -318, 0, 0),
		TextSize = 12,
		Font = Theme.Font,
		TextColor3 = P.ink2,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if equipped then
		local chip = Extras.chip(row, "✓ EQUIPPED", "good")
		chip.Size = UDim2.fromOffset(0, 28)
		chip.Position = UDim2.new(1, -10, 0.5, 0)
		chip.AnchorPoint = Vector2.new(1, 0.5)
		chip.TextSize = 13
	else
		local button = Ui.button(row, "EQUIP", UDim2.fromOffset(100, 32), P.sage, function()
			Extras.equip(title)
		end)
		button.TextSize = 14
		button.Position = UDim2.new(1, -10, 0.5, 0)
		button.AnchorPoint = Vector2.new(1, 0.5)
	end
end

-- An exclusive gun or paint: yours with an EXCLUSIVE badge, else dimmed with how to get it.
function Extras.exclusiveCard(parent: Instance, item: ExclusiveItem, order: number)
	local owned = Extras.owned(item.exclusive)
	local mystery = item.exclusive == "challenges" and not owned
	local color = Extras.itemColor(item.reward)
	local card = Ui.make("Frame", {
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	Extras.paper(card, if owned then P.paper else P.ticket, if owned then color:Lerp(P.ink, 0.2) else P.line, if owned then 1.5 else 1)
	Ui.padding(card, 6)
	Ui.list(card, true, 3, Enum.HorizontalAlignment.Center)
	local chip = Extras.chip(card, if owned then "EXCLUSIVE" else "REWARD", if owned then "coop" else "quiet", 1)
	chip.Size = UDim2.fromOffset(0, 18)
	Extras.itemIcon(card, item.reward, 40, if mystery then "silhouette" elseif owned then "shown" else "dim", { LayoutOrder = 2 })
	Ui.label(card, if mystery then "???" else item.name, UDim2.new(1, 0, 0, 28), {
		TextSize = 12,
		Font = Theme.HeadingFont,
		TextColor3 = if owned then P.ink else P.ink2,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 3,
	})
	Ui.label(card, if owned then (if item.kind == "weapon" then "yours · Gun Shop" else "yours · Garage") else Extras.howToGet(item.exclusive), UDim2.new(1, 0, 0, 26), {
		TextSize = 12,
		Font = Theme.HeadingFont,
		TextColor3 = if owned then C.green else P.ink2,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 4,
	})
end

-- A grid inside a page (it grows with its cells).
function Extras.grid(parent: Instance, columns: number, height: number, order: number): any
	local grid = Ui.make("Frame", {
		Size = UDim2.new(1, -2, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, parent)
	Ui.make("UIGridLayout", {
		CellSize = UDim2.new(1 / columns, -8, 0, height),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	return grid
end

function Extras.rewardsPage(parent: Instance)
	local S = Extras.state
	-- The campaign rewards.
	local earned = 0
	for _, campaign in Missions.Campaigns do
		if S.campaigns[campaign.id] then
			earned += 1
		end
	end
	Extras.section(parent, "🏆  CAMPAIGN REWARDS", `{earned} / {#Missions.Campaigns} earned`, 1)
	Extras.note(parent, "Finish all ten missions of a campaign: its gun or paint and its title are yours, and nobody can buy them.", 2)
	local grid = Extras.grid(parent, 5, 160, 3)
	for order, campaign in Missions.Campaigns do
		Extras.campaignCard(grid, campaign, order)
	end
	-- The titles: none, then the earned ones (in Challenges.allTitles order, anything else after).
	local all = Challenges.allTitles()
	local mine: { string } = {}
	for _, title in all do
		if S.titles[title] and not table.find(mine, title) then
			table.insert(mine, title)
		end
	end
	for title, on in S.titles do
		if on and not table.find(mine, title) then
			table.insert(mine, title)
		end
	end
	Extras.section(parent, "🎖  YOUR TITLES", `{#mine} / {#all} earned`, 10)
	Extras.note(parent, "The title you equip shows over your head for everyone and on the leaderboard.", 11)
	Extras.titleRow(parent, nil, 12)
	for index, title in mine do
		Extras.titleRow(parent, title, 12 + index)
	end
	if #mine == 0 then
		Extras.note(parent, "No titles yet: finish a campaign, or the challenges with 🎖.", 200)
	end
	-- The exclusive guns and paints.
	local items = Extras.exclusives()
	local owned = 0
	for _, item in items do
		if Extras.owned(item.exclusive) then
			owned += 1
		end
	end
	Extras.section(parent, "💎  EXCLUSIVE ITEMS", `{owned} / {#items} yours`, 300)
	local itemsGrid = Extras.grid(parent, 6, 146, 301)
	for order, item in items do
		Extras.exclusiveCard(itemsGrid, item, order)
	end
end

-- Draws the page in refs.extra.
function Extras.renderPage(page: string)
	local parent = refs.extra
	Ui.clear(parent)
	if page == "challenges" then
		Extras.challengesPage(parent)
	elseif page == "secrets" then
		Extras.secretsPage(parent)
	elseif page == "rewards" then
		Extras.rewardsPage(parent)
	end
end

-- The page tabs: ("open") so the server sends a fresh state for the 3.1 pages.
function Extras.setTab(id: string)
	if Extras.tab == id then
		return
	end
	Extras.tab = id
	if id ~= "missions" then
		Extras.ask("open")
	end
	if refs.extra then
		refs.extra.CanvasPosition = Vector2.zero
	end
	render()
end

-- ── Rendering ──────────────────────────────────────────────────────────────

render = function()
	local window = refs.window
	if not window or not window.Visible then
		return
	end
	hideTip()
	-- The header.
	local got, most = Missions.stars(progress, nil)
	refs.stars.Text = `★ {got} / {most}`
	refs.chrome.context.Text = `<b>★ {got} / {most} STARS</b> · U · Missions, challenges, lost packages, rewards`
	for id, button in refs.tabs do
		Extras.paintTab(button, filter == id)
	end
	-- 3.1: the page tabs; the CHALLENGES / SECRETS / REWARDS pages draw in their own list.
	do
		local page = Extras.tab
		local S = Extras.state
		local done = Extras.count(S.done)
		for id, button in refs.pages do
			Extras.paintTab(button, page == id)
		end
		refs.pages.challenges.Text = `🏅 CHALLENGES {math.min(done, #Challenges.List)}/{#Challenges.List}`
		local missionsPage = page == "missions"
		refs.campaigns.Visible = missionsPage
		refs.missions.Visible = missionsPage
		refs.column.Visible = missionsPage
		refs.extra.Visible = not missionsPage
		if not missionsPage then
			refs.stars.Text = if page == "challenges" then `🏅 {math.min(done, #Challenges.List)} / {#Challenges.List}`
				elseif page == "secrets" then `📦 {Extras.count(S.secrets)} / {math.max(S.secretsTotal, #Extras.secretList())}`
				else `🎖 {Extras.count(S.titles)} titles`
			Extras.renderPage(page)
			return
		end
	end
	-- The campaigns.
	Ui.clear(refs.campaigns)
	for order, campaign in Missions.Campaigns do
		campaignRow(campaign, order)
	end
	-- The selected campaign and its missions.
	Ui.clear(refs.missions)
	local campaign = Missions.findCampaign(selectedCampaign) or Missions.Campaigns[1]
	campaignHeader(campaign, 1)
	local shown = 0
	for _, def in Missions.ofCampaign(campaign.id) do
		if visible(def) then
			shown += 1
			missionCard(def, campaign, 10 + def.number * 2)
			if selectedMission == def.id then
				missionDetail(def, campaign, 11 + def.number * 2)
			end
		end
	end
	if shown == 0 then
		Ui.label(refs.missions, if filter == "coop" then "No co-op missions in this campaign." else "No missions here yet.", UDim2.new(1, -2, 0, 40), {
			LayoutOrder = 5,
			TextSize = 14,
			Font = Theme.Font,
			TextColor3 = P.ink2,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
	end
end

-- ── Open / close ───────────────────────────────────────────────────────────

local function setOpen(open: boolean, campaignId: string?)
	if open then
		build()
		if not hudOn() then
			return
		end
		local window = refs.window
		if not window.Visible then
			-- One window at a time.
			local cb = MissionsUi.onOpen
			if cb then
				cb()
			end
			ask("open")
			-- 3.1: a CHALLENGES / SECRETS / REWARDS page wants a fresh state too.
			if Extras.tab ~= "missions" and not campaignId then
				Extras.ask("open")
			end
		end
		-- A campaign asked for (NEXT MISSION, a reward card): the MISSIONS page.
		if campaignId then
			Extras.tab = "missions"
		end
		local target = if campaignId and Missions.findCampaign(campaignId) then campaignId else nil
		if target or not window.Visible then
			local id = target or currentCampaign()
			blindPick = not target and not hasState
			if id ~= selectedCampaign or not selectedMission then
				selectedCampaign = id
				selectedMission = currentMission(id)
			end
			refs.missions.CanvasPosition = Vector2.zero
		end
		window.Visible = true
		render()
	else
		hideTip()
		if refs.window then
			refs.window.Visible = false
		end
	end
end

-- START: the server checks it (open, level, no job, not in somebody else's crew) and answers with a Notice.
function MissionsUi.startMission(id: string)
	local def = Missions.find(id)
	if not def then
		return
	end
	if crewOwner then
		say(`Your crew leader {crewOwner} picks the mission.`, P.violet)
		return
	end
	if ownJob then
		say("Finish your current delivery first.", P.danger)
		return
	end
	local ok, why = Missions.unlocked(id, progress, myLevel())
	if not ok then
		say(why or "Locked.", P.danger)
		return
	end
	-- 3.2: a DUO mission without a crew: why, and FIND CREW is next to START (the server checks the range too).
	if Extras.needsCrew(def) then
		say(Extras.DUO_REFUSAL, P.danger)
		return
	end
	local short = Extras.slotsShort(def)
	if short then
		say(Extras.slotsText(short), P.danger)
		return
	end
	pendingStart = id
	say(`Starting "{def.name}"…`, P.ink)
	ask("start", id)
end

-- FIND CREW: on the crew board for this mission, and the crew panel opens (Main: MissionsUi.onFindCrew).
function MissionsUi.findCrew(id: string)
	if not Missions.find(id) then
		return
	end
	Net.get("CrewBoard"):FireServer(id)
	local cb = MissionsUi.onFindCrew
	if cb then
		cb(id)
	else
		CrewPanel.open()
	end
end

-- ── The banner during a mission (the Hud's top stack) ──────────────────────

-- 3.6: a small paper ticket under the objective ticket, tilted the other way (+0.5°): the campaign's colour as its
-- edge, the mission's name and the crew on top, the twists under it, HOLD OUT / the levers when they matter, and a
-- perforated stub with "3/10".
local function buildBanner()
	-- Right under the job panel and the crew strip, above the car call line and the toasts (Hud's SLOT_ORDER).
	local slot = Hud.topSlot("mission")
	local banner = Ui.make("Frame", {
		Name = "MissionBanner",
		Size = UDim2.new(0.92, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = K.scrim, -- a localized charcoal scrim over the world
		BorderSizePixel = 0,
		Visible = false,
	}, slot)
	Ui.corner(banner)
	refs.banner = banner
	refs.bannerEdge = Ui.edge(banner, P.violet)
	local body = Ui.make("Frame", { Size = UDim2.new(1, -66, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, banner)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, body)
	Ui.list(body, true, 3)
	local header = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 1 }, body)
	refs.bannerTitle = Ui.label(header, "", UDim2.new(1, -96, 1, 0), {
		TextSize = 15,
		Font = Theme.DisplayFont,
		TextColor3 = P.ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	refs.bannerCrew = Ui.label(header, "", UDim2.new(0, 96, 1, 0), {
		Position = UDim2.new(1, -96, 0, 0),
		TextSize = 14,
		Font = Theme.HeadingFont,
		TextColor3 = P.violet,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
	refs.bannerTwists = Ui.label(body, "", UDim2.new(1, 0, 0, 18), {
		LayoutOrder = 2,
		TextSize = 14,
		Font = Theme.Font,
		TextColor3 = P.ink2,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	refs.bannerDefend = Ui.label(body, "", UDim2.new(1, 0, 0, 22), {
		LayoutOrder = 3,
		Visible = false,
		TextSize = 17,
		Font = Theme.DisplayFont,
		TextColor3 = P.danger,
	})
	-- The mission's number behind a fine line.
	Ui.dashes(banner, true, 6, P.line, UDim2.new(0, 1, 1, -12), UDim2.new(1, -66, 0, 6))
	refs.bannerNumber = Ui.label(banner, "", UDim2.new(0, 62, 0, 24), {
		Position = UDim2.new(1, -64, 0.5, -4),
		AnchorPoint = Vector2.new(0, 0.5),
		TextSize = 18,
		Font = Theme.DisplayFont,
		TextColor3 = P.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
	})
	Ui.caps(banner, "Mission", UDim2.new(0, 62, 0, 14), {
		Position = UDim2.new(1, -64, 0.5, 10),
		TextSize = 12,
		TextColor3 = P.ink2,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
end

-- The mission the banner shows: my own, else (a member) the leader's.
local function bannerMission(): (any, number)
	if jobMission then
		return jobMission, jobCrew
	end
	return crewMission, crewCount
end

local function updateBanner()
	local banner = refs.banner
	if not banner then
		return
	end
	local mission, members = bannerMission()
	banner.Visible = mission ~= nil
	if not mission then
		return
	end
	local def = if type(mission.id) == "string" then Missions.find(mission.id) else nil
	local campaign = if def then campaignOf(def) elseif type(mission.campaign) == "string" then Missions.findCampaign(mission.campaign) else nil
	local number = if type(mission.number) == "number" then mission.number elseif def then def.number else nil
	local name = if type(mission.name) == "string" then mission.name elseif def then def.name else "Mission"
	refs.bannerTitle.Text = `{if campaign then campaign.icon else "🎯"}  {name}`
	refs.bannerNumber.Text = if number then `{number}/10` else "—"
	refs.bannerEdge.BackgroundColor3 = if campaign then colorOf(campaign) else P.violet
	local coop = mission.coop == true or (def ~= nil and def.coop == true)
	local duo = mission.duo == true or (def ~= nil and def.duo == true)
	refs.bannerCrew.Text = if duo then `🤝 DUO ×{members + 1}` elseif coop then `👥 CO-OP ×{members + 1}` else (if members > 0 then `👥 ×{members + 1}` else "")
	local parts = {}
	local twists = if type(mission.twists) == "table" then mission.twists elseif def then twistsOf(def) else {}
	for _, twist in twists do
		local info = T.Twists[twist]
		if info then
			table.insert(parts, `{info.icon} {info.name}`)
		end
	end
	refs.bannerTwists.Text = if #parts > 0 then table.concat(parts, "   ") else "no twists: just deliver"
	-- HOLD OUT: the server's seconds, counted down here between its updates (at most a little ahead of it: the
	-- own job sends every second, the crew state every 2 s; leaving the radius pauses the server's clock).
	local left = if type(mission.defendLeft) == "number" then mission.defendLeft - math.min(os.clock() - defendAt, if jobMission then 1.2 else 2.2) else nil
	refs.bannerDefend.Visible = left ~= nil and left > 0
	if left and left > 0 then
		refs.bannerDefend.Text = `🛡 HOLD OUT {Ui.clock(math.ceil(left))}  ·  stay near the receiver`
		refs.bannerDefend.TextColor3 = P.danger
	elseif type(mission.gatePulled) == "number" then
		-- 3.2, TWIN SWITCHES: the gate here is shut until both levers are pulled together.
		refs.bannerDefend.Visible = true
		refs.bannerDefend.Text = `🎛 PULL BOTH LEVERS TOGETHER  ·  {math.clamp(mission.gatePulled, 0, 2)}/2`
		refs.bannerDefend.TextColor3 = P.ink
	end
end

-- ── The celebration card ("cleared") ───────────────────────────────────────

local clearedToken = 0
local clearedNext: string? = nil

local function hideCleared()
	clearedToken += 1
	if refs.cleared then
		refs.cleared.Visible = false
	end
	-- 3.1: a popup waiting for the card follows at once (deferred: NEXT MISSION opens the window first).
	local pumpPopups = Extras.pumpPopups
	if pumpPopups then
		task.defer(pumpPopups)
	end
end

local function buildCleared()
	if refs.cleared then
		return
	end
	local gui = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryMissionCleared",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 6,
	}, player:WaitForChild("PlayerGui"))
	-- A charcoal card, the campaign's colour as its fine rim (set on every show).
	local card = Ui.make("Frame", {
		Name = "MissionCleared",
		Size = UDim2.fromOffset(460, 0),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Visible = false,
	}, gui)
	Ui.corner(card)
	refs.clearedRim = Ui.stroke(card, P.violet, 1)
	refs.clearedRim.Transparency = 0
	refs.cleared = card
	refs.clearedGui = gui
	refs.clearedScale = Ui.make("UIScale", {}, card)
	Ui.padding(card, 16)
	Ui.list(card, true, 8, Enum.HorizontalAlignment.Center)
	local function line(name: string, order: number, size: number, font: Enum.Font, color: Color3)
		refs[name] = Ui.label(card, "", UDim2.new(1, 0, 0, 0), {
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			TextSize = size,
			Font = font,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Center,
			RichText = true,
		})
	end
	line("clearedRibbon", 1, 14, Theme.DisplayFont, P.violet)
	line("clearedName", 2, 26, Theme.DisplayFont, P.ink)
	-- The three stars (they fly in one after the other).
	local starRow = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1, LayoutOrder = 3 }, card)
	refs.clearedStars = {}
	for index = 1, 3 do
		local holder = Ui.make("Frame", {
			Size = UDim2.fromOffset(64, 64),
			Position = UDim2.new(0.5, (index - 2) * 74, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
		}, starRow)
		local star = Ui.label(holder, "★", UDim2.fromScale(1, 1), {
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			TextSize = 60,
			Font = Theme.DisplayFont,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeColor3 = K.charcoal,
			TextStrokeTransparency = 0.5,
		})
		table.insert(refs.clearedStars, star)
	end
	line("clearedBest", 4, 14, Theme.DisplayFont, C.green)
	line("clearedDebrief", 5, 16, Theme.Font, P.ink)
	line("clearedRewards", 6, 15, Theme.HeadingFont, C.money)
	line("clearedCampaign", 7, 18, Theme.DisplayFont, C.yellow)
	local buttons = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, LayoutOrder = 8 }, card)
	Ui.list(buttons, false, 10, Enum.HorizontalAlignment.Center)
	refs.clearedNext = Ui.button(buttons, "NEXT MISSION ▶", UDim2.fromOffset(200, 42), P.sage, function()
		local id = clearedNext
		hideCleared()
		local def = if id then Missions.find(id) else nil
		if def then
			-- The window opens on that campaign with the mission's card open.
			selectedCampaign = def.campaign
			selectedMission = def.id
			MissionsUi.open(def.campaign)
		else
			MissionsUi.open()
		end
	end)
	refs.clearedNext.LayoutOrder = 1
	local ok = Ui.button(buttons, "OK", UDim2.fromOffset(110, 42), C.blue, function()
		hideCleared()
	end)
	ok.LayoutOrder = 2
	local function scaleCard()
		local camera = workspace.CurrentCamera
		if camera then
			local size = camera.ViewportSize
			refs.clearedScale.Scale = math.clamp(math.min((size.X - 16) / 480, (size.Y - 16) / 600), 0.5, 1.1)
		end
	end
	scaleCard()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(scaleCard)
	end
end

-- 3.6 threw confetti over the card here. 3.8 (the contract UI: no decorative motion) keeps the call for its callers
-- and draws nothing; the card's coloured rim and its words carry the moment.
local function confetti(color: Color3, target: Instance?)
	local _ = color and target
end

local function showCleared(data: any)
	if type(data) ~= "table" or type(data.id) ~= "string" then
		return
	end
	buildCleared()
	local def = Missions.find(data.id)
	local campaign = if def then campaignOf(def) else nil
	local color = colorOf(campaign)
	local stars = math.clamp(tonumber(data.stars) or 1, 1, 3)
	local card = refs.cleared
	refs.clearedRim.Color = color
	refs.clearedRibbon.Text = if def then `{if campaign then campaign.icon .. "  " else ""}MISSION {def.number}/10 COMPLETE` else "MISSION COMPLETE"
	refs.clearedRibbon.TextColor3 = P.violet
	refs.clearedName.Text = esc(tostring(data.name or (def and def.name) or "Mission"))
	local newStars = tonumber(data.newStars) or 0
	local bestStars = tonumber(data.best) or stars
	refs.clearedBest.Text = if (tonumber(data.reward) or 0) > 0 then "FIRST CLEAR!"
		elseif newStars > 0 then `NEW BEST!  +{newStars} ★`
		elseif bestStars > stars then `Your best stays {Ui.stars(math.clamp(bestStars, 1, 3))}`
		else ""
	refs.clearedBest.Visible = refs.clearedBest.Text ~= ""
	refs.clearedDebrief.Text = if def then `“{esc(def.debrief)}”\n<font color="{Extras.hex(P.ink2)}" size="14">— {esc(if campaign then campaign.client else def.giver)}</font>` else ""
	refs.clearedDebrief.Visible = def ~= nil
	-- The rewards.
	local parts = {}
	local reward = tonumber(data.reward) or 0
	if reward > 0 then
		table.insert(parts, `First clear  +{Ui.money(reward)}`)
	end
	local starBonus = tonumber(data.starBonus) or 0
	if starBonus > 0 then
		table.insert(parts, `New stars  +{Ui.money(starBonus)}`)
	end
	local campaignReward = tonumber(data.campaignReward) or 0
	if campaignReward > 0 then
		table.insert(parts, `Campaign reward  +{Ui.money(campaignReward)}`)
	end
	refs.clearedRewards.Text = table.concat(parts, "\n")
	refs.clearedRewards.Visible = #parts > 0
	local campaignDone = if type(data.campaignDone) == "string" then data.campaignDone else nil
	refs.clearedCampaign.Text = if campaignDone then `🏆  {esc(string.upper(campaignDone))} COMPLETE!` else ""
	refs.clearedCampaign.Visible = campaignDone ~= nil
	-- NEXT MISSION (members: their leader picks; the button still opens the window there).
	local following = nextMission(data.id)
	clearedNext = if following then following.id else nil
	refs.clearedNext.Text = if following then `NEXT: {following.name} ▶` else "ALL MISSIONS ▶"
	refs.clearedNext.Visible = true
	-- The stars fly in.
	for index, star in refs.clearedStars do
		local earned = index <= stars
		star.Text = if earned then "★" else "☆"
		star.TextColor3 = if earned then C.yellow else P.line
		star.TextTransparency = 1
		star.TextStrokeTransparency = 1
		star.TextSize = 60
		star.Rotation = 0
		-- 3.8: they fade in one after the other (no spin, no bounce).
		local delay = 0.25 + (index - 1) * 0.2
		task.delay(delay, function()
			if not star.Parent then
				return
			end
			TweenService:Create(star, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				TextTransparency = if earned then 0 else 0.3,
				TextStrokeTransparency = if earned then 0.5 else 1,
			}):Play()
		end)
	end
	card.Visible = true
	card.Position = UDim2.new(0.5, 0, 0.45, 8)
	TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.45) }):Play()
	confetti(color)
	clearedToken += 1
	local mine = clearedToken
	task.delay(CLEARED_TIME, function()
		if clearedToken == mine then
			hideCleared()
		end
	end)
end

-- ── 3.1: the unlock popups (the Challenges remote's "unlocked") ────────────
-- In the Hud's top stack (under the toasts: nothing there is covered), one at a time from a queue, the 3.0 cleared
-- card's look. A flood (many at once, e.g. the admin's challengesAll) merges into one "N more" card per kind.

do -- (its own block: the locals below stay out of the 200-register limit)
	type Popup = { card: any, duration: number, loops: { Tween }, color: Color3, big: boolean }
	type Queued = { u: { [string]: any } }

	local queue: { Queued } = {}
	local busy = false
	local waiting = false
	local BIG: { [string]: boolean } = { campaign = true, secrets = true, challenges = true }
	local MERGE: { [string]: boolean } = { challenge = true, secret = true, place = true }
	-- Not now: the interface is off, or something would cover the popup: the DELIVERY result, the cleared card (or
	-- one on its way: the server sends a campaign's reward before its "cleared"), or this window (MissionsUi.isOpen).
	local function blocked(): boolean
		return not hudOn() or Hud.resultOpen() or Extras.clearedPending > 0 or MissionsUi.isOpen()
	end

	local function line(parent: Instance, text: string, order: number, size: number, font: Enum.Font, color: Color3): any
		return Ui.label(parent, text, UDim2.new(1, 0, 0, 0), {
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			TextSize = size,
			Font = font,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Center,
			RichText = true,
		})
	end

	-- The big reward's picture: the item on a dark square with a fine frame in its colour (3.8: no pulsing glow;
	-- `loops` stays for the callers).
	local function glowArt(parent: Instance, reward: RewardItem?, color: Color3, loops: { Tween })
		local _ = loops
		local art = Ui.make("Frame", { Size = UDim2.fromOffset(124, 124), BackgroundColor3 = K.charcoal, BorderSizePixel = 0, LayoutOrder = 2 }, parent)
		Ui.stroke(art, color, 1).Transparency = 0
		if reward then
			Extras.itemIcon(art, reward, 88, "shown", { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
		else
			Ui.label(art, "🏆", UDim2.fromScale(1, 1), { TextSize = 60, TextXAlignment = Enum.TextXAlignment.Center })
		end
	end

	-- The card of one unlock, and how long it stays.
	local function build(u: { [string]: any }): Popup
		local slot = Hud.topSlot("unlocked")
		local kind = tostring(u.kind)
		local big = BIG[kind] == true
		local name = esc(tostring(u.name or ""))
		local money = tonumber(u.money) or 0
		-- A merged card (a flood): how many it stands for; one alone shows as a normal card.
		local merged = tonumber(u.batch)
		local batch = if merged and merged > 1 then merged else nil
		local title = if type(u.title) == "string" and u.title ~= "" and not batch then esc(u.title) else nil
		local reward: RewardItem? = if type(u.weapon) == "string" then { weapon = u.weapon }
			elseif type(u.paint) == "string" then { paint = u.paint }
			else nil
		local color = if kind == "place" then C.blue
			elseif kind == "secret" then C.yellow
			elseif kind == "challenge" then C.green
			elseif kind == "challenges" then Extras.PURPLE
			elseif reward then Extras.itemColor(reward)
			else C.yellow
		local loops: { Tween } = {}
		local card = Ui.make("TextButton", {
			Name = "Unlocked",
			Size = UDim2.new(if kind == "place" then 0.86 elseif big then 1 else 0.9, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = K.charcoal, -- a charcoal card over the world, its colour as a fine rim
			BackgroundTransparency = 0.06,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Selectable = false,
			Text = "",
		}, slot)
		Ui.corner(card)
		Ui.stroke(card, color, 1).Transparency = 0
		Ui.make("Frame", { Name = "Rule", Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 }, card)
		Ui.make("UIScale", { Name = "Pop", Scale = 0.97 }, card)
		local count = if tonumber(u.count) and tonumber(u.total) then `  {u.count}/{u.total}` else ""
		if kind == "place" then
			-- A thin strip, like a toast.
			Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, card)
			-- 3.7: "discovered" is the map's banner now (client/Discovery.luau); this strip counts the places visited.
			local text = if batch then `🧭  {batch} PLACES VISITED{if count ~= "" then ` ({string.sub(count, 3)})` else ""}`
				else `🧭  PLACE VISITED: <b>{name}</b>{if count ~= "" then ` ({string.sub(count, 3)})` else ""}`
			line(card, text, 1, 15, Theme.HeadingFont, P.ink)
			return { card = card, duration = 3.5, loops = loops, color = color, big = false }
		end
		Ui.padding(card, if big then 16 else 12)
		Ui.list(card, true, if big then 6 else 4, Enum.HorizontalAlignment.Center)
		if kind == "secret" then
			line(card, if batch then `📦  {batch} LOST PACKAGES{count}` else `📦  LOST PACKAGE{count}`, 1, 21, Theme.DisplayFont, C.yellow)
			if name ~= "" and not batch then
				line(card, name, 2, 14, Theme.HeadingFont, P.ink2)
			end
			if money > 0 then
				line(card, `+{Ui.money(money)}`, 3, 21, Theme.DisplayFont, C.money)
			end
			return { card = card, duration = 4.5, loops = loops, color = color, big = false }
		elseif kind == "challenge" then
			local def = if type(u.id) == "string" then Challenges.find(u.id) else nil
			line(card, if batch then "🏅  CHALLENGES COMPLETE" else "🏅  CHALLENGE COMPLETE", 1, 14, Theme.DisplayFont, C.green)
			line(card, if batch then `{batch} challenges done` else name, 2, 23, Theme.DisplayFont, P.ink)
			if def and not batch then
				line(card, esc(def.description), 3, 14, Theme.Font, P.ink2)
			end
			if money > 0 then
				line(card, `+{Ui.money(money)}`, 4, 20, Theme.DisplayFont, C.money)
			end
			if title then
				line(card, `🎖 New title: “{title}”`, 5, 14, Theme.HeadingFont, Extras.GOLD)
			end
			line(card, `{Extras.count(Extras.state.done)}/{#Challenges.List} challenges  ·  MISSIONS (U) → CHALLENGES`, 6, 12, Theme.HeadingFont, P.ink2)
			return { card = card, duration = 5, loops = loops, color = color, big = false }
		end
		-- BIG: a campaign's reward, every lost package's, every challenge's.
		local campaign = if kind == "campaign" and type(u.id) == "string" then Missions.findCampaign(u.id) else nil
		local ribbon = if kind == "campaign" then `🏆  {string.upper(if campaign then esc(campaign.name) else name)} COMPLETE`
			elseif kind == "secrets" then "📦  EVERY LOST PACKAGE FOUND"
			elseif kind == "challenges" then "☠  EVERY CHALLENGE COMPLETE"
			else `🏆  {string.upper(name)}`
		line(card, ribbon, 1, 15, Theme.DisplayFont, P.violet)
		glowArt(card, reward, color, loops)
		line(card, "EXCLUSIVE  ·  nobody can buy this", 3, 12, Theme.DisplayFont, P.violet)
		line(card, if reward then esc(Extras.itemName(reward)) else name, 4, 30, Theme.DisplayFont, P.ink)
		if title then
			line(card, `🎖 Title: “{title}”`, 5, 16, Theme.HeadingFont, Extras.GOLD)
		end
		if money > 0 then
			line(card, `+{Ui.money(money)}`, 6, 20, Theme.DisplayFont, C.money)
		end
		local hint = if reward and reward.weapon then "Switch to it with Q, or equip it at the Gun Shop."
			elseif reward and reward.paint then "Paint a car with it at Wrench Garage."
			else ""
		line(card, `{hint}  Titles: MISSIONS (U) → REWARDS.`, 7, 12, Theme.HeadingFont, P.ink2)
		return { card = card, duration = 9, loops = loops, color = color, big = true }
	end

	local pump: () -> ()

	local function show(item: Queued)
		busy = true
		local ok, popup = pcall(build, item.u)
		if not ok then
			warn(`[MissionsUi] unlocked popup: {popup}`)
			busy = false
			pump()
			return
		end
		local card = popup.card
		local pop = card:FindFirstChild("Pop")
		TweenService:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if popup.big then
			confetti(popup.color, card:FindFirstAncestorWhichIsA("ScreenGui"))
		end
		local closed = false
		local function close()
			if closed then
				return
			end
			closed = true
			for _, loop in popup.loops do
				loop:Cancel()
			end
			TweenService:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
			task.delay(0.2, function()
				card:Destroy()
				busy = false
				pump()
			end)
		end
		card.Activated:Connect(close)
		-- More waiting: each one stays shorter.
		task.delay(if #queue > 2 then math.max(1.8, popup.duration * 0.5) else popup.duration, close)
	end

	pump = function()
		if busy or #queue == 0 then
			return
		end
		if not blocked() then
			show(table.remove(queue, 1) :: Queued)
			return
		end
		-- They must wait: look again soon.
		if not waiting then
			waiting = true
			task.delay(0.5, function()
				waiting = false
				pump()
			end)
		end
	end
	Extras.pumpPopups = pump

	-- The Challenges remote's "unlocked" (U in the 3.1 spec).
	function Extras.unlocked(u: any)
		if type(u) ~= "table" or type(u.kind) ~= "string" then
			return
		end
		-- Counted at once (the server's next state agrees): the card's "X/40" and the pages are not one behind.
		if type(u.id) == "string" then
			local S = Extras.state
			if u.kind == "challenge" then
				S.done[u.id] = true
			elseif u.kind == "secret" then
				S.secrets[u.id] = true
			elseif u.kind == "place" then
				S.visited[u.id] = true
			end
		end
		if MERGE[u.kind] and #queue >= 4 then
			-- A flood: the rest of this kind merge into one card (the money summed, the latest count).
			for _, item in queue do
				local merged = item.u
				if merged.kind == u.kind and merged.batch then
					merged.batch += 1
					merged.money = (tonumber(merged.money) or 0) + (tonumber(u.money) or 0)
					merged.count, merged.total = u.count, u.total
					return
				end
			end
			local first = table.clone(u)
			first.batch = 1
			table.insert(queue, { u = first })
		else
			table.insert(queue, { u = u })
		end
		pump()
	end
end

-- The Challenges remote's "state" (S in the 3.1 spec), checked.
function Extras.apply(data: any)
	if type(data) ~= "table" then
		return
	end
	local function flags(value: any): { [string]: boolean }
		local set: { [string]: boolean } = {}
		if type(value) == "table" then
			for key, on in value do
				if type(key) == "string" and on then
					set[key] = true
				end
			end
		end
		return set
	end
	local values: { [string]: number } = {}
	if type(data.values) == "table" then
		for stat, value in data.values do
			if type(stat) == "string" and type(value) == "number" then
				values[stat] = value
			end
		end
	end
	local rewards = if type(data.rewards) == "table" then data.rewards else {}
	Extras.state = {
		values = values,
		done = flags(data.done),
		secrets = flags(data.secrets),
		secretsTotal = if type(data.secretsTotal) == "number" then data.secretsTotal else #Extras.secretList(),
		visited = flags(data.visited),
		placesTotal = if type(data.placesTotal) == "number" then data.placesTotal else #Map.Places,
		titles = flags(data.titles),
		title = if type(data.title) == "string" and data.title ~= "" then data.title else nil,
		campaigns = flags(rewards.campaigns),
		secretsReward = rewards.secrets == true,
		challengesReward = rewards.challenges == true,
	}
	Extras.hasState = true
	if refs.window and refs.window.Visible then
		queueRender()
	end
end

-- ── The server's messages ──────────────────────────────────────────────────

local function applyState(data: any)
	if type(data) ~= "table" then
		return
	end
	local fresh: { [string]: number } = {}
	if type(data.progress) == "table" then
		for id, stars in data.progress do
			if type(id) == "string" and type(stars) == "number" then
				fresh[id] = stars
			end
		end
	end
	progress = fresh
	serverLevel = if type(data.level) == "number" then data.level else nil
	active = if type(data.active) == "string" then data.active else nil
	crewOwner = if type(data.crewOwner) == "string" then data.crewOwner else nil
	Extras.crewSize = if type(data.crewSize) == "number" then data.crewSize else 0
	Extras.capacity = if type(data.capacity) == "number" then data.capacity else nil
	Extras.carName = if type(data.carName) == "string" then data.carName else "car"
	Extras.carId = if type(data.carId) == "string" then data.carId else Config.Cars[1].id
	Extras.carStage = if type(data.carStage) == "number" then data.carStage else 0
	hasState = true
	-- Opened before the first state (a slow load): pick where the player is in the story now.
	if blindPick then
		blindPick = false
		selectedCampaign = currentCampaign()
		selectedMission = currentMission(selectedCampaign)
	end
	if pendingStart and active == pendingStart then
		pendingStart = nil
		setOpen(false)
	elseif refs.window and refs.window.Visible then
		queueRender()
	end
end

local function onJob(job: any)
	ownJob = job ~= nil
	local mission = if type(job) == "table" and type(job.mission) == "table" and type(job.mission.id) == "string" then job.mission else nil
	jobMission = mission
	jobCrew = if type(job) == "table" and type(job.crewCount) == "number" then job.crewCount else 0
	if mission and type(mission.defendLeft) == "number" then
		defendAt = os.clock()
	end
	if mission and pendingStart == mission.id then
		pendingStart = nil
		setOpen(false)
	end
	if not ownJob then
		active = nil
	end
	updateBanner()
end

local function onCrewState(state: any)
	local member = type(state) == "table" and state.role == "member"
	local status = if member and type(state.status) == "table" then state.status else nil
	local mission = if status and type(status.mission) == "table" and type(status.mission.id) == "string" then status.mission else nil
	crewMission = mission
	crewCount = if status and type(status.crewCount) == "number" then status.crewCount else 0
	if mission and type(mission.defendLeft) == "number" then
		defendAt = os.clock()
	end
	-- The leader's name (the server's state says it too; this is quicker after joining or leaving).
	local owner = if member and type(state.owner) == "table" then state.owner.name else nil
	local changed = (owner ~= nil) ~= (crewOwner ~= nil)
	crewOwner = if type(owner) == "string" then owner else nil
	-- 3.2: my own crew's size (the DUO missions), quicker than the next Missions state.
	local size = if type(state) == "table" and state.role == "owner" and type(state.members) == "table" then #state.members else 0
	if size ~= Extras.crewSize then
		Extras.crewSize = size
		changed = true
	end
	if changed and refs.window and refs.window.Visible then
		queueRender()
	end
	updateBanner()
end

-- ── API ────────────────────────────────────────────────────────────────────

function MissionsUi.isOpen(): boolean
	return (refs.window ~= nil and refs.window.Visible == true) or (refs.cleared ~= nil and refs.cleared.Visible == true)
end

function MissionsUi.close()
	setOpen(false)
end

-- Opens the window (on a campaign, else where you are in the story).
function MissionsUi.open(campaignId: string?)
	setOpen(true, campaignId)
end

-- 3.1: opens the window on a page ("missions" | "challenges" | "secrets" | "rewards").
function MissionsUi.openTab(page: string)
	local known = false
	for _, entry in Extras.PAGES do
		if entry.id == page then
			known = true
		end
	end
	if not known then
		return
	end
	local wasOpen = refs.window ~= nil and refs.window.Visible == true
	Extras.tab = page
	setOpen(true)
	if wasOpen and page ~= "missions" then
		Extras.ask("open")
	end
end

-- U and the Hud's MISSIONS button (Hud.onMissions).
function MissionsUi.toggle()
	if refs.window and refs.window.Visible then
		setOpen(false)
	else
		setOpen(true)
	end
end

function MissionsUi.start()
	buildBanner()
	getRemote().OnClientEvent:Connect(function(kind: any, data: any)
		if kind == "state" then
			applyState(data)
		elseif kind == "cleared" then
			-- The Hud's DELIVERY result comes first: the card waits until it is closed (not over its pay and buttons).
			-- 3.1: the unlock popups wait for it from now on (Extras.clearedPending), not only once it shows.
			Extras.clearedPending += 1
			task.spawn(function()
				task.wait(0.2)
				local waited = 0
				while Hud.resultOpen() and waited < 120 do
					waited += task.wait(0.25)
				end
				Extras.clearedPending -= 1
				showCleared(data)
			end)
		elseif type(kind) == "table" then
			applyState(kind)
		end
	end)
	Net.get("Job").OnClientEvent:Connect(onJob)
	Net.get("CrewState").OnClientEvent:Connect(onCrewState)
	-- 3.1: the challenges, secrets and rewards ("state"), and what was just unlocked (the popups).
	local challengesRemote = Net.get("Challenges")
	Extras.remote = challengesRemote
	challengesRemote.OnClientEvent:Connect(function(kind: any, data: any)
		if kind == "state" then
			Extras.apply(data)
		elseif kind == "unlocked" then
			Extras.unlocked(data)
		end
	end)
	-- The server's answers, in the window too (the toasts are behind it).
	Net.get("Notice").OnClientEvent:Connect(function(text: any)
		if refs.window and refs.window.Visible and type(text) == "string" then
			say(text, P.ink)
		end
	end)
	player:GetAttributeChangedSignal("Level"):Connect(function()
		if refs.window and refs.window.Visible then
			queueRender()
		end
	end)
	-- U opens and closes the window (not while typing, e.g. in the chat).
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.U or UserInputService:GetFocusedTextBox() or not hudOn() then
			return
		end
		MissionsUi.toggle()
	end)
	-- The interface went off (back to the start screen): the window and the card go too.
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		local hud = playerGui:WaitForChild("ZombieDeliveryHud", 30)
		if hud and hud:IsA("ScreenGui") then
			hud:GetPropertyChangedSignal("Enabled"):Connect(function()
				if not hud.Enabled then
					setOpen(false)
					hideCleared()
				end
			end)
		end
	end)
	-- The HOLD OUT countdown between the server's updates (only while a mission runs).
	task.spawn(function()
		while true do
			task.wait(0.25)
			if jobMission or crewMission then
				local ok, err = pcall(function()
					updateBanner()
				end)
				if not ok then
					warn(`[MissionsUi] {err}`)
				end
			end
		end
	end)
	ask("open")
	Extras.ask("open") -- the state for the campaign headers' rewards (the server sends it on join too)
end

return MissionsUi
