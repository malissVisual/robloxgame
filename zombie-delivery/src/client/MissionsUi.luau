--!strict
-- The MISSIONS window (3.0, key U and the Hud's MISSIONS button), in the Dead End Dispatch look: the ten campaigns of
-- shared/Missions.luau, a hundred story jobs, taken from anywhere.
--
--   * Left: the ten campaigns (icon, name, the client, missions done X/10, stars; a locked one says "LEVEL N").
--   * Right: the selected campaign's pitch and progress, then its ten missions as cards: the number, the name, the
--     status (locked / open / done with ★★☆), the twist chips (icon and name; hovering one shows what it does), the
--     CO-OP badge, the tier, the cargo, the lent vehicle and a pay hint. A card opens below itself: the client's
--     briefing in a speech bubble, the route, the twists explained, the rewards and START. A member of somebody
--     else's crew sees "Your crew leader picks the mission" instead (server/Missions.luau checks everything).
--   * A co-op card has FIND CREW: it puts you on the crew board (the CrewBoard remote) and opens the crew panel
--     through MissionsUi.onFindCrew (Main may wire it; without it CrewPanel.open is called directly).
--   * The header: every star you have (X / 300) and the filter tabs ALL / CO-OP.
-- Outside the window:
--   * During a mission a compact banner in the Hud's top stack (Hud.topSlot("mission")): "MISSION 3/10 · Name", the
--     twists, the CO-OP crew count and the HOLD OUT countdown. It follows your own job (the Job remote's `mission`)
--     or, for a crew member, the leader's (CrewState status.mission).
--   * When a mission is done (the Missions remote's "cleared"): a celebration card with the stars flying in, the
--     client's debrief, the rewards, a finished campaign and NEXT MISSION.
-- The window is built on the first open. The server answers START with a Notice; while the window is open it shows
-- in the subtitle too (the toasts are behind the window). While it is open the mouse is free (Main:
-- CameraRig.mouseNeeded checks MissionsUi.isOpen()).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local Missions = require(Shared.Missions)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local Hud = require(script.Parent.Hud)
local CrewPanel = require(script.Parent.CrewPanel)

type MissionDef = Missions.MissionDef
type Campaign = Missions.Campaign

local C = Ui.Colors
local GPS = Ui.Gps
local T = Config.Missions
local MissionsUi = {}

-- Set by Main: opening this window closes the others.
MissionsUi.onOpen = nil :: (() -> ())?
-- Set by Main: FIND CREW on a co-op mission opens the crew panel (CrewPanel.open); the mission id it was for.
-- Without it FIND CREW opens the crew panel itself.
MissionsUi.onFindCrew = nil :: ((missionId: string) -> ())?

local player = Players.LocalPlayer

local BASE_W, BASE_H = 900, 600 -- the window's design size (smaller on small screens, see updateScale)
local LEFT_W = 262 -- the campaign list
local TOP = 74 -- where the lists start under the header
local NOTICE_TIME = 4
local CLEARED_TIME = 22 -- seconds the celebration card stays
local DARK = Color3.fromRGB(9, 14, 11)
local TWIST_COLOR = Color3.fromRGB(64, 52, 30)
local SUBTITLE = "Ten stories · a hundred jobs · play them with your crew · U"
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

local function campaignLocked(campaign: Campaign): boolean
	return myLevel() < campaign.level
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
		if not campaignLocked(campaign) then
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
			local after = Missions.Campaigns[index + 1]
			return if after then Missions.ofCampaign(after.id)[1] else nil
		end
	end
	return nil
end

local function paintButton(button: any, text: string, color: Color3, enabled: boolean)
	local fill = if enabled then color else C.grey
	button.Text = text
	button.BackgroundColor3 = fill
	button.TextColor3 = if enabled then Theme.textOn(fill) else C.dim
	button.AutoButtonColor = false
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
	subtitle.TextColor3 = color or C.yellow
	task.delay(NOTICE_TIME, function()
		if noticeStamp == mine and refs.subtitle then
			refs.subtitle.Text = SUBTITLE
			refs.subtitle.TextColor3 = C.dim
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
	local chip = Ui.chip(parent, if compact then info.icon else `{info.icon} {info.name}`, TWIST_COLOR, C.yellow)
	chip.TextSize = 11
	chip.LayoutOrder = order or 0
	Ui.stroke(chip, C.yellow:Lerp(TWIST_COLOR, 0.5), 1)
	chip.MouseEnter:Connect(function()
		showTip(chip, `{info.icon}  {info.name}  ·  +{math.floor((info.pay - 1) * 100 + 0.5)} % pay`, info.description)
	end)
	chip.MouseLeave:Connect(function()
		hideTip(chip)
	end)
	return chip
end

local function coopChip(parent: any, order: number?): any
	local chip = Ui.chip(parent, "👥 CO-OP", GPS, Color3.new(1, 1, 1))
	chip.TextSize = 11
	chip.LayoutOrder = order or 0
	chip.MouseEnter:Connect(function()
		showTip(chip, "👥  CO-OP", `Made for a crew: every member adds +{math.floor(T.CoopPayPerMember * 100 + 0.5)} % pay and +{math.floor(T.CoopEnemyPerMember * 100 + 0.5)} % enemies. You can still play it alone.`)
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
	local size = camera.ViewportSize
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
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, parent)
	Ui.list(frame, true, gap)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 1), PaddingLeft = UDim.new(0, 1), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6) }, frame)
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
	local window = Ui.panel(gui, UDim2.fromOffset(BASE_W, BASE_H), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	window.Visible = false
	window.BackgroundTransparency = 0.04
	refs.window = window
	refs.scale = Ui.make("UIScale", {}, window)
	Ui.stroke(window, C.panelLight:Lerp(C.text, 0.2), 1)
	-- A thin dispatch-yellow line on top.
	local top = Ui.make("Frame", { Size = UDim2.new(1, -16, 0, 3), Position = UDim2.fromOffset(8, 0), BackgroundColor3 = C.yellow, BorderSizePixel = 0 }, window)
	Ui.corner(top, 2)

	-- ── The header ──
	Ui.label(window, "🎯  MISSIONS", UDim2.fromOffset(260, 44), {
		Position = UDim2.fromOffset(18, 6),
		TextSize = 26,
		Font = Theme.DisplayFont,
		TextWrapped = false,
	})
	refs.subtitle = Ui.label(window, SUBTITLE, UDim2.new(1, -40, 0, 18), {
		Position = UDim2.fromOffset(20, 46),
		TextSize = 14,
		Font = Theme.Font,
		TextColor3 = C.dim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local close = Ui.button(window, "X", UDim2.fromOffset(40, 40), C.red, function()
		MissionsUi.close()
	end)
	close.Position = UDim2.new(1, -50, 0, 8)
	refs.stars = Ui.label(window, "★ 0 / 300", UDim2.fromOffset(150, 30), {
		Position = UDim2.new(1, -210, 0, 12),
		TextSize = 22,
		Font = Theme.DisplayFont,
		TextColor3 = C.yellow,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
	local tabs = Ui.make("Frame", { Size = UDim2.fromOffset(176, 32), Position = UDim2.new(1, -400, 0, 11), BackgroundTransparency = 1 }, window)
	Ui.list(tabs, false, 8)
	refs.tabs = {}
	for order, tab in { { id = "all", text = "ALL" }, { id = "coop", text = "👥 CO-OP" } } do
		local id = tab.id
		local button = Ui.button(tabs, tab.text, UDim2.fromOffset(84, 32), C.panelLight, function()
			setFilter(id)
		end)
		button.TextSize = 14
		button.LayoutOrder = order
		refs.tabs[id] = button
	end

	-- ── The campaigns (left) and the selected campaign's missions (right) ──
	refs.campaigns = scrolling(window, UDim2.new(0, LEFT_W, 1, -(TOP + 14)), UDim2.fromOffset(14, TOP), 6)
	refs.missions = scrolling(window, UDim2.new(1, -(LEFT_W + 40), 1, -(TOP + 14)), UDim2.fromOffset(LEFT_W + 26, TOP), 8)

	-- ── The tooltip (over everything in the window) ──
	local tip = Ui.make("Frame", {
		Name = "Tooltip",
		Size = UDim2.fromOffset(280, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 50,
	}, window)
	Ui.corner(tip, 8)
	Ui.stroke(tip, C.yellow, 1)
	Ui.padding(tip, 10)
	Ui.list(tip, true, 4)
	refs.tip = tip
	refs.tipTitle = Ui.label(tip, "", UDim2.new(1, 0, 0, 18), { TextSize = 14, Font = Theme.DisplayFont, TextColor3 = C.yellow, LayoutOrder = 1, ZIndex = 51 })
	refs.tipText = Ui.label(tip, "", UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 13,
		Font = Theme.Font,
		TextColor3 = C.text,
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
	local row = Ui.make("TextButton", {
		Size = UDim2.new(1, -2, 0, 68),
		BackgroundColor3 = if selected then C.panelLight:Lerp(color, 0.18) else C.panelLight,
		BackgroundTransparency = if locked and not selected then 0.4 else 0,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
	}, refs.campaigns)
	Ui.corner(row, 8)
	Ui.stroke(row, if selected then color else C.panelLight:Lerp(C.text, 0.12), if selected then 2 else 1)
	row.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		selectCampaign(id)
	end)
	local stripe = Ui.make("Frame", { Size = UDim2.new(0, 5, 1, -16), Position = UDim2.fromOffset(6, 8), BackgroundColor3 = if locked then C.grey else color, BorderSizePixel = 0 }, row)
	Ui.corner(stripe, 3)
	Ui.label(row, campaign.icon, UDim2.fromOffset(34, 34), {
		Position = UDim2.fromOffset(16, 17),
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = if locked then 0.5 else 0,
	})
	Ui.label(row, campaign.name, UDim2.new(1, -66, 0, 20), {
		Position = UDim2.fromOffset(56, 6),
		TextSize = 16,
		Font = Theme.DisplayFont,
		TextColor3 = if locked then C.dim else C.text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.label(row, campaign.client, UDim2.new(1, -66, 0, 16), {
		Position = UDim2.fromOffset(56, 26),
		TextSize = 12,
		Font = Theme.Font,
		TextColor3 = C.dim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local line = if locked then `🔒 LEVEL {campaign.level}`
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
		TextColor3 = if locked then C.red elseif done >= total then C.yellow else C.text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local back, fill = Ui.bar(row, UDim2.new(1, -66, 0, 3), color)
	back.Position = UDim2.new(0, 56, 1, -7)
	fill.Size = UDim2.fromScale(if total > 0 then done / total else 0, 1)
end

-- ── The selected campaign ──────────────────────────────────────────────────

local function campaignHeader(campaign: Campaign, order: number)
	local color = colorOf(campaign)
	local done, total = Missions.done(progress, campaign.id)
	local got, most = Missions.stars(progress, campaign.id)
	local frame = Ui.make("Frame", {
		Size = UDim2.new(1, -2, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.panelLight:Lerp(color, 0.1),
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, refs.missions)
	Ui.corner(frame, 8)
	Ui.stroke(frame, color, 1.5)
	Ui.padding(frame, 12)
	Ui.list(frame, true, 4)
	local title = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 1 }, frame)
	Ui.label(title, `{campaign.icon}  {string.upper(campaign.name)}`, UDim2.new(1, -150, 1, 0), {
		TextSize = 22,
		Font = Theme.DisplayFont,
		TextColor3 = color:Lerp(C.text, 0.15),
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
	Ui.label(frame, campaign.client, UDim2.new(1, 0, 0, 16), { TextSize = 13, Font = Theme.HeadingFont, TextColor3 = C.dim, LayoutOrder = 2 })
	Ui.label(frame, campaign.pitch, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 14,
		Font = Theme.Font,
		TextColor3 = C.text,
		LayoutOrder = 3,
	})
	local locked = campaignLocked(campaign)
	local finished = done >= total and total > 0
	local status = if locked then `🔒 Opens at driver level {campaign.level} (you are level {myLevel()}).`
		elseif finished then `🏆 Campaign complete! The {Ui.money(campaign.reward)} campaign reward is yours.`
		else `{done}/{total} done  ·  finish all ten for {Ui.money(campaign.reward)}  ·  every new star pays {Ui.money(T.StarBonus)}`
	Ui.label(frame, status, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 13,
		Font = Theme.HeadingFont,
		TextColor3 = if locked then C.red elseif finished then C.yellow else C.money,
		LayoutOrder = 4,
	})
	local back, fill = Ui.bar(frame, UDim2.new(1, 0, 0, 6), color)
	back.LayoutOrder = 5
	fill.Size = UDim2.fromScale(if total > 0 then done / total else 0, 1)
end

-- The line under a card: the tier, the cargo, the vehicle, the pay hint, the first-clear reward.
local function cardInfo(def: MissionDef): string
	local parts = {
		string.rep("★", def.tier) .. string.rep("☆", math.max(0, 4 - def.tier)),
		`{cargoEmoji(def)} {def.items} {pieceName(def)}`,
	}
	local vehicle = vehicleName(def.vehicle)
	if vehicle then
		table.insert(parts, `🚚 {vehicle}`)
	end
	if def.timeLimit then
		table.insert(parts, `⏱ {Ui.clock(def.timeLimit)}`)
	end
	table.insert(parts, `≈ {Ui.money(payHint(def))}`)
	if best(def.id) == 0 then
		table.insert(parts, `🏁 +{Ui.money(def.reward)}`)
	end
	return table.concat(parts, "  ·  ")
end

local function selectMission(id: string)
	selectedMission = if selectedMission == id then nil else id
	render()
end

local function missionCard(def: MissionDef, campaign: Campaign, order: number)
	local color = colorOf(campaign)
	local status = statusOf(def)
	local locked = status == "locked"
	local selected = selectedMission == def.id
	local stars = best(def.id)
	local id = def.id
	local card = Ui.make("TextButton", {
		Size = UDim2.new(1, -2, 0, 88),
		BackgroundColor3 = if selected then C.panelLight:Lerp(color, 0.12) else C.panelLight,
		BackgroundTransparency = if locked and not selected then 0.4 else 0,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
	}, refs.missions)
	Ui.corner(card, 8)
	Ui.stroke(card, if selected then color elseif status == "active" then GPS else C.panelLight:Lerp(C.text, 0.12), if selected or status == "active" then 2 else 1)
	card.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		selectMission(id)
	end)
	-- The number badge: filled when done, outlined when open, grey when locked.
	local badge = Ui.make("Frame", {
		Size = UDim2.fromOffset(46, 46),
		Position = UDim2.fromOffset(12, 21),
		BackgroundColor3 = if stars > 0 then color elseif locked then C.grey else C.panel,
		BorderSizePixel = 0,
	}, card)
	Ui.corner(badge, 23)
	Ui.stroke(badge, if locked then C.grey else color, 2)
	Ui.label(badge, if locked then "🔒" else tostring(def.number), UDim2.fromScale(1, 1), {
		TextSize = if locked then 18 else 22,
		Font = Theme.DisplayFont,
		TextColor3 = if stars > 0 then Theme.textOn(color) else C.text,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Ui.label(card, if def.number == 10 then `{def.name}  ·  FINALE` else def.name, UDim2.new(1, -210, 0, 22), {
		Position = UDim2.fromOffset(70, 8),
		TextSize = 17,
		Font = Theme.DisplayFont,
		TextColor3 = if locked then C.dim else C.text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local statusText, statusColor = "OPEN", C.green
	if status == "done" then
		statusText, statusColor = Ui.stars(stars), C.yellow
	elseif status == "locked" then
		statusText, statusColor = "🔒 LOCKED", C.dim
	elseif status == "active" then
		statusText, statusColor = "▶ PLAYING", GPS:Lerp(C.text, 0.3)
	end
	Ui.label(card, statusText, UDim2.fromOffset(130, 22), {
		Position = UDim2.new(1, -142, 0, 8),
		TextSize = if status == "done" then 20 else 14,
		Font = Theme.DisplayFont,
		TextColor3 = statusColor,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
	-- The chips: the twists, the CO-OP badge.
	local chips = Ui.make("Frame", { Size = UDim2.new(1, -82, 0, 20), Position = UDim2.fromOffset(70, 35), BackgroundTransparency = 1 }, card)
	Ui.list(chips, false, 6)
	local count = 0
	for index, twist in twistsOf(def) do
		if twistChip(chips, twist, false, index) then
			count += 1
		end
	end
	if def.coop then
		coopChip(chips, 10)
		count += 1
	end
	if count == 0 then
		Ui.label(chips, "a plain delivery", UDim2.new(1, 0, 1, 0), { TextSize = 12, Font = Theme.Font, TextColor3 = C.dim })
	end
	Ui.label(card, cardInfo(def), UDim2.new(1, -82, 0, 18), {
		Position = UDim2.fromOffset(70, 62),
		TextSize = 13,
		Font = Theme.Font,
		TextColor3 = C.dim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
end

-- ── The selected mission (under its card) ──────────────────────────────────

local function detailLine(parent: any, text: string, color: Color3?, order: number, size: number?): any
	return Ui.label(parent, text, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = size or 14,
		Font = Theme.Font,
		TextColor3 = color or C.text,
		RichText = true,
		LayoutOrder = order,
	})
end

-- The client's briefing as a speech bubble: their icon on the left, the bubble pointing at it.
local function briefingBubble(parent: any, def: MissionDef, campaign: Campaign, order: number)
	local color = colorOf(campaign)
	local holder = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order }, parent)
	local avatar = Ui.make("Frame", { Size = UDim2.fromOffset(52, 52), Position = UDim2.fromOffset(0, 18), BackgroundColor3 = color, BorderSizePixel = 0 }, holder)
	Ui.corner(avatar, 26)
	Ui.stroke(avatar, color:Lerp(Color3.new(1, 1, 1), 0.4), 2)
	Ui.label(avatar, campaign.icon, UDim2.fromScale(1, 1), { TextSize = 28, TextXAlignment = Enum.TextXAlignment.Center })
	Ui.label(holder, campaign.client, UDim2.new(1, -66, 0, 16), {
		Position = UDim2.fromOffset(66, 0),
		TextSize = 12,
		Font = Theme.DisplayFont,
		TextColor3 = color:Lerp(C.text, 0.2),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	-- The bubble's tail: a small square turned 45°, under the bubble.
	Ui.make("Frame", {
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromOffset(60, 34),
		Rotation = 45,
		BackgroundColor3 = C.text,
		BorderSizePixel = 0,
	}, holder)
	local bubble = Ui.make("Frame", {
		Size = UDim2.new(1, -66, 0, 0),
		Position = UDim2.fromOffset(66, 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.text,
		BorderSizePixel = 0,
	}, holder)
	Ui.corner(bubble, 12)
	Ui.padding(bubble, 12)
	Ui.label(bubble, `“{def.briefing}”`, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		TextColor3 = DARK,
	})
	-- Room under the bubble in the holder (AutomaticSize counts the children's bottoms).
	Ui.make("UIPadding", { PaddingBottom = UDim.new(0, 2) }, holder)
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
	local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	Ui.list(row, false, 10)
	local id = def.id
	local member = crewOwner ~= nil
	local note: string? = nil
	if member then
		note = `👥 Your crew leader picks the mission ({crewOwner}). Leave the crew (K) to play your own.`
	else
		local enabled = status ~= "locked" and status ~= "active" and not ownJob
		local text = if status == "done" then "▶ PLAY AGAIN" elseif status == "active" then "▶ PLAYING" else "▶ START"
		local start = Ui.button(row, text, UDim2.fromOffset(170, 42), C.yellow, function()
			MissionsUi.startMission(id)
		end)
		start.TextSize = 17
		start.LayoutOrder = 1
		paintButton(start, text, C.yellow, enabled)
		if status == "locked" then
			note = `🔒 {why or "Locked."}`
		elseif status == "active" then
			note = "You are on this mission right now."
		elseif ownJob then
			note = "Finish your current delivery first."
		elseif table.find(twistsOf(def), "night") and workspace:GetAttribute("Night") == false then
			note = "🌙 Night only: come back after dark."
		end
	end
	if def.coop and not member then
		local find = Ui.button(row, "🔎 FIND CREW", UDim2.fromOffset(150, 42), GPS, function()
			MissionsUi.findCrew(id)
		end)
		find.TextSize = 15
		find.LayoutOrder = 2
	end
	if note then
		Ui.label(row, note, UDim2.new(1, if member then 0 elseif def.coop then -340 else -180, 1, 0), {
			LayoutOrder = 3,
			TextSize = 13,
			Font = Theme.HeadingFont,
			TextColor3 = if member then GPS:Lerp(C.text, 0.4) else C.yellow,
		})
	end
end

local function missionDetail(def: MissionDef, campaign: Campaign, order: number)
	local color = colorOf(campaign)
	local frame = Ui.make("Frame", {
		Size = UDim2.new(1, -2, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, refs.missions)
	Ui.corner(frame, 8)
	Ui.stroke(frame, color, 1.5)
	Ui.padding(frame, 12)
	Ui.list(frame, true, 8)
	briefingBubble(frame, def, campaign, 1)
	detailLine(frame, esc(def.description), C.dim, 2, 13)
	detailLine(frame, routeText(def), C.text, 3)
	-- The people, the clock, the bandits.
	local facts = { `🙋 {esc(def.giver)}  →  {esc(def.receiver)}` }
	table.insert(facts, if def.timeLimit then `⏱ RUSH: {Ui.clock(def.timeLimit)} on the clock` else "⏱ the clock goes by the distance")
	if def.banditBoost and def.banditBoost > 1 then
		table.insert(facts, `🏴 bandits want it: ×{def.banditBoost}`)
	end
	local vehicle = vehicleName(def.vehicle)
	table.insert(facts, if vehicle then `🚚 lent: {esc(vehicle)}` else "🚗 your own car")
	detailLine(frame, table.concat(facts, "   ·   "), C.dim, 4, 13)
	-- The twists, explained (touch players have no hover).
	local line = 5
	for _, twist in twistsOf(def) do
		local info = T.Twists[twist]
		if info then
			detailLine(frame, `<b>{info.icon} {info.name}</b>  {esc(info.description)}  <font color="#AADA89">+{math.floor((info.pay - 1) * 100 + 0.5)} %</font>`, C.yellow, line, 13)
			line += 1
		end
	end
	if def.coop then
		detailLine(frame, `<b>👥 CO-OP</b>  +{math.floor(T.CoopPayPerMember * 100 + 0.5)} % pay and +{math.floor(T.CoopEnemyPerMember * 100 + 0.5)} % enemies for every crew member. Playable alone; your crew earns the stars too.`, GPS:Lerp(C.text, 0.45), line, 13)
		line += 1
	end
	-- The rewards.
	local stars = best(def.id)
	local rewards = if stars > 0
		then `Best: <font color="#F5B34F">{Ui.stars(stars)}</font>  ·  {if stars < 3 then `every new star pays {Ui.money(T.StarBonus)}` else "all stars collected"}`
		else `First clear: <font color="#AADA89">{Ui.money(def.reward)}</font> + {Ui.money(T.StarBonus)} a star  ·  about {Ui.money(payHint(def))} pay  ·  ★★ cargo ≥ {math.floor(T.TwoStarCondition * 100)} %, ★★★ and {math.floor(T.ThreeStarTime * 100)} % of the clock left`
	detailLine(frame, rewards, C.text, 20, 13)
	actionRow(frame, def, 21)
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
	for id, button in refs.tabs do
		local on = filter == id
		button.BackgroundColor3 = if on then (if id == "coop" then GPS else C.yellow) else C.panelLight
		button.TextColor3 = if on then Theme.textOn(button.BackgroundColor3) else C.dim
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
			TextColor3 = C.dim,
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
		say(`Your crew leader {crewOwner} picks the mission.`, GPS:Lerp(C.text, 0.4))
		return
	end
	if ownJob then
		say("Finish your current delivery first.", C.red)
		return
	end
	local ok, why = Missions.unlocked(id, progress, myLevel())
	if not ok then
		say(why or "Locked.", C.red)
		return
	end
	pendingStart = id
	say(`Starting "{def.name}"…`, C.yellow)
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

local function buildBanner()
	-- Right under the job panel and the crew strip, above the car call line and the toasts (Hud's SLOT_ORDER).
	local slot = Hud.topSlot("mission")
	local banner = Ui.panel(slot, UDim2.new(1, 0, 0, 0), UDim2.new(), nil)
	banner.Name = "MissionBanner"
	banner.AutomaticSize = Enum.AutomaticSize.Y
	banner.Visible = false
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7) }, banner)
	Ui.stroke(banner, C.yellow, 1.5)
	Ui.list(banner, true, 3)
	refs.banner = banner
	local header = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 1 }, banner)
	refs.bannerTitle = Ui.label(header, "", UDim2.new(1, -90, 1, 0), {
		TextSize = 15,
		Font = Theme.DisplayFont,
		TextColor3 = C.yellow,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	refs.bannerCrew = Ui.label(header, "", UDim2.new(0, 90, 1, 0), {
		Position = UDim2.new(1, -90, 0, 0),
		TextSize = 14,
		Font = Theme.DisplayFont,
		TextColor3 = GPS:Lerp(C.text, 0.35),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
	refs.bannerTwists = Ui.label(banner, "", UDim2.new(1, 0, 0, 16), {
		LayoutOrder = 2,
		TextSize = 13,
		Font = Theme.HeadingFont,
		TextColor3 = C.dim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	refs.bannerDefend = Ui.label(banner, "", UDim2.new(1, 0, 0, 24), {
		LayoutOrder = 3,
		Visible = false,
		TextSize = 20,
		Font = Theme.DisplayFont,
		TextColor3 = C.red,
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
	refs.bannerTitle.Text = `{if campaign then campaign.icon else "🎯"}  MISSION {if number then `{number}/10` else ""}  ·  {name}`
	Ui.stroke(banner, if campaign then colorOf(campaign) else C.yellow, 1.5)
	local coop = mission.coop == true or (def ~= nil and def.coop == true)
	refs.bannerCrew.Text = if coop then `👥 CO-OP ×{members + 1}` else (if members > 0 then `👥 ×{members + 1}` else "")
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
	local card = Ui.panel(gui, UDim2.fromOffset(460, 0), UDim2.fromScale(0.5, 0.45), Vector2.new(0.5, 0.5))
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Visible = false
	card.BackgroundTransparency = 0.02
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
	line("clearedRibbon", 1, 14, Theme.DisplayFont, C.yellow)
	line("clearedName", 2, 26, Theme.DisplayFont, C.text)
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
			TextStrokeTransparency = 0.5,
		})
		table.insert(refs.clearedStars, star)
	end
	line("clearedBest", 4, 13, Theme.DisplayFont, C.green)
	line("clearedDebrief", 5, 16, Theme.Font, C.text)
	line("clearedRewards", 6, 15, Theme.HeadingFont, C.money)
	line("clearedCampaign", 7, 18, Theme.DisplayFont, C.yellow)
	local buttons = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, LayoutOrder = 8 }, card)
	Ui.list(buttons, false, 10, Enum.HorizontalAlignment.Center)
	refs.clearedNext = Ui.button(buttons, "NEXT MISSION ▶", UDim2.fromOffset(200, 42), C.yellow, function()
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
	local ok = Ui.button(buttons, "OK", UDim2.fromOffset(110, 42), C.panelLight:Lerp(C.text, 0.15), function()
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

-- A handful of confetti bits falling over the card (destroyed after).
local function confetti(color: Color3)
	local gui = refs.clearedGui
	if not gui then
		return
	end
	local colors = { color, C.yellow, C.green, C.blue, C.red, Color3.new(1, 1, 1) }
	local rng = Random.new()
	for index = 1, 26 do
		local bit = Ui.make("Frame", {
			Size = UDim2.fromOffset(rng:NextInteger(6, 11), rng:NextInteger(10, 16)),
			Position = UDim2.new(rng:NextNumber(0.3, 0.7), 0, 0.2, rng:NextInteger(-30, 10)),
			Rotation = rng:NextInteger(0, 180),
			BackgroundColor3 = colors[(index % #colors) + 1],
			BorderSizePixel = 0,
			ZIndex = 10,
		}, gui)
		local fall = rng:NextNumber(1.4, 2.4)
		TweenService:Create(bit, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(bit.Position.X.Scale + rng:NextNumber(-0.18, 0.18), 0, 0.9, 0),
			Rotation = bit.Rotation + rng:NextInteger(-360, 360),
			BackgroundTransparency = 1,
		}):Play()
		task.delay(fall + 0.1, function()
			bit:Destroy()
		end)
	end
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
	Ui.stroke(card, color, 2)
	refs.clearedRibbon.Text = if def then `{if campaign then campaign.icon .. "  " else ""}MISSION {def.number}/10 COMPLETE` else "MISSION COMPLETE"
	refs.clearedRibbon.TextColor3 = color:Lerp(C.text, 0.15)
	refs.clearedName.Text = esc(tostring(data.name or (def and def.name) or "Mission"))
	local newStars = tonumber(data.newStars) or 0
	local bestStars = tonumber(data.best) or stars
	refs.clearedBest.Text = if (tonumber(data.reward) or 0) > 0 then "FIRST CLEAR!"
		elseif newStars > 0 then `NEW BEST!  +{newStars} ★`
		elseif bestStars > stars then `Your best stays {Ui.stars(math.clamp(bestStars, 1, 3))}`
		else ""
	refs.clearedBest.Visible = refs.clearedBest.Text ~= ""
	refs.clearedDebrief.Text = if def then `“{esc(def.debrief)}”\n<font color="#AFBBA9" size="13">— {esc(if campaign then campaign.client else def.giver)}</font>` else ""
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
		star.TextColor3 = if earned then C.yellow else C.grey
		star.TextTransparency = 1
		star.TextStrokeTransparency = 1
		star.TextSize = 130
		star.Rotation = -40
		local delay = 0.35 + (index - 1) * 0.32
		task.delay(delay, function()
			if not star.Parent then
				return
			end
			TweenService:Create(star, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				TextSize = 60,
				Rotation = 0,
				TextTransparency = if earned then 0 else 0.3,
				TextStrokeTransparency = if earned then 0.5 else 1,
			}):Play()
		end)
	end
	card.Visible = true
	card.Position = UDim2.new(0.5, 0, 0.45, 40)
	TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.45) }):Play()
	confetti(color)
	clearedToken += 1
	local mine = clearedToken
	task.delay(CLEARED_TIME, function()
		if clearedToken == mine then
			hideCleared()
		end
	end)
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
			task.spawn(function()
				task.wait(0.2)
				local waited = 0
				while Hud.resultOpen() and waited < 120 do
					waited += task.wait(0.25)
				end
				showCleared(data)
			end)
		elseif type(kind) == "table" then
			applyState(kind)
		end
	end)
	Net.get("Job").OnClientEvent:Connect(onJob)
	Net.get("CrewState").OnClientEvent:Connect(onCrewState)
	-- The server's answers, in the window too (the toasts are behind it).
	Net.get("Notice").OnClientEvent:Connect(function(text: any)
		if refs.window and refs.window.Visible and type(text) == "string" then
			say(text, C.yellow)
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
end

return MissionsUi
