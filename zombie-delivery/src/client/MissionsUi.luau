--!strict
-- The MISSIONS window (3.0, key U, the Hud's MISSIONS button and the phone's MORE → MISSIONS), in the Dead End
-- Dispatch look.
--
-- 6.8, WHO YOU WORK FOR (the owner: "the menu is weird, I can't find my way in it; I want to see it big, with a
-- picture of who I go to for a set of missions"): the MISSIONS page is the clients (shared/Missions.luau chapters,
-- shared/Cast.luau people) and the chosen one's chapter, told as a story:
--   * Left (on a small screen: a strip on top; client/MissionsLayout.luau decides): a card per client: the portrait
--     (client/Portrait.luau: a bust of their NPC in a ViewportFrame over the chapter's colour), the name, the role and
--     the place, the chapter's progress "2 / 6" with a bar, or why it is shut ("🔒 Level 6", "🔒 Finish Raj's chapter
--     first"), and NEW / ✓ DONE / 🤝 DUO badges.
--   * Right: the chosen client big: the portrait, the name, the role and the place, the pitch, the progress; then the
--     action card: the next mission (or the one clicked on the path) with the client's briefing, the route, the twists,
--     what it pays you now ("FIRST TIME · ≈ $1,220 + 540 XP", a replay "REPLAY · ≈ $300") and the big START (PLAY
--     AGAIN for a done one; FIND CREW beside it on a co-op or DUO mission; why START would be refused under it); then
--     THE STORY: the chapter's six missions as a path (✓ done, ▶ next, 🔒 locked with "Finish 'X' first" or "Level
--     7"), each with its one-line description and its pay; then the finale's reward (money, the exclusive gun or paint
--     with its picture, the title).
--   * Only the chapter's next mission starts (server/Missions.luau checks it all again); a done one replays for a
--     quarter of the pay (Config.Missions.ReplayPay). The ALL / CO-OP filter is gone: the chips say CO-OP / DUO.
--   * Gamepad: the client cards, the path's steps and the buttons are selectable; opening the window selects START.
--   * The banner says "MISSION 3/6", the cleared card FIRST CLEAR! or "REPLAY · $X" and the chapter's next mission.
-- The older notes below describe the rest of the window (the other tabs, the banner, the cards outside it).
--
--   * (3.0 – 6.7: a campaign list on the left and ten mission cards on the right; 6.8 replaced them, see above.) A
--     member of somebody else's crew sees "Your crew leader picks the mission" (server/Missions.luau checks it all).
--   * A co-op card has FIND CREW: it puts you on the crew board (the CrewBoard remote) and opens the crew panel
--     through MissionsUi.onFindCrew (Main may wire it; without it CrewPanel.open is called directly).
--   * The header: every star you have (X / 198).
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
-- 5.8 (the courier phone's look, design/phone-ui/): the ZDC window header with the missions glyph; the page tabs and
-- the ALL / CO-OP filter are Ui.tabs (square, a red underline on the open one); the campaigns, the mission cards, the
-- open card, the challenge / package / title rows and the reward cards are slim hairline rows and cards (Extras.row:
-- no corners, no hatching, no lift; the selected one raised with the narrow red rule, a locked one sunk); the twists
-- and badges are square outlined tags; START is the red primary action (it wears the "off" face while something
-- blocks it, and FIND CREW is the red one on a DUO mission still short of a crew), EQUIP the main one; section heads
-- carry the phone's small red marker. The cleared card has the ZDC heading, a red NEXT MISSION and a plain OK.

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
local DialogKeys = require(script.Parent.DialogKeys)

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

local NOTICE_TIME = 4
local CLEARED_TIME = 22 -- seconds the celebration card stays
local SUBTITLE = `Who you work for · {#Missions.Campaigns} clients, a story each · U`
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
local selectedMission: string? = nil -- 6.8: the mission clicked on the story path (nil: the chapter's next one)
local pendingStart: string? = nil -- START was pressed for this one: the window closes when it runs
local hasState = false -- the server's state came at least once
local blindPick = false -- the window opened before it did: the first state picks the campaign again
local remote: RemoteEvent? = nil

-- The window's parts (built on the first open) and the banner's / the card's.
local refs: { [string]: any } = {}

-- 6.8: the MISSIONS page (the clients and the chosen one's chapter) lives in one table (one top-level register: the
-- file is big), with its modules: the window's measures, the portraits, the XP.
local Page = {}
Page.Layout = require(script.Parent.MissionsLayout)
Page.Portrait = require(script.Parent.Portrait)
Page.Levels = require(Shared.Levels)

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

-- "next" | "done" | "locked" (with why) | "active". 6.8: Missions.statusOf: only a chapter's next mission starts.
local function statusOf(def: MissionDef): (string, string?)
	if active == def.id or (jobMission and jobMission.id == def.id) then
		return "active", nil
	end
	return Missions.statusOf(def.id, progress, myLevel())
end

-- The chapter to show first: the first open story chapter not finished yet (else the last open one; the DUO chapter
-- is a side story you pick yourself).
local function currentCampaign(): string
	local fallback = Missions.Campaigns[1].id
	for _, campaign in Missions.Campaigns do
		if not campaign.duo then
			local state = Missions.chapterState(campaign.id, progress, myLevel())
			if state.open then
				fallback = campaign.id
				if not state.complete then
					return campaign.id
				end
			end
		end
	end
	return fallback
end

-- The mission after this one: its chapter's next (the cleared card's NEXT; the server's nextId comes first).
local function nextMission(id: string): MissionDef?
	local def = Missions.find(id)
	if not def then
		return nil
	end
	local following = Missions.nextUp(progress, def.campaign)
	return if following and following.id ~= id then following else nil
end

-- An action on (its `color`: Contract.red is the primary face, white caps) or off (the sunk disabled face, the quiet
-- text). Only the look: the click still asks (and the window says why not).
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
Extras.DUO_REFUSAL = Config.Missions.Duo.NeedsPartner -- 6.8: the server says the same (server/Missions.luau)
Extras.capacity = nil :: number? -- 3.4: the cargo slots of my equipped car (3.5: at its stage; the server's state)
Extras.carName = "car"
Extras.carId = "van" -- 3.5: my equipped car and its stage (the advice in the "too small" texts)
Extras.carStage = 0
Extras.hasCar = true -- 5.0: a vehicle of my own (the server's hasCar); the missions need one
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
-- The compact tags (5.8: the phone's outlined tags: a charcoal face, the text and its outline in the meaning's colour).
Extras.CHIP = {
	twist = { face = K.row, ink = K.text },
	coop = { face = K.row, ink = C.blue },
	duo = { face = K.charcoal, ink = P.danger },
	warn = { face = K.charcoal, ink = P.danger },
	good = { face = K.row, ink = C.green },
	gold = { face = K.row, ink = C.yellow }, -- a done mission's stars
	quiet = { face = K.recessed, ink = K.secondary },
}
-- The page tabs (5.8: Ui.tabs, plain caps like the phone's; CHALLENGES gets its count in render).
Extras.PAGES = {
	{ id = "missions", text = "MISSIONS" },
	{ id = "challenges", text = "CHALLENGES" },
	{ id = "secrets", text = "SECRETS" },
	{ id = "rewards", text = "REWARDS" },
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

-- A compact square tag that grows with its text (the twists, CO-OP, DUO, "needs N slots", EQUIPPED): `kind` is one
-- of Extras.CHIP. 5.8: the phone's outlined tag (no corners), the outline in its text's colour.
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
	Ui.stroke(chip, look.ink, 1).Transparency = if look.ink == P.danger then 0.4 else 0.65
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, chip)
	return chip
end

-- 5.8, a slim row or card like the phone's (HudContract.row): `face` (default the row surface; a locked one passes
-- Contract.recessed), square, a hairline (Ui.HAIRLINE); `line` gives the hairline a meaning's colour (an earned
-- reward, a running mission). Ui.selectRow(frame, true) then gives it the selected look (raised, the red rule).
function Extras.row(frame: GuiObject, face: Color3?, line: Color3?)
	frame.BackgroundColor3 = face or K.row
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	Ui.stroke(frame, line or K.line, 1).Transparency = if line then 0.35 else Ui.HAIRLINE
end

-- A section's small red marker (the phone's "■ ACTIVE ORDER"): a 7 px square, vertically centred at `x`.
function Extras.marker(parent: Instance, x: number, color: Color3?): any
	return Ui.make("Frame", {
		Name = "Marker",
		Size = UDim2.fromOffset(7, 7),
		Position = UDim2.new(0, x, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = color or K.red,
		BorderSizePixel = 0,
	}, parent)
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

-- A reward item's name and colour: "Maria's Carbine", "Volt Neon paint".
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

-- 3.4: the cargo slots this mission needs when my car is too small for it (it lends no vehicle), else nil. Not in
-- somebody else's crew: the leader's car does the mission (the server checks that one).
function Extras.slotsShort(def: MissionDef): number?
	local need = Economy.cargoNeed(def.load, def.items)
	local holds = Extras.capacity
	if def.vehicle or crewOwner ~= nil or need <= 0 or holds == nil or need <= holds or Extras.noCar() then
		return nil
	end
	return need
end

-- 3.4: what START says when the car is too small (the server's words).
function Extras.slotsText(need: number): string
	return `This mission needs a vehicle with {need} slots (your {Extras.carName} holds {Extras.capacity or 0}). {Economy.roomAdvice(Extras.carId, Extras.carStage, need)}`
end

-- 5.0: no vehicle of my own (you start on foot) and not in somebody else's crew: no mission can start (the server's
-- words: Config.VanQuest.MissionsNeed).
function Extras.noCar(): boolean
	return not Extras.hasCar and crewOwner == nil
end

-- 3.2: is a DUO mission short of a crew right now (not in somebody else's crew: the leader decides there)?
function Extras.needsCrew(def: MissionDef): boolean
	return def.duo == true and crewOwner == nil and Extras.crewSize < Config.Missions.Duo.MinCrew
end

-- A campaign's reward as a line: "Maria's Carbine + title “Quartermaster”" (nil for a campaign without one).
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
	-- 3.8: a flat square swatch (5.8: no corner); a fine rim (a thicker one in its own colour for the neon ones).
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

local function scrolling(parent: any, size: UDim2, position: UDim2, gap: number): any
	local frame = Ui.make("ScrollingFrame", {
		Size = size,
		Position = position,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = K.line,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		CanvasPosition = Vector2.zero,
	}, parent)
	Ui.list(frame, true, gap)
	-- Room around the rows for their hairline and the selected row's red rule.
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 8) }, frame)
	frame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		hideTip()
	end)
	return frame
end

-- 6.8: the window's measures for this screen (client/MissionsLayout.luau): its size and scale, the chrome (slimmer on
-- a small screen), and where the page's parts sit: wide, the clients in a column on the left and the chosen one's
-- chapter on the right; narrow, the clients in a strip on top and the chapter under it.
function Page.fit()
	local window, scale, chrome = refs.window, refs.scale, refs.chrome
	if not window or not scale or not chrome then
		return
	end
	local size = Ui.screenSize() -- (under the top bar: the ScreenGui does not ignore the inset)
	local layout = Page.Layout.fit(size.X, size.Y)
	local was = refs.layout
	refs.layout = layout
	scale.Scale = layout.scale
	window.Size = UDim2.fromOffset(layout.width, layout.height)
	chrome.header.Size = UDim2.new(1, 0, 0, layout.header)
	chrome.subtitle.Visible = not layout.narrow
	chrome.content.Position = UDim2.fromOffset(0, layout.header)
	chrome.content.Size = UDim2.new(1, 0, 1, -(layout.header + layout.footer))
	chrome.footer.Size = UDim2.new(1, 0, 0, layout.footer)
	chrome.footer.Position = UDim2.new(0, 0, 1, -layout.footer)
	local page = Page.Layout.pageHeight(layout)
	local top = layout.tabs
	refs.pageTabs.frame.Size = UDim2.new(1, if layout.narrow then -24 else -220, 0, top - 8)
	refs.stars.Visible = not layout.narrow
	refs.extra.Size = UDim2.new(1, -28, 0, page)
	refs.extra.Position = UDim2.fromOffset(14, top)
	local clients, list = refs.clients, refs.clientsList
	if layout.narrow then
		refs.clientsHead.Visible = false
		refs.column.Visible = false
		clients.Size = UDim2.new(1, -16, 0, layout.stripH)
		clients.Position = UDim2.fromOffset(8, top)
		clients.AutomaticCanvasSize = Enum.AutomaticSize.X
		clients.ScrollingDirection = Enum.ScrollingDirection.X
		list.FillDirection = Enum.FillDirection.Horizontal
		refs.chapter.Size = UDim2.new(1, -16, 0, page - layout.stripH - 6)
		refs.chapter.Position = UDim2.fromOffset(8, top + layout.stripH + 6)
	else
		refs.clientsHead.Visible = Extras.tab == "missions"
		refs.column.Visible = Extras.tab == "missions"
		refs.column.Size = UDim2.new(0, layout.listW + 8, 0, page + 6)
		refs.column.Position = UDim2.fromOffset(0, top - 6)
		clients.Size = UDim2.new(0, layout.listW - 8, 0, page - 30)
		clients.Position = UDim2.fromOffset(10, top + 26)
		clients.AutomaticCanvasSize = Enum.AutomaticSize.Y
		clients.ScrollingDirection = Enum.ScrollingDirection.Y
		list.FillDirection = Enum.FillDirection.Vertical
		refs.chapter.Size = UDim2.new(1, -(layout.listW + 22), 0, page)
		refs.chapter.Position = UDim2.fromOffset(layout.listW + 14, top)
	end
	hideTip()
	if was and (was.narrow ~= layout.narrow or was.text ~= layout.text) and window.Visible then
		queueRender()
	end
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
	local design = Page.Layout.Design
	local window, content, chrome = Ui.window(gui, "Missions", SUBTITLE, "🎯", UDim2.fromOffset(design.width, design.height), { glyph = "missions" })
	window.Visible = false
	refs.window = window
	refs.chrome = chrome
	refs.scale = window:FindFirstChildOfClass("UIScale") or Ui.make("UIScale", {}, window)
	refs.subtitle = chrome.subtitle
	chrome.onClose = function()
		MissionsUi.close()
	end

	-- ── The page tabs (MISSIONS | CHALLENGES | SECRETS | REWARDS; 5.8: Ui.tabs) and the stars on the right ──
	do
		local pages = Ui.tabs(content, Extras.PAGES, function(id: string)
			Extras.setTab(id)
		end, { selected = Extras.tab, gap = 6, textSize = 13 })
		pages.frame.Size = UDim2.new(1, -220, 0, 36)
		pages.frame.Position = UDim2.fromOffset(16, 6)
		refs.pageTabs = pages
	end
	refs.stars = Ui.label(content, `★ 0 / {#Missions.List * 3}`, UDim2.fromOffset(190, 36), {
		Position = UDim2.new(1, -206, 0, 6),
		TextSize = 21,
		Font = Theme.DisplayFont,
		TextColor3 = P.ink,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})

	-- ── 6.8: the clients (a sunk column on the left, or a strip on top) and the chosen one's chapter ──
	local column = Ui.make("Frame", { Name = "Column", BackgroundColor3 = K.recessed, BackgroundTransparency = 0.3, BorderSizePixel = 0 }, content)
	refs.column = column
	Ui.make("Frame", { Name = "Hairline", Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0), BackgroundColor3 = K.rule, BorderSizePixel = 0 }, column)
	local head = Ui.make("Frame", { Name = "ClientsHead", Size = UDim2.fromOffset(260, 22), Position = UDim2.fromOffset(14, 50), BackgroundTransparency = 1 }, content)
	Extras.marker(head, 0)
	refs.clientsHeadText = Ui.caps(head, "Who you work for", UDim2.new(1, -14, 1, 0), { Position = UDim2.fromOffset(14, 0), TextSize = 12, TextColor3 = P.ink2 })
	refs.clientsHead = head
	local clients = scrolling(content, UDim2.fromOffset(280, 400), UDim2.fromOffset(10, 76), 6)
	clients.Name = "Clients"
	clients.SelectionGroup = true
	refs.clients = clients
	refs.clientsList = clients:FindFirstChildOfClass("UIListLayout")
	refs.chapter = scrolling(content, UDim2.fromOffset(600, 400), UDim2.fromOffset(310, 46), 10)
	refs.chapter.Name = "Chapter"
	-- 3.1: the CHALLENGES / SECRETS / REWARDS pages (one full-width list, rebuilt by render).
	refs.extra = scrolling(content, UDim2.fromOffset(600, 400), UDim2.fromOffset(14, 46), 8)
	refs.extra.Visible = false

	-- ── The tooltip (over everything in the window): a raised square card with a hairline ──
	local tip = Ui.make("Frame", {
		Name = "Tooltip",
		Size = UDim2.fromOffset(280, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = K.raised,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 50,
	}, window)
	Ui.stroke(tip, K.line, 1).Transparency = Ui.HAIRLINE_SELECTED
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

	Page.fit()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(Page.fit)
	end
end

-- ── 6.8: the clients ──────────────────────────────────────────────────────────

-- Shows a client's chapter (its next mission in front).
function Page.select(id: string)
	if selectedCampaign == id then
		return
	end
	selectedCampaign = id
	selectedMission = nil
	blindPick = false
	render()
	if refs.chapter then
		refs.chapter.CanvasPosition = Vector2.zero
	end
end

-- The mission the chapter's action card shows: the one clicked on the story path, else the next one, else (the
-- chapter done) its finale.
function Page.focus(campaign: Campaign): MissionDef?
	local chosen = if selectedMission then Missions.find(selectedMission) else nil
	if chosen and chosen.campaign == campaign.id then
		return chosen
	end
	return Missions.nextUp(progress, campaign.id) or Missions.finale(campaign.id)
end

-- The money and XP a mission pays you now: the first time (its reward, about its pay, its XP × FirstClearXp) or a
-- replay (Missions.replayPay of about its pay). (cash, xp, replay)
function Page.payout(def: MissionDef): (number, number, boolean)
	if best(def.id) > 0 then
		return Missions.replayPay(payHint(def)), 0, true
	end
	local xp = math.floor(Page.Levels.jobXp(def.tier, def.items, 0, false, true) * T.FirstClearXp + 0.5)
	return def.reward + payHint(def), xp, false
end

-- A client's card (6.8): the portrait, the name and the role, the chapter's progress "2 / 6" (or why it is shut:
-- "🔒 Level 6", "🔒 Finish Raj's chapter first"), NEW / DONE badges. Wide: a row of the column; narrow: a card of
-- the strip. The chosen one raised with the red rule, a shut one sunk with a dimmed portrait.
function Page.clientCard(campaign: Campaign, order: number)
	local layout = refs.layout
	local state = Missions.chapterState(campaign.id, progress, myLevel())
	local color = colorOf(campaign)
	local main = Missions.clientOf(campaign.id)
	local id = campaign.id
	local h, p = layout.cardH, layout.cardPortrait
	local card = Ui.make("TextButton", {
		Name = id,
		Size = if layout.narrow then UDim2.fromOffset(layout.cardW, h) else UDim2.new(1, -2, 0, h),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
	}, refs.clients)
	Extras.row(card, if state.open then nil else K.recessed)
	if id == selectedCampaign then
		Ui.selectRow(card, true) -- raised, the narrow red rule
		refs.selectedCard = card
	end
	Ui.tactile(card)
	card.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		Page.select(id)
	end)
	local frame = Ui.make("Frame", {
		Name = "Face",
		Size = UDim2.fromOffset(p, p),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = K.charcoal,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, card)
	Ui.stroke(frame, if state.open then color else K.line, 1).Transparency = if state.open then 0.2 else Ui.HAIRLINE
	Page.Portrait.mount(frame, Page.Portrait.people(campaign.clientId, campaign.partnerId), color, { dim = not state.open })
	local x = p + 20
	-- The badge on the right: DONE, NEW, the DUO's partner.
	local badgeText, badgeKind = nil :: string?, "quiet"
	if state.complete then
		badgeText, badgeKind = "✓ DONE", "good"
	elseif campaign.duo then
		badgeText, badgeKind = "🤝 DUO", "duo"
	elseif state.new then
		badgeText, badgeKind = "NEW", "warn"
	end
	if badgeText then
		local badge = Extras.chip(card, badgeText, badgeKind)
		badge.Size = UDim2.fromOffset(0, 18)
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, -8, 0, 8)
		badge.TextSize = 11
	end
	local nameW = if badgeText then -(x + 72) else -(x + 8)
	Ui.label(card, Missions.clientName(id), UDim2.new(1, nameW, 0, 20), {
		Position = UDim2.fromOffset(x, 7),
		TextSize = if layout.narrow then 16 else 17,
		Font = Theme.DisplayFont,
		TextColor3 = if state.open then P.ink else P.ink2,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.label(card, if main then `{main.job} · {main.place}` else campaign.client, UDim2.new(1, -(x + 8), 0, 16), {
		Position = UDim2.fromOffset(x, 28),
		TextSize = layout.small,
		Font = Theme.Font,
		TextColor3 = P.ink2,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local line = if not state.open then `🔒 {state.why or "Locked"}`
		elseif state.complete then `{campaign.icon} {campaign.name} · {state.done} / {state.total}`
		else `{campaign.icon} {state.done} / {state.total} · {campaign.name}`
	Ui.label(card, line, UDim2.new(1, -(x + 8), 0, 16), {
		Position = UDim2.new(0, x, 1, -(if state.open and not state.complete then 30 else 24)),
		TextSize = layout.small,
		Font = Theme.HeadingFont,
		TextColor3 = if not state.open then P.danger elseif state.complete then C.green else P.ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if state.open and not state.complete then
		local back, fill = Ui.bar(card, UDim2.new(1, -(x + 10), 0, 4), color)
		back.Position = UDim2.new(0, x, 1, -11)
		fill.Size = UDim2.fromScale(if state.total > 0 then state.done / state.total else 0, 1)
	end
end

-- ── 6.8: the chosen client's chapter ─────────────────────────────────────────

-- The hero: the big portrait, the name, the role and the place, the pitch, the chapter's progress (or why it is shut).
function Page.hero(campaign: Campaign, order: number)
	local layout = refs.layout
	local color = colorOf(campaign)
	local state = Missions.chapterState(campaign.id, progress, myLevel())
	local main = Missions.clientOf(campaign.id)
	local got, most = Missions.stars(progress, campaign.id)
	local frame = Ui.make("Frame", {
		Name = "Hero",
		Size = UDim2.new(1, -4, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, refs.chapter)
	Extras.row(frame)
	-- (4.0.3: the content in a frame of its own: a scale-tall item in an auto-sized list grows without end)
	local body = Ui.make("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, frame)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12) }, body)
	Ui.list(body, false, 16)
	local row = body:FindFirstChildOfClass("UIListLayout")
	if row then
		row.VerticalAlignment = Enum.VerticalAlignment.Top
	end
	local face = Ui.make("Frame", {
		Name = "Portrait",
		Size = UDim2.fromOffset(layout.heroW, layout.heroH),
		BackgroundColor3 = K.charcoal,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = 1,
	}, body)
	Ui.stroke(face, if state.open then color else K.line, 1).Transparency = 0
	Page.Portrait.mount(face, Page.Portrait.people(campaign.clientId, campaign.partnerId), color, { dim = not state.open })
	local text = Ui.make("Frame", {
		Name = "Words",
		Size = UDim2.new(1, -(layout.heroW + 16), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	}, body)
	Ui.list(text, true, 4)
	local caps = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 1 }, text)
	Extras.marker(caps, 0, color)
	Ui.caps(caps, `{campaign.icon}  {campaign.name}  ·  chapter of {state.total}`, UDim2.new(1, -16, 1, 0), { Position = UDim2.fromOffset(14, 0), TextSize = layout.small, TextColor3 = P.ink2 })
	Ui.label(text, Missions.clientName(campaign.id), UDim2.new(1, 0, 0, layout.title + 4), {
		TextSize = layout.title,
		Font = Theme.DisplayFont,
		TextColor3 = P.ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
	})
	Ui.label(text, if main then `{main.job}  ·  {main.place}` else campaign.client, UDim2.new(1, 0, 0, layout.text + 4), {
		TextSize = layout.text,
		Font = Theme.HeadingFont,
		TextColor3 = color:Lerp(K.text, 0.35),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 3,
	})
	Ui.label(text, campaign.pitch, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = layout.text,
		Font = Theme.Font,
		TextColor3 = P.ink,
		LayoutOrder = 4,
	})
	local status = if not state.open then `🔒  {state.why or "Locked"}`
		elseif state.complete then `🏆  CHAPTER COMPLETE  ·  ★ {got} / {most}`
		else `{state.done} / {state.total} MISSIONS DONE  ·  ★ {got} / {most}`
	Ui.label(text, status, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = layout.small + 1,
		Font = Theme.HeadingFont,
		TextColor3 = if not state.open then P.danger elseif state.complete then C.yellow else P.ink,
		LayoutOrder = 5,
	})
	if campaign.duo then
		Ui.label(text, `🤝  NEEDS A PARTNER: every mission here needs a crew mate with you at START (invite with K). A side story: the main story never waits for it.`, UDim2.new(1, 0, 0, 0), {
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = layout.small + 1,
			Font = Theme.HeadingFont,
			TextColor3 = Extras.DUO_COLOR,
			LayoutOrder = 6,
		})
	end
	local back, fill = Ui.bar(text, UDim2.new(1, 0, 0, 4), color)
	back.LayoutOrder = 7
	fill.Size = UDim2.fromScale(if state.total > 0 then state.done / state.total else 0, 1)
end

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

-- Why START would be refused now, or nil (the server checks it all again).
function Page.blocker(def: MissionDef): string?
	local status, why = statusOf(def)
	if crewOwner then
		return `👥 Your crew leader picks the mission ({crewOwner}). Leave the crew (K) to play your own.`
	elseif status == "locked" then
		return `🔒 {why or "Locked."}`
	elseif status == "active" then
		return "You are on this mission right now."
	elseif ownJob then
		return "Finish your current delivery first."
	elseif Extras.noCar() then
		return `🚐 {Config.VanQuest.MissionsNeed}`
	elseif Extras.needsCrew(def) then
		return `🤝 {Extras.DUO_REFUSAL}`
	elseif Extras.slotsShort(def) then
		return `📦 needs {Extras.slotsShort(def)} slots: your {Extras.carName} holds {Extras.capacity or 0}.`
	elseif table.find(twistsOf(def), "night") and workspace:GetAttribute("Night") == false then
		return "🌙 Night only: it starts after dark (the clock in the top bar)."
	end
	return nil
end

-- The action card: the focused mission (the next one unless one was clicked on the path) with the client's
-- briefing, the route, the twists, what it pays you now (FIRST TIME or REPLAY) and the big START (PLAY AGAIN); a shut
-- chapter says what to do first, a finished one says so.
function Page.action(campaign: Campaign, order: number)
	local layout = refs.layout
	local color = colorOf(campaign)
	local state = Missions.chapterState(campaign.id, progress, myLevel())
	local def = Page.focus(campaign)
	refs.startButton = nil
	local frame = Ui.make("Frame", {
		Name = "Action",
		Size = UDim2.new(1, -4, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, refs.chapter)
	Extras.row(frame, K.raised, if state.open then color else nil)
	local body = Ui.make("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, frame)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 14) }, body)
	Ui.list(body, true, 8)
	if not state.open then
		-- Shut: what it waits for, and a way there.
		detailLine(body, `<b>🔒  {esc(campaign.name)} IS STILL SHUT</b>`, P.danger, 1, layout.text + 2)
		local missing = Missions.missing(campaign.id, progress)
		local first = missing[1]
		if first then
			local nextDef = Missions.nextUp(progress, first.id)
			detailLine(body, `{esc(Missions.missingText(missing))} {if nextDef then `{esc(Missions.clientName(first.id))}'s next mission is “{esc(nextDef.name)}”.` else ""}`, P.ink, 2, layout.text)
			local go = Ui.button(body, `GO TO {string.upper(Missions.clientName(first.id))} ▶`, UDim2.fromOffset(240, layout.start - 8), K.red, function()
				Page.select(first.id)
			end)
			go.TextSize = 15
			go.LayoutOrder = 3
			refs.startButton = go
		else
			detailLine(body, `It opens at driver level {campaign.level} (you are level {myLevel()}). Deliveries on the job board (J) and the other chapters give XP.`, P.ink, 2, layout.text)
		end
		return
	end
	if not def then
		return
	end
	local status = statusOf(def)
	local size = Missions.size(campaign.id)
	local stars = best(def.id)
	local finale = def.number == size
	local ribbon = if status == "active" then `▶ PLAYING · MISSION {def.number} OF {size}`
		elseif status == "done" then `✓ DONE · MISSION {def.number} OF {size} · {Ui.stars(stars)}`
		elseif status == "next" then `▶ NEXT · MISSION {def.number} OF {size}{if finale then " · THE FINALE" else ""}`
		else `🔒 MISSION {def.number} OF {size}{if finale then " · THE FINALE" else ""}`
	local caps = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 1 }, body)
	Extras.marker(caps, 0, if status == "next" then K.red else color)
	Ui.caps(caps, ribbon, UDim2.new(1, -16, 1, 0), { Position = UDim2.fromOffset(14, 0), TextSize = layout.small, TextColor3 = if status == "done" then C.green else P.ink2 })
	Ui.label(body, `{if finale then "🏆  " else ""}{def.name}`, UDim2.new(1, 0, 0, 30), {
		TextSize = layout.title - 6,
		Font = Theme.DisplayFont,
		TextColor3 = P.ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
	})
	-- The chips: the twists, CO-OP / NEEDS A PARTNER, the slots your car lacks.
	local chips = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 3 }, body)
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
	local short = Extras.slotsShort(def)
	if short then
		Extras.chip(chips, `📦 needs {short} slots`, "warn", 11)
		count += 1
	end
	if count == 0 then
		chips:Destroy()
	end
	-- The briefing in the client's words.
	local note = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, LayoutOrder = 4 }, body)
	Extras.row(note, K.charcoal)
	Ui.make("Frame", { Name = "Rule", Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 }, note)
	local words = Ui.make("Frame", { Size = UDim2.new(1, -28, 0, 0), Position = UDim2.fromOffset(16, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, note)
	Ui.list(words, true, 4)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, words)
	Ui.label(words, `“{def.briefing}”`, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = layout.text,
		Font = Theme.Font,
		TextColor3 = P.ink,
		LayoutOrder = 1,
	})
	Ui.label(words, `— {Missions.clientName(campaign.id)}`, UDim2.new(1, 0, 0, 18), {
		TextSize = layout.small + 1,
		Font = Theme.HeadingFont,
		TextColor3 = P.ink2,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		LayoutOrder = 2,
	})
	detailLine(body, routeText(def), P.ink, 5, layout.text - 1)
	-- The people, the clock, the bandits, the vehicle.
	local facts = { `🙋 {esc(def.giver)}  →  {esc(def.receiver)}`, `{cargoEmoji(def)} {def.items} {esc(pieceName(def))}` }
	table.insert(facts, if def.timeLimit then `⏱ RUSH: {Ui.clock(def.timeLimit)} on the clock` else "⏱ the clock goes by the distance")
	if def.banditBoost and def.banditBoost > 1 then
		table.insert(facts, `🏴 bandits want it: ×{def.banditBoost}`)
	end
	local vehicle = vehicleName(def.vehicle)
	local slotsNeed = Economy.cargoNeed(def.load, def.items)
	table.insert(facts, if vehicle then `🚚 lent: {esc(vehicle)}` elseif slotsNeed > 0 then `🚗 your own car · 📦 {slotsNeed} slots` else "🚗 your own car")
	-- 6.8: the danger as dots (the stars are the rating's).
	table.insert(facts, `☣ danger {string.rep("●", def.tier)}{string.rep("○", math.max(0, 4 - def.tier))}`)
	detailLine(body, table.concat(facts, "   ·   "), P.ink2, 6, layout.small + 1)
	-- The twists, explained (touch players have no hover).
	local line = 7
	local good = Extras.hex(C.money)
	for _, twist in twistsOf(def) do
		local info = T.Twists[twist]
		if info then
			detailLine(body, `<b>{info.icon} {info.name}</b>  {esc(info.description)}  <font color="{good}">+{math.floor((info.pay - 1) * 100 + 0.5)} %</font>`, P.ink, line, layout.small + 1)
			line += 1
		end
	end
	if short then
		detailLine(body, `<b>📦 needs {short} slots</b>  {esc(Extras.slotsText(short))}`, P.danger, 19, layout.small + 1)
	end
	-- What it pays you now.
	local cash, xp, replay = Page.payout(def)
	local payLine = if replay
		then `<font color="{Extras.hex(P.ink2)}"><b>REPLAY · ≈ {Ui.money(cash)}</b></font>  a quarter of the pay: no reward, no XP bonus, no unlock{if stars < 3 then `  ·  a new best ★ still pays {Ui.money(T.StarBonus)}` else ""}`
		else `<font color="{good}"><b>FIRST TIME · ≈ {Ui.money(cash)} + {xp} XP</b></font>  the reward {Ui.money(def.reward)} and about {Ui.money(payHint(def))} pay{if finale then `  ·  <font color="{Extras.hex(Extras.GOLD)}"><b>+ THE CHAPTER'S REWARD</b></font>` else ""}`
	detailLine(body, payLine, P.ink, 20, layout.text)
	-- START (PLAY AGAIN), FIND CREW on a co-op or DUO mission, and why START would be refused.
	local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, layout.start), BackgroundTransparency = 1, LayoutOrder = 21 }, body)
	Ui.list(row, false, 10)
	local blocker = Page.blocker(def)
	local member = crewOwner ~= nil
	local id = def.id
	if not member then
		local text = if status == "done" then `PLAY AGAIN ▶` elseif status == "active" then "▶ PLAYING" else "START ▶"
		local start = Ui.button(row, text, UDim2.fromOffset(if layout.narrow then 190 else 220, layout.start), K.red, function()
			MissionsUi.startMission(id)
		end)
		start.TextSize = 18
		start.LayoutOrder = 1
		paintButton(start, text, K.red, blocker == nil)
		refs.startButton = start
	end
	if (def.coop or def.duo) and not member then
		local find = Ui.button(row, "🔎 FIND CREW", UDim2.fromOffset(150, layout.start), if Extras.needsCrew(def) then K.red else P.violet, function()
			MissionsUi.findCrew(id)
		end)
		find.TextSize = 15
		find.LayoutOrder = 2
	end
	if blocker then
		detailLine(body, blocker, if member then P.violet else P.ink, 22, layout.small + 1)
	end
end

-- One step of the story path: the node (✓ done, ▶ next, 🔒 locked) on the chapter's line, the number and the name,
-- a one-line description, and what it pays you now (FIRST TIME / REPLAY) or why it waits. A click shows it in the
-- action card above.
function Page.step(def: MissionDef, campaign: Campaign, order: number, last: boolean)
	local layout = refs.layout
	local color = colorOf(campaign)
	local status, why = statusOf(def)
	local stars = best(def.id)
	local focus = Page.focus(campaign)
	local id = def.id
	local row = Ui.make("TextButton", {
		Name = id,
		Size = UDim2.new(1, -4, 0, layout.step),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
	}, refs.chapter)
	Extras.row(row, if status == "locked" then K.recessed else nil, if status == "next" then K.red else nil)
	if focus == def then
		Ui.selectRow(row, true)
	end
	Ui.tactile(row)
	row.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		selectedMission = id
		render()
		if refs.chapter then
			refs.chapter.CanvasPosition = Vector2.zero -- (the action card is on top)
		end
	end)
	-- The chapter's line through the nodes (not above the first, not below the last).
	local node = 30
	if def.number > 1 then
		Ui.make("Frame", { Size = UDim2.new(0, 2, 0.5, -node / 2), Position = UDim2.fromOffset(27, 0), BackgroundColor3 = if status == "locked" then K.track else color, BorderSizePixel = 0 }, row)
	end
	if not last then
		Ui.make("Frame", { Size = UDim2.new(0, 2, 0.5, -node / 2), Position = UDim2.new(0, 27, 0.5, node / 2), BackgroundColor3 = if status == "done" then color else K.track, BorderSizePixel = 0 }, row)
	end
	local badge = Ui.make("Frame", {
		Size = UDim2.fromOffset(node, node),
		Position = UDim2.new(0, 13, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = if status == "done" then color elseif status == "next" or status == "active" then K.red else K.recessed,
		BorderSizePixel = 0,
	}, row)
	Ui.stroke(badge, if status == "locked" then K.line else color, 1).Transparency = if status == "locked" then Ui.HAIRLINE_SELECTED else 0
	Ui.label(badge, if status == "done" then "✓" elseif status == "locked" then "🔒" else "▶", UDim2.fromScale(1, 1), {
		TextSize = if status == "locked" then 13 else 16,
		Font = Theme.DisplayFont,
		TextColor3 = if status == "done" then Theme.textOn(color) else K.text,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local x = 56
	local payW = if layout.narrow then 150 else 176
	Ui.label(row, `{def.number}.  {def.name}{if last then "  🏆" else ""}`, UDim2.new(1, -(x + payW + 8), 0, 22), {
		Position = UDim2.fromOffset(x, 9),
		TextSize = layout.text + 1,
		Font = Theme.DisplayFont,
		TextColor3 = if status == "locked" then P.ink2 else P.ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.label(row, def.description, UDim2.new(1, -(x + payW + 8), 0, 18), {
		Position = UDim2.fromOffset(x, 33),
		TextSize = layout.small + 1,
		Font = Theme.Font,
		TextColor3 = P.ink2,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	-- What it pays, or why it waits.
	local cash, xp, replay = Page.payout(def)
	local top, bottom, topColor = "", "", P.ink
	if status == "locked" then
		top, bottom, topColor = `🔒 {why or "Locked"}`, if def.number == Missions.size(campaign.id) then "the chapter's reward" else `first time ≈ {Ui.money(cash)}`, P.ink2
	elseif replay then
		top, bottom, topColor = `REPLAY {Ui.money(cash)}`, Ui.stars(stars), P.ink2
	else
		top, bottom, topColor = `FIRST TIME {Ui.money(cash)}`, `+{xp} XP{if last then " · + 🏆" else ""}`, C.money
	end
	if status == "active" then
		top, topColor = "▶ PLAYING", C.blue
	end
	Ui.label(row, top, UDim2.new(0, payW, 0, 20), {
		Position = UDim2.new(1, -(payW + 10), 0, 10),
		TextSize = if status == "locked" then layout.small else layout.small + 2,
		Font = Theme.DisplayFont,
		TextColor3 = topColor,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.label(row, bottom, UDim2.new(0, payW, 0, 18), {
		Position = UDim2.new(1, -(payW + 10), 0, 32),
		TextSize = layout.small,
		Font = Theme.HeadingFont,
		TextColor3 = if replay and status ~= "locked" then C.yellow else P.ink2,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
end

-- The finale's reward: the chapter's money and its exclusive gun or paint (its picture) and title, ✓ once yours.
function Page.finale(campaign: Campaign, order: number)
	local layout = refs.layout
	local reward = Config.Rewards.Campaigns[campaign.id]
	local earned = Extras.state.campaigns[campaign.id] == true or (Missions.done(progress, campaign.id)) >= Missions.size(campaign.id)
	local frame = Ui.make("Frame", {
		Name = "Finale",
		Size = UDim2.new(1, -4, 0, 84),
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, refs.chapter)
	Extras.row(frame, if earned then K.raised else nil, if earned then C.green else colorOf(campaign))
	local art = Ui.make("Frame", { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(10, 10), BackgroundColor3 = K.charcoal, BorderSizePixel = 0 }, frame)
	Ui.stroke(art, if reward then Extras.itemColor(reward) else C.yellow, 1).Transparency = 0
	if reward then
		Extras.itemIcon(art, reward, 48, if earned then "shown" else "dim", { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
	else
		Ui.label(art, "🏆", UDim2.fromScale(1, 1), { TextSize = 32, TextXAlignment = Enum.TextXAlignment.Center })
	end
	Ui.caps(frame, if earned then "🏆  The finale's reward  ·  ✓ yours" else "🏆  The finale's reward", UDim2.new(1, -96, 0, 16), {
		Position = UDim2.fromOffset(86, 10),
		TextSize = layout.small,
		TextColor3 = if earned then C.green else P.ink2,
	})
	local parts = { Ui.money(campaign.reward) }
	if reward then
		table.insert(parts, Extras.itemName(reward))
		table.insert(parts, `title “{reward.title}”`)
	end
	Ui.label(frame, table.concat(parts, "  +  "), UDim2.new(1, -96, 0, 0), {
		Position = UDim2.fromOffset(86, 28),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = layout.text,
		Font = Theme.DisplayFont,
		TextColor3 = if earned then P.ink else Extras.GOLD,
	})
end

-- The MISSIONS page: the clients, then the chosen one's chapter (the hero, the action card, the story path, the
-- finale's reward).
function Page.render()
	local layout = refs.layout
	refs.selectedCard = nil
	Ui.clear(refs.clients)
	local done = 0
	for order, campaign in Missions.Campaigns do
		Page.clientCard(campaign, order)
		if Missions.chapterState(campaign.id, progress, myLevel()).complete then
			done += 1
		end
	end
	refs.clientsHeadText.Text = string.upper(`Who you work for  ·  {done} / {#Missions.Campaigns} done`)
	Ui.clear(refs.chapter)
	local campaign = Missions.findCampaign(selectedCampaign) or Missions.Campaigns[1]
	Page.hero(campaign, 1)
	Page.action(campaign, 2)
	local got, total = Missions.done(progress, campaign.id)
	Extras.section(refs.chapter, "The story", `{got} / {total} done`, 3)
	local list = Missions.ofCampaign(campaign.id)
	for index, def in list do
		Page.step(def, campaign, 10 + index, index == #list)
	end
	Page.finale(campaign, 40)
	if layout.narrow and refs.selectedCard then
		-- The chosen client's card in view on the strip.
		local card = refs.selectedCard
		task.defer(function()
			local clients = refs.clients
			if card.Parent and clients then
				local s = math.max(0.01, refs.scale.Scale)
				local x = (card.AbsolutePosition.X - clients.AbsolutePosition.X) / s + clients.CanvasPosition.X
				clients.CanvasPosition = Vector2.new(math.max(0, x - 24), 0)
			end
		end)
	end
end

-- ── 3.1: the CHALLENGES / SECRETS / REWARDS pages ──────────────────────────

-- A section's heading (5.8: the phone's "■ ACTIVE ORDER"): the small red marker, the name in caps, a count on the
-- right and a thin line under it all.
function Extras.section(parent: Instance, text: string, right: string, order: number)
	local frame = Ui.make("Frame", { Size = UDim2.new(1, -2, 0, 32), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	local line = Ui.make("Frame", { Name = "Line", Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(2, 4), BackgroundTransparency = 1 }, frame)
	Extras.marker(line, 0)
	Ui.label(line, string.upper(text), UDim2.new(1, -176, 1, 0), {
		Position = UDim2.fromOffset(16, 0),
		TextSize = 15,
		Font = Theme.DisplayFont,
		TextColor3 = P.ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.caps(line, right, UDim2.fromOffset(156, 26), {
		Position = UDim2.new(1, -158, 0, 0),
		TextSize = 12,
		TextColor3 = P.ink2,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	Ui.make("Frame", { Name = "Rule", Size = UDim2.new(1, -4, 0, 1), Position = UDim2.new(0, 2, 1, -1), BackgroundColor3 = K.rule, BorderSizePixel = 0 }, frame)
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
	-- 5.8: a square card with a hairline (in its colour once earned), the raised face when it is yours.
	Extras.row(frame, if info.earned then K.raised else nil, if info.earned then color else nil)
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
	-- 5.8: a slim row (a secret one sunk); the badge a square outline (green once done).
	Extras.row(row, if secret then K.recessed else nil)
	local badge = Ui.make("Frame", {
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromOffset(12, 14),
		BackgroundColor3 = if isDone then K.raised else K.charcoal,
		BorderSizePixel = 0,
	}, row)
	Ui.stroke(badge, if isDone then C.green else K.line, 1).Transparency = if isDone then 0 else Ui.HAIRLINE_SELECTED
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
		local back, fill = Ui.bar(row, UDim2.new(1, -336, 0, 4), if isDone then C.green else K.red)
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
	Extras.row(row, if visited or found then nil else K.recessed) -- 5.8: a slim row, sunk before you have been there
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
	Extras.row(head)
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
	local back, fill = Ui.bar(head, UDim2.new(1, 0, 0, 3), K.red)
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
	Extras.row(card, if earned then K.raised else nil, if earned then color else nil)
	Ui.padding(card, 8)
	Ui.list(card, true, 3, Enum.HorizontalAlignment.Center)
	card.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		Extras.tab = "missions"
		if selectedCampaign ~= id then
			Page.select(id)
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
	Extras.row(row)
	if equipped then
		Ui.selectRow(row, true) -- the one over your head: raised, the red rule
	end
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
		local button = Ui.button(row, "EQUIP", UDim2.fromOffset(100, 36), C.yellow, function()
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
	Extras.row(card, if owned then K.raised else nil, if owned then color:Lerp(P.ink, 0.2) else nil)
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
	Extras.section(parent, "🏆  CHAPTER REWARDS", `{earned} / {#Missions.Campaigns} earned`, 1)
	Extras.note(parent, "Finish a client's chapter (its finale): its gun or paint and its title are yours, and nobody can buy them.", 2)
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
		Extras.note(parent, "No titles yet: finish a chapter, or the challenges with 🎖.", 200)
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
	if not refs.layout then
		Page.fit()
	end
	local layout = refs.layout
	-- The header.
	local got, most = Missions.stars(progress, nil)
	refs.stars.Text = `★ {got} / {most}`
	refs.chrome.context.Text = `<b>★ {got} / {most} STARS</b> · U · Who you work for, challenges, lost packages, rewards`
	-- 3.1: the page tabs; the CHALLENGES / SECRETS / REWARDS pages draw in their own list.
	do
		local page = Extras.tab
		local S = Extras.state
		local done = Extras.count(S.done)
		refs.pageTabs.select(page)
		refs.pageTabs.buttons.challenges.Text = `CHALLENGES {math.min(done, #Challenges.List)}/{#Challenges.List}`
		local missionsPage = page == "missions"
		refs.clients.Visible = missionsPage
		refs.chapter.Visible = missionsPage
		refs.column.Visible = missionsPage and not layout.narrow
		refs.clientsHead.Visible = missionsPage and not layout.narrow
		refs.extra.Visible = not missionsPage
		if not missionsPage then
			refs.stars.Text = if page == "challenges" then `🏅 {math.min(done, #Challenges.List)} / {#Challenges.List}`
				elseif page == "secrets" then `📦 {Extras.count(S.secrets)} / {math.max(S.secretsTotal, #Extras.secretList())}`
				else `🎖 {Extras.count(S.titles)} titles`
			Extras.renderPage(page)
			return
		end
	end
	-- 6.8: the clients and the chosen one's chapter.
	Page.render()
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
		local opening = not window.Visible
		if target or opening then
			local id = target or currentCampaign()
			blindPick = not target and not hasState
			if id ~= selectedCampaign then
				selectedCampaign = id
				selectedMission = nil
			end
			refs.chapter.CanvasPosition = Vector2.zero
		end
		window.Visible = true
		Page.fit()
		render()
		-- 6.8, a gamepad: START (or the chosen client) is selected, A takes it.
		if opening then
			Ui.gamepadFocus(refs.startButton or refs.selectedCard)
		end
	else
		hideTip()
		if refs.window then
			refs.window.Visible = false
			Ui.gamepadRelease(refs.window)
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
	if Extras.noCar() then
		say(Config.VanQuest.MissionsNeed, P.danger) -- 5.0: on foot
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

-- A compact charcoal scrim under the objective (5.8: square, a hairline): the campaign's colour as its edge, the
-- mission's name and the crew on top, the twists under it, HOLD OUT / the levers when they matter, and "3/10" behind a
-- fine line.
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
	Ui.stroke(banner, K.line, 1).Transparency = Ui.HAIRLINE
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
	local size = if type(mission.of) == "number" then mission.of elseif campaign then Missions.size(campaign.id) else nil
	refs.bannerNumber.Text = if number and size then `{number}/{size}` elseif number then `{number}` else "—" -- 6.8: the chapter's length
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
	-- 5.8: a square charcoal card in the phone's look: the ZDC heading with the missions glyph and a thin line under
	-- it, a hairline rim; the campaign's colour is the small square before the ribbon (set on every show).
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
	refs.clearedRim = Ui.stroke(card, K.line, 1)
	refs.clearedRim.Transparency = Ui.HAIRLINE_SELECTED
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
	-- The ZDC heading ([■ ZDC] | ☆ MISSION COMPLETE) and its thin line.
	local heading = Ui.heading(card, "Mission complete", { glyph = "missions", textSize = 16, height = 28 })
	heading.frame.LayoutOrder = -2
	Ui.make("Frame", { Name = "Rule", Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = K.rule, BorderSizePixel = 0, LayoutOrder = -1 }, card)
	line("clearedRibbon", 1, 13, Theme.HeadingFont, P.ink2)
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
	local buttons = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = 8 }, card)
	Ui.list(buttons, false, 10, Enum.HorizontalAlignment.Center)
	refs.clearedNext = Ui.button(buttons, "NEXT MISSION ▶", UDim2.fromOffset(220, 44), K.red, function()
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
	refs.clearedNext.TextSize = 15 -- (a long "NEXT: …" in caps wraps onto two lines)
	refs.clearedNext.TextWrapped = true
	local ok = Ui.ghostButton(buttons, "OK", UDim2.fromOffset(90, 44), nil, function()
		hideCleared()
	end)
	ok.LayoutOrder = 2
	-- 4.4.1: Space (Enter, the gamepad's A) closes the card like OK while it shows; the key's hint next to OK.
	Ui.label(buttons, DialogKeys.hint(), UDim2.fromOffset(0, 44), {
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.MonoFont,
		TextSize = 11,
		TextColor3 = P.ink2,
		TextWrapped = false,
		LayoutOrder = 3,
	})
	DialogKeys.watch("cleared", card, hideCleared)
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
	local swatch = `<font color="{Extras.hex(color)}">■</font>  `
	-- 6.8: the chapter's length ("MISSION 3/6").
	local size = if type(data.of) == "number" then data.of elseif def then Missions.size(def.campaign) else 0
	refs.clearedRibbon.Text = if def then `{swatch}{if campaign then esc(string.upper(campaign.name)) .. "  ·  " else ""}MISSION {def.number}/{size}` else `{swatch}MISSION`
	refs.clearedRibbon.TextColor3 = P.ink2
	refs.clearedName.Text = esc(tostring(data.name or (def and def.name) or "Mission"))
	local newStars = tonumber(data.newStars) or 0
	local bestStars = tonumber(data.best) or stars
	-- 6.8: a replay says so, with what it paid (a quarter of the pay; no reward, no XP bonus).
	local replay = data.replay == true
	refs.clearedBest.Text = if replay then `REPLAY  ·  {Ui.money(tonumber(data.paid) or 0)}{if newStars > 0 then `  ·  NEW BEST +{newStars} ★` else ""}`
		elseif data.first == true or (tonumber(data.reward) or 0) > 0 then "FIRST CLEAR!"
		elseif newStars > 0 then `NEW BEST!  +{newStars} ★`
		elseif bestStars > stars then `Your best stays {Ui.stars(math.clamp(bestStars, 1, 3))}`
		else ""
	refs.clearedBest.TextColor3 = if replay then P.ink2 else C.green
	refs.clearedBest.Visible = refs.clearedBest.Text ~= ""
	refs.clearedDebrief.Text = if def then `“{esc(def.debrief)}”\n<font color="{Extras.hex(P.ink2)}" size="14">— {esc(if campaign then Missions.clientName(campaign.id) else def.giver)}</font>` else ""
	refs.clearedDebrief.Visible = def ~= nil
	-- The rewards.
	local parts = {}
	local reward = tonumber(data.reward) or 0
	if reward > 0 then
		table.insert(parts, `First time  +{Ui.money(reward)}`)
	end
	local xp = tonumber(data.xp) or 0
	if xp > 0 then
		table.insert(parts, `First-time XP  +{xp}`)
	end
	local starBonus = tonumber(data.starBonus) or 0
	if starBonus > 0 then
		table.insert(parts, `New stars  +{Ui.money(starBonus)}`)
	end
	local campaignReward = tonumber(data.campaignReward) or 0
	if campaignReward > 0 then
		table.insert(parts, `The chapter's reward  +{Ui.money(campaignReward)}`)
	end
	refs.clearedRewards.Text = table.concat(parts, "\n")
	refs.clearedRewards.Visible = #parts > 0
	local campaignDone = if type(data.campaignDone) == "string" then data.campaignDone else nil
	refs.clearedCampaign.Text = if campaignDone then `🏆  {esc(string.upper(campaignDone))} COMPLETE!` else ""
	refs.clearedCampaign.Visible = campaignDone ~= nil
	-- NEXT MISSION (members: their leader picks; the button still opens the window there). 6.8: the chapter's next
	-- (the server's nextId: the client's progress may be a step behind); the chapter done: the clients.
	local following = if type(data.nextId) == "string" then Missions.find(data.nextId) elseif data.nextId == nil and data.of ~= nil then nil else nextMission(data.id)
	clearedNext = if following then following.id else nil
	refs.clearedNext.Text = if following then `NEXT: {following.name} ▶` else "WHO'S NEXT? ▶"
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
		Ui.stroke(card, K.line, 1).Transparency = Ui.HAIRLINE_SELECTED -- 5.8: square, a hairline; its colour the rule
		Ui.make("Frame", { Name = "Rule", Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 }, card)
		Ui.make("UIScale", { Name = "Pop", Scale = 0.97 }, card)
		-- 4.0.3: the content in a frame of its own: the rule (scale-tall) must not be an item of the card's list, or
		-- the auto-sized card grows without end (it did: a tall card with the rule down its middle that never went).
		local body = Ui.make("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, card)
		local count = if tonumber(u.count) and tonumber(u.total) then `  {u.count}/{u.total}` else ""
		if kind == "place" then
			-- A thin strip, like a toast.
			Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, body)
			-- 3.7: "discovered" is the map's banner now (client/Discovery.luau); this strip counts the places visited.
			local text = if batch then `🧭  {batch} PLACES VISITED{if count ~= "" then ` ({string.sub(count, 3)})` else ""}`
				else `🧭  PLACE VISITED: <b>{name}</b>{if count ~= "" then ` ({string.sub(count, 3)})` else ""}`
			line(body, text, 1, 15, Theme.HeadingFont, P.ink)
			return { card = card, duration = 3.5, loops = loops, color = color, big = false }
		end
		Ui.padding(body, if big then 16 else 12)
		Ui.list(body, true, if big then 6 else 4, Enum.HorizontalAlignment.Center)
		if kind == "secret" then
			line(body, if batch then `📦  {batch} LOST PACKAGES{count}` else `📦  LOST PACKAGE{count}`, 1, 21, Theme.DisplayFont, C.yellow)
			if name ~= "" and not batch then
				line(body, name, 2, 14, Theme.HeadingFont, P.ink2)
			end
			if money > 0 then
				line(body, `+{Ui.money(money)}`, 3, 21, Theme.DisplayFont, C.money)
			end
			return { card = card, duration = 4.5, loops = loops, color = color, big = false }
		elseif kind == "challenge" then
			local def = if type(u.id) == "string" then Challenges.find(u.id) else nil
			line(body, if batch then "🏅  CHALLENGES COMPLETE" else "🏅  CHALLENGE COMPLETE", 1, 14, Theme.DisplayFont, C.green)
			line(body, if batch then `{batch} challenges done` else name, 2, 23, Theme.DisplayFont, P.ink)
			if def and not batch then
				line(body, esc(def.description), 3, 14, Theme.Font, P.ink2)
			end
			if money > 0 then
				line(body, `+{Ui.money(money)}`, 4, 20, Theme.DisplayFont, C.money)
			end
			if title then
				line(body, `🎖 New title: “{title}”`, 5, 14, Theme.HeadingFont, Extras.GOLD)
			end
			line(body, `{Extras.count(Extras.state.done)}/{#Challenges.List} challenges  ·  MISSIONS (U) → CHALLENGES`, 6, 12, Theme.HeadingFont, P.ink2)
			return { card = card, duration = 5, loops = loops, color = color, big = false }
		end
		-- BIG: a campaign's reward, every lost package's, every challenge's.
		local campaign = if kind == "campaign" and type(u.id) == "string" then Missions.findCampaign(u.id) else nil
		local ribbon = if kind == "campaign" then `🏆  {string.upper(if campaign then esc(campaign.name) else name)} COMPLETE`
			elseif kind == "secrets" then "📦  EVERY LOST PACKAGE FOUND"
			elseif kind == "challenges" then "☠  EVERY CHALLENGE COMPLETE"
			else `🏆  {string.upper(name)}`
		line(body, ribbon, 1, 15, Theme.DisplayFont, P.violet)
		glowArt(body, reward, color, loops)
		line(body, "EXCLUSIVE  ·  nobody can buy this", 3, 12, Theme.DisplayFont, P.violet)
		line(body, if reward then esc(Extras.itemName(reward)) else name, 4, 30, Theme.DisplayFont, P.ink)
		if title then
			line(body, `🎖 Title: “{title}”`, 5, 16, Theme.HeadingFont, Extras.GOLD)
		end
		if money > 0 then
			line(body, `+{Ui.money(money)}`, 6, 20, Theme.DisplayFont, C.money)
		end
		local hint = if reward and reward.weapon then "Switch to it with Q, or equip it at the Gun Shop."
			elseif reward and reward.paint then "Paint a car with it at Wrench Garage."
			else ""
		line(body, `{hint}  Titles: MISSIONS (U) → REWARDS.`, 7, 12, Theme.HeadingFont, P.ink2)
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
	Extras.hasCar = data.hasCar ~= false -- 5.0 (an older server sends none: as before)
	hasState = true
	-- Opened before the first state (a slow load): pick where the player is in the story now.
	if blindPick then
		blindPick = false
		selectedCampaign = currentCampaign()
		selectedMission = nil
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
