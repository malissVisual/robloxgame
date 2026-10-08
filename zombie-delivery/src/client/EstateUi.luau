--!strict
-- The real estate window (Config.Estate, server/Estate.luau), in the Dead End Dispatch look. Two pages in one window:
--
--   * ESTATE (H, or the ESTATE button in the HUD: EstateUi.toggleList): every property, filtered by kind (ALL,
--     HOMES, GARAGES, OFFICES, OWNED), yours marked (★ your home, OWNED), the price, the level lock (3.2: or the
--     campaign it needs, "🔒 IRON SUPPLY") and a GPS button.
--     A row opens its listing.
--   * A property's listing (the FOR SALE sign's prompt opens it through the "Estate" remote, or a row of the list):
--     name, kind, district, description, price, garage slots / couriers, the driver level, the campaign it requires
--     (3.2, EstateDef.requires: "Finish Iron Supply first"; the server says which finales you have done), the
--     sell-back value and the actions: BUY (6.12.1: from here, anywhere), SELL (asks
--     once more), SET AS HOME, SPAWN AT THE DEPOT and GPS.
--
-- The GPS goes through MapView (setWaypoint: the white GPS route on both maps, onWaypoint: the HUD's beam and label).
-- The summary strip shows your car slots (used / total), your home and how many properties you own. The server
-- answers every action with a Notice; while the window is open it shows in the subtitle too (the toasts are behind
-- the window). The money comes with the State remote, the level with the player attribute "Level".
-- While it is open the mouse is free (Main: CameraRig.mouseNeeded checks EstateUi.isOpen()).
-- 3.8 (the contract UI, design/ui-contract/): the charcoal window (Ui.window: header, ESC footer), the properties as
-- flat rows with the status column behind a fine line, the filters as flat tabs (the chosen one with a red rule).
-- 5.8, the courier phone's look (design/phone-ui/): the ZDC window header with the estate glyph, the filters as the
-- phone's square tabs (Ui.tabs: the open one raised with a red underline), the summary a slim row led by the red
-- marker, the properties as slim hairline rows (no corners; your home selected: raised, the red rule; one you own a
-- thin green rule), the facts as flat hairline cells, and BUY as the red primary action.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Levels = require(Shared.Levels)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local Missions = require(Shared.Missions)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local MapView = require(script.Parent.MapView)

local C = Ui.Colors
local K = Theme.Contract
local EstateUi = {}

-- Set by the HUD: opening this window closes the HUD's windows (one window at a time).
EstateUi.onOpen = nil :: (() -> ())?

local player = Players.LocalPlayer

local BASE_W, BASE_H = 740, 620 -- the window's design size (smaller on small screens, see updateScale)
local SUBTITLE = "Homes, garages and offices · H"
local NARROW = 600 -- below this design width: two fact columns, a slimmer row
local CONFIRM = 3 -- seconds a SELL click waits for the second one
local NOTICE_TIME = 4

type State = {
	owned: { [string]: boolean },
	home: string?,
	office: string?,
	slots: number,
	used: number,
	owners: { [string]: { string } },
	finished: { [string]: boolean }, -- 3.2: the required campaigns whose finale you have done
}

type Kind = { name: string, icon: string, color: Color3 }
local KINDS: { [string]: Kind } = {
	mansion = { name = "Mansion", icon = "🏰", color = C.yellow },
	villa = { name = "Villa", icon = "🏡", color = C.blue },
	house = { name = "House", icon = "🏠", color = C.green },
	garage = { name = "Garage", icon = "🅿️", color = C.grey },
	office = { name = "Office", icon = "🏢", color = K.text },
}
local HOME_KINDS = { mansion = true, villa = true, house = true }
local FILTERS = {
	{ id = "all", label = "ALL" },
	{ id = "homes", label = "HOMES" },
	{ id = "garage", label = "GARAGES" },
	{ id = "office", label = "OFFICES" },
	{ id = "owned", label = "OWNED" },
}
local GPS_COLOR = Theme.Gps -- the old GPS purple: a button wears its lilac face (the maps' GPS route is white)

local state: State = { owned = {}, home = nil, office = nil, slots = Config.Estate.BaseCarSlots, used = 0, owners = {}, finished = {} }
local money = 0
local remote: RemoteEvent? = nil

local gui: any = nil
local window: any = nil
local chrome: any = nil
local scale: any = nil
local subtitle: any = nil
local summary: any = nil
local listPage: any = nil
local filterTabs: Ui.Tabs? = nil -- 5.8: the filters (Ui.tabs)
local body: any = nil
local listingPage: any = nil
local designWidth = BASE_W

local page = "list" -- "list" | "listing"
local filter = "all"
local current: string? = nil -- the listing's property
local confirmSell: string? = nil
local confirmUntil = 0
local renderQueued = false

local byId: { [string]: Config.EstateDef } = {}
for _, def in Config.Estate.Properties do
	byId[def.id] = def
end

local function getRemote(): RemoteEvent
	if not remote then
		remote = Net.get("Estate")
	end
	return remote :: RemoteEvent
end

local function send(action: string, id: string?)
	getRemote():FireServer(action, id)
end

-- Is the game's interface on (after PLAY on the start screen)?
local function hudOn(): boolean
	local playerGui = player:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	return not (hud and hud:IsA("ScreenGui")) or hud.Enabled
end

local function myLevel(): number
	return tonumber(player:GetAttribute("Level")) or 1
end

-- ── The map (shared/Map.luau Map.EstatePlots, 2.6 contract; optional) ─────

local function plotOf(id: string): { x: number, z: number, district: string? }?
	local plots = (Map :: any).EstatePlots
	local plot = if type(plots) == "table" then plots[id] else nil
	if type(plot) == "table" and type(plot.x) == "number" and type(plot.z) == "number" then
		return { x = plot.x, z = plot.z, district = if type(plot.district) == "string" then plot.district else nil }
	end
	return nil
end

local function districtName(id: string?): string?
	if not id then
		return nil
	end
	for _, d in Map.Districts do
		if d.id == id then
			return d.name
		end
	end
	local words = string.gsub(id, "[_%-]", " ")
	return (string.gsub(words, "%f[%a]%a", string.upper))
end

-- ── Helpers ────────────────────────────────────────────────────────────────

local function kindOf(def: Config.EstateDef): Kind
	return KINDS[def.kind] or KINDS.house
end

local function capacity(def: Config.EstateDef): string
	if def.kind == "office" then
		return `up to {def.couriers or 0} couriers`
	elseif def.kind == "garage" then
		return `{def.garageSlots} car slots`
	end
	return `garage for {def.garageSlots}`
end

local function locked(def: Config.EstateDef): boolean
	return def.level ~= nil and myLevel() < def.level
end

-- 3.2: the name of the campaign this property still needs ("Iron Supply"), or nil.
local function needs(def: Config.EstateDef): string?
	local missing = Economy.missingCampaign(def.requires, state.finished)
	if not missing then
		return nil
	end
	local campaign = Missions.findCampaign(missing)
	return if campaign then campaign.name else missing
end

local function sellValue(def: Config.EstateDef): number
	return math.floor(def.price * Config.Estate.SellBack)
end

local function ownedCount(): number
	local count = 0
	for _ in state.owned do
		count += 1
	end
	return count
end

local noticeStamp = 0
local function say(text: string, color: Color3?)
	if not subtitle then
		return
	end
	noticeStamp += 1
	local mine = noticeStamp
	subtitle.Text = text
	subtitle.TextColor3 = color or C.yellow
	task.delay(NOTICE_TIME, function()
		if noticeStamp == mine and subtitle then
			subtitle.Text = SUBTITLE
			subtitle.TextColor3 = C.dim
		end
	end)
end

-- The GPS to a property: the white route on the maps and the HUD's beam (MapView.onWaypoint, set by the Hud).
local function setGps(def: Config.EstateDef): boolean
	local plot = plotOf(def.id)
	if not plot then
		say(`{def.name} is not on the map yet.`, C.red)
		return false
	end
	MapView.setWaypoint(Vector3.new(plot.x, Map.RoadTop, plot.z))
	local landmark: Map.Landmark = {
		id = "estate_" .. def.id,
		name = def.name,
		icon = kindOf(def).icon,
		x = plot.x,
		z = plot.z,
		kind = "place",
		description = def.description,
	}
	local ok, err = pcall(function()
		MapView.onWaypoint(landmark)
	end)
	if not ok then
		warn(`[EstateUi] GPS: {err}`)
	end
	return true
end

-- ── Building ───────────────────────────────────────────────────────────────

local render: () -> ()

local function queueRender()
	if renderQueued then
		return
	end
	renderQueued = true
	task.delay(0.2, function()
		renderQueued = false
		if window and window.Visible then
			render()
		end
	end)
end

local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera or not scale or not window then
		return
	end
	local size = camera.ViewportSize
	local s = math.clamp(math.min(size.X / 800, size.Y / 680), 0.6, 1.1)
	scale.Scale = s
	local w = math.floor(math.min(BASE_W, (size.X - 16) / s))
	local h = math.floor(math.min(BASE_H, (size.Y - 16) / s))
	window.Size = UDim2.fromOffset(w, h)
	if w ~= designWidth then
		designWidth = w
		queueRender()
	end
end

local function build()
	if gui then
		return
	end
	gui = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryEstate",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 2,
	}, player:WaitForChild("PlayerGui"))
	local content
	window, content, chrome = Ui.window(gui, "Real estate", SUBTITLE, "🏠", UDim2.fromOffset(BASE_W, BASE_H))
	window.Visible = false
	chrome.onClose = function()
		EstateUi.close()
	end
	chrome.context.Text = "H · buy from here · GPS shows the way"
	content.ClipsDescendants = true
	scale = Ui.make("UIScale", {}, window)
	subtitle = chrome.subtitle

	-- Your car slots, home, properties and money.
	-- 5.8: a slim row led by the contract's red marker (like the leaderboard's).
	summary = Ui.label(content, "", UDim2.new(1, -40, 0, 32), {
		Position = UDim2.fromOffset(20, 12),
		BackgroundTransparency = 0,
		BackgroundColor3 = K.row,
		TextSize = 14,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.HeadingFont,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.stroke(summary, K.line, 1).Transparency = Ui.HAIRLINE
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 26), PaddingRight = UDim.new(0, 12) }, summary)
	Ui.make("Frame", {
		Name = "Marker",
		Size = UDim2.fromOffset(7, 7),
		Position = UDim2.new(0, -15, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = K.red,
		BorderSizePixel = 0,
	}, summary)

	-- The list page: the filters (5.8: the phone's square tabs, 36 px tall) and the rows.
	listPage = Ui.make("Frame", { Size = UDim2.new(1, -36, 1, -60), Position = UDim2.fromOffset(18, 54), BackgroundTransparency = 1 }, content)
	local items: { Ui.TabItem } = {}
	for _, entry in FILTERS do
		table.insert(items, { id = entry.id, text = entry.label })
	end
	filterTabs = Ui.tabs(listPage, items, function(id: string)
		filter = id
		render()
	end, { selected = filter, height = 36, gap = 4, textSize = 13 })
	body = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -46),
		Position = UDim2.fromOffset(0, 46),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = K.line,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, listPage)
	Ui.list(body, true, 8)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8) }, body)

	-- The listing page: one property.
	listingPage = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -36, 1, -60),
		Position = UDim2.fromOffset(18, 54),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = K.line,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
	}, content)
	Ui.list(listingPage, true, 10)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 6) }, listingPage)

	updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
end

-- ── The list ───────────────────────────────────────────────────────────────

local function passes(def: Config.EstateDef): boolean
	if filter == "all" then
		return true
	elseif filter == "homes" then
		return HOME_KINDS[def.kind] == true
	elseif filter == "owned" then
		return state.owned[def.id] == true
	end
	return def.kind == filter
end

-- The filter tabs (5.8: Ui.tabs, built once): the chosen one raised with a red rule under it, the others quiet.
local function renderFilters()
	local tabs = filterTabs
	if tabs and tabs.selected ~= filter then
		tabs.select(filter)
	end
end

local function row(def: Config.EstateDef, order: number)
	local mine = state.owned[def.id] == true
	local isHome = state.home == def.id
	local kind = kindOf(def)
	local narrow = designWidth < NARROW
	local right = if narrow then 190 else 236 -- the status column and the GPS button
	-- A slim row (5.8: no corners, a hairline): the status column behind a fine line; your home is selected (raised,
	-- the red rule), a property you own has a thin green rule on its left. Hover / gamepad focus brightens it.
	local frame = Ui.make("TextButton", {
		Size = UDim2.new(1, -10, 0, 64),
		BackgroundColor3 = K.row,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
	}, body)
	Ui.stroke(frame, K.line, 1).Transparency = Ui.HAIRLINE
	if isHome then
		Ui.selectRow(frame, true)
	elseif mine then
		Ui.make("Frame", { Name = "Rule", Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = C.green, BorderSizePixel = 0, ZIndex = 2 }, frame)
	end
	Ui.dashes(frame, true, 6, K.rule, UDim2.new(0, 1, 1, -16), UDim2.new(1, -right - 10, 0, 8))
	Ui.tactile(frame)
	frame.Activated:Connect(function()
		EstateUi.openListing(def.id, false)
	end)
	Ui.icon(frame, "estate_" .. def.kind, kind.icon, UDim2.fromOffset(42, 42), {
		Position = UDim2.fromOffset(10, 11),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		ImageColor3 = kind.color,
	})
	Ui.label(frame, def.name, UDim2.new(1, -(62 + right), 0, 24), {
		Position = UDim2.fromOffset(62, 8),
		TextSize = 18,
		Font = Theme.DisplayFont,
		TextColor3 = C.text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local plot = plotOf(def.id)
	local district = districtName(plot and plot.district)
	Ui.label(frame, `{kind.name}{if district then " · " .. district else ""} · {capacity(def)}`, UDim2.new(1, -(62 + right), 0, 18), {
		Position = UDim2.fromOffset(62, 34),
		TextSize = 13,
		Font = Theme.Font,
		TextColor3 = C.dim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	-- The status column: the price (or OWNED / YOUR HOME) and the level lock.
	local statusW = right - 76
	local top: string
	local topColor: Color3
	local bottom: string
	local bottomColor: Color3
	if isHome then
		top, topColor = "★ YOUR HOME", C.yellow
		bottom, bottomColor = "you spawn here", C.dim
	elseif mine then
		top, topColor = "OWNED", C.green
		bottom, bottomColor = if def.kind == "office" and state.office == def.id then "your company" else `sells {Ui.money(sellValue(def))}`, C.dim
	else
		top, topColor = Ui.money(def.price), if money >= def.price then C.money else C.dim
		local story = needs(def)
		if locked(def) then
			bottom, bottomColor = `🔒 LEVEL {def.level}`, C.red
		elseif story then
			bottom, bottomColor = `🔒 {string.upper(story)}`, C.red
		else
			bottom, bottomColor = if money >= def.price then "FOR SALE" else `{Ui.money(def.price - money)} more`, C.dim
		end
	end
	Ui.label(frame, top, UDim2.fromOffset(statusW, 24), {
		Position = UDim2.new(1, -right, 0, 8),
		TextSize = 17,
		Font = Theme.DisplayFont,
		TextColor3 = topColor,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		TextScaled = true,
	})
	Ui.label(frame, bottom, UDim2.fromOffset(statusW, 18), {
		Position = UDim2.new(1, -right, 0, 34),
		TextSize = 13,
		Font = Theme.HeadingFont,
		TextColor3 = bottomColor,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local gps = Ui.button(frame, "GPS", UDim2.fromOffset(58, 36), GPS_COLOR, function()
		if setGps(def) then
			EstateUi.close()
		end
	end)
	gps.AnchorPoint = Vector2.new(1, 0.5)
	gps.Position = UDim2.new(1, -8, 0.5, 0)
	gps.TextSize = 14
end

-- The OWNED filter with nothing owned: the cheapest home and its level (from Config, not hard-coded).
local function firstHomeText(): string
	local first: Config.EstateDef? = nil
	for _, def in Config.Estate.Properties do
		if HOME_KINDS[def.kind] and (first == nil or def.price < first.price) then
			first = def
		end
	end
	if not first then
		return "Nothing yet: find the FOR SALE signs."
	end
	return `Nothing yet. Your first home could be the {first.name} (level {first.level or 1}, {Ui.money(first.price)}): find the FOR SALE signs.`
end

local function renderList()
	renderFilters()
	local scroll = body.CanvasPosition
	Ui.clear(body)
	local shown = 0
	for index, def in Config.Estate.Properties do
		if passes(def) then
			shown += 1
			row(def, index)
		end
	end
	if shown == 0 then
		Ui.label(body, if filter == "owned" then firstHomeText() else "Nothing here.", UDim2.new(1, -10, 0, 60), {
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Theme.Font,
			TextSize = 15,
		})
	end
	body.CanvasPosition = scroll
end

-- ── The listing ────────────────────────────────────────────────────────────

local listingOrder = 0
local function nextOrder(): number
	listingOrder += 1
	return listingOrder
end

local function fact(parent: any, caption: string, value: string, color: Color3, hint: string?)
	-- A stat cell (5.8: flat, square, a hairline).
	local cell = Ui.make("Frame", { BackgroundColor3 = K.row, BorderSizePixel = 0, LayoutOrder = nextOrder() }, parent)
	Ui.stroke(cell, K.line, 1).Transparency = Ui.HAIRLINE
	Ui.caps(cell, caption, UDim2.new(1, -16, 0, 16), { Position = UDim2.fromOffset(8, 6) })
	Ui.label(cell, value, UDim2.new(1, -16, 0, 24), {
		Position = UDim2.fromOffset(8, 22),
		TextSize = 20,
		Font = Theme.DisplayFont,
		TextColor3 = color,
		TextWrapped = false,
		TextScaled = true,
	})
	if hint then
		Ui.label(cell, hint, UDim2.new(1, -16, 0, 14), {
			Position = UDim2.fromOffset(8, 48),
			TextSize = 12,
			Font = Theme.Font,
			TextColor3 = C.dim,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
end

local function actionButton(parent: any, text: string, color: Color3, onClick: () -> ()): any
	local button = Ui.button(parent, text, UDim2.fromOffset(if designWidth < NARROW then 172 else 200, 44), color, onClick)
	button.TextSize = 16
	button.TextWrapped = true
	button.LayoutOrder = nextOrder()
	return button
end

local function renderListing()
	local def = if current then byId[current] else nil
	if not def then
		page = "list"
		render()
		return
	end
	Ui.clear(listingPage)
	listingOrder = 0
	local kind = kindOf(def)
	local mine = state.owned[def.id] == true
	local isHome = state.home == def.id
	local narrow = designWidth < NARROW

	-- Back to the list.
	local top = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, listingPage)
	local back = Ui.ghostButton(top, "‹  ALL PROPERTIES", UDim2.fromOffset(190, 32), nil, function()
		page = "list"
		render()
	end)
	back.TextSize = 14

	-- The name, kind, district and status.
	local hero = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 84), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, listingPage)
	Ui.icon(hero, "estate_" .. def.kind, kind.icon, UDim2.fromOffset(72, 72), {
		Position = UDim2.fromOffset(0, 6),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		ImageColor3 = kind.color,
	})
	Ui.label(hero, def.name, UDim2.new(1, -86, 0, 34), {
		Position = UDim2.fromOffset(86, 4),
		TextSize = if narrow then 22 else 28,
		Font = Theme.DisplayFont,
		TextColor3 = if isHome then C.yellow else C.text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local chips = Ui.make("Frame", { Size = UDim2.new(1, -86, 0, 24), Position = UDim2.fromOffset(86, 46), BackgroundTransparency = 1, ClipsDescendants = true }, hero)
	Ui.list(chips, false, 6)
	local function chip(text: string, color: Color3)
		local c = Ui.chip(chips, text, color)
		c.TextSize = 12
		c.LayoutOrder = nextOrder()
	end
	chip(string.upper(kind.name), kind.color)
	local plot = plotOf(def.id)
	local district = districtName(plot and plot.district)
	if district then
		chip(district, C.grey)
	end
	local story = needs(def) -- 3.2: the campaign it still needs
	if isHome then
		chip("★ YOUR HOME", C.yellow)
	elseif mine then
		chip("OWNED", C.green)
	elseif locked(def) then
		chip(`🔒 LEVEL {def.level}`, C.red)
	elseif story then
		chip(`🔒 {string.upper(story)}`, C.red)
	else
		chip("FOR SALE", C.money)
	end

	Ui.label(listingPage, def.description, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 16,
		Font = Theme.Font,
		TextColor3 = C.text,
		LayoutOrder = nextOrder(),
	})

	-- The facts.
	local facts = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nextOrder() }, listingPage)
	local columns = if narrow then 2 else 4
	Ui.make("UIGridLayout", {
		CellSize = UDim2.new(1 / columns, -8, 0, 68),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, facts)
	if mine then
		fact(facts, "BOUGHT FOR", Ui.money(def.price), C.text, nil)
	else
		fact(facts, "PRICE", Ui.money(def.price), if money >= def.price then C.money else C.red, if money >= def.price then "you can afford it" else `you have {Ui.money(money)}`)
	end
	if def.kind == "office" then
		fact(facts, "COURIERS", `up to {def.couriers or 0}`, C.text, "your delivery company")
	else
		fact(facts, "CAR SLOTS", `+{def.garageSlots}`, C.text, if def.kind == "garage" then "a garage for your cars" else `garage for {def.garageSlots}`)
	end
	local level = def.level or 1
	fact(facts, "DRIVER LEVEL", if locked(def) then `🔒 {level}` else `✓ {level}`, if locked(def) then C.red else C.green, Levels.rank(level))
	if def.requires and def.requires[1] then
		-- 3.2: the campaign it opens after (its finale done).
		local first = Missions.findCampaign(def.requires[1])
		local name = story or (if first then first.name else def.requires[1])
		fact(facts, "CAMPAIGN", if story then `🔒 {name}` else `✓ {name}`, if story then C.red else C.green, if story then "finish its finale first" else "finished")
	end
	fact(facts, "SELLS FOR", Ui.money(sellValue(def)), C.text, `{math.floor(Config.Estate.SellBack * 100 + 0.5)}% of the price`)

	-- What you can do (or why not).
	local message: string
	local messageColor = C.dim
	if isHome then
		message = "Your home: you spawn here after PLAY and every respawn, and your car comes out of its garage."
		messageColor = C.yellow
	elseif mine and def.kind == "office" then
		message = if state.office == def.id then "Your company runs from here: use the office computer (hire couriers, upgrades, COLLECT the safe)." else "Yours. Your company runs from your biggest office."
		messageColor = C.green
	elseif mine and HOME_KINDS[def.kind] then
		message = "Yours. SET AS HOME to spawn here and keep your car in its garage."
		messageColor = C.green
	elseif mine then
		message = `Yours: +{def.garageSlots} car slots.`
		messageColor = C.green
	elseif locked(def) then
		message = `Needs driver level {level} ({Levels.rank(level)}). You are level {myLevel()}: deliveries give XP.`
		messageColor = C.red
	elseif story then
		message = `Finish {story} first: {def.name} opens after its finale (MISSIONS, U).`
		messageColor = C.red
	elseif money < def.price then
		message = `You need {Ui.money(def.price - money)} more. Big jobs, night runs and your company pay best.`
	else
		message = if HOME_KINDS[def.kind] and not state.home then "Buy it and it becomes your home: you spawn here." else "Ready to buy."
		messageColor = C.money
	end
	Ui.label(listingPage, message, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 15,
		Font = Theme.HeadingFont,
		TextColor3 = messageColor,
		LayoutOrder = nextOrder(),
	})
	-- The other owners on this server (everybody owns their own copy).
	local others: { string } = {}
	local owners: { string } = state.owners[def.id] or {}
	for _, name in owners do
		if name ~= player.DisplayName then
			table.insert(others, name)
		end
	end
	if #others > 0 then
		Ui.label(listingPage, `Also owned on this server by {table.concat(others, ", ")}.`, UDim2.new(1, 0, 0, 0), {
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = 13,
			Font = Theme.Font,
			TextColor3 = C.dim,
			LayoutOrder = nextOrder(),
		})
	end
	Ui.label(listingPage, `Your cars: {state.used} of {state.slots} slots`, UDim2.new(1, 0, 0, 18), {
		TextSize = 13,
		Font = Theme.Font,
		TextColor3 = if state.used >= state.slots then C.red else C.dim,
		LayoutOrder = nextOrder(),
	})

	-- The actions.
	local actions = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nextOrder() }, listingPage)
	local layout = Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, actions)
	pcall(function()
		layout.Wraps = true
	end)
	if not mine then
		-- (6.12.1: bought from here, the phone, anywhere: no walk to the FOR SALE sign)
		local can = not locked(def) and story == nil and money >= def.price
		actionButton(actions, `BUY  {Ui.money(def.price)}`, if can then K.red else C.grey, function() -- 5.8: the red primary
			send("buy", def.id)
		end)
	else
		if HOME_KINDS[def.kind] and not isHome then
			actionButton(actions, "SET AS HOME", C.green, function()
				send("home", def.id)
			end)
		end
		if isHome then
			actionButton(actions, "SPAWN AT THE DEPOT", C.grey, function()
				send("home", "depot")
			end)
			actionButton(actions, "SELL (move out first)", C.panelLight, function()
				say("Set another home (or the depot) first, then sell.", C.red)
			end)
		else
			local asking = confirmSell == def.id and os.clock() < confirmUntil
			actionButton(actions, if asking then `SURE? SELL FOR {Ui.money(sellValue(def))}` else `SELL  {Ui.money(sellValue(def))}`, C.red, function()
				if confirmSell == def.id and os.clock() < confirmUntil then
					confirmSell = nil
					send("sell", def.id)
				else
					confirmSell = def.id
					confirmUntil = os.clock() + CONFIRM
					render()
					local mineId = def.id
					task.delay(CONFIRM + 0.05, function()
						if confirmSell == mineId and os.clock() >= confirmUntil then
							confirmSell = nil
							queueRender()
						end
					end)
				end
			end)
		end
	end
	actionButton(actions, "GPS", GPS_COLOR, function()
		if setGps(def) then
			EstateUi.close()
		end
	end)
end

-- ── Rendering ──────────────────────────────────────────────────────────────

render = function()
	if not window then
		return
	end
	local homeDef = if state.home then byId[state.home] else nil
	summary.Text = `🚗 Car slots {state.used} / {state.slots}   ·   🏠 {if homeDef then homeDef.name else "Depot"}   ·   {ownedCount()} of {#Config.Estate.Properties} owned   ·   {Ui.money(money)}`
	listPage.Visible = page == "list"
	listingPage.Visible = page == "listing"
	if page == "listing" then
		renderListing()
	else
		renderList()
	end
end

local function applyState(raw: any)
	if type(raw) ~= "table" then
		return
	end
	local owned: { [string]: boolean } = {}
	if type(raw.owned) == "table" then
		for id, on in raw.owned do
			if on == true and type(id) == "string" and byId[id] then
				owned[id] = true
			end
		end
	end
	local finished: { [string]: boolean } = {}
	if type(raw.finished) == "table" then
		for id, on in raw.finished do
			if on == true and type(id) == "string" then
				finished[id] = true
			end
		end
	end
	local owners: { [string]: { string } } = {}
	if type(raw.owners) == "table" then
		for id, names in raw.owners do
			if type(id) == "string" and type(names) == "table" then
				local list: { string } = {}
				for _, name in names do
					if type(name) == "string" then
						table.insert(list, name)
					end
				end
				owners[id] = list
			end
		end
	end
	state = {
		owned = owned,
		home = if type(raw.home) == "string" and owned[raw.home] then raw.home else nil,
		office = if type(raw.office) == "string" and owned[raw.office] then raw.office else nil,
		slots = if type(raw.slots) == "number" then raw.slots else Config.Estate.BaseCarSlots,
		used = if type(raw.used) == "number" then raw.used else 0,
		owners = owners,
		finished = finished,
	}
end

-- ── Open / close ───────────────────────────────────────────────────────────

function EstateUi.isOpen(): boolean
	return window ~= nil and window.Visible == true
end

function EstateUi.close()
	if window then
		window.Visible = false
	end
	confirmSell = nil
end

-- Opens the window on the page `setup` picks. The other windows close first (EstateUi.onOpen may close this one
-- too, which resets the page state: setup runs after it).
local function show(setup: () -> ())
	build()
	if not hudOn() then
		return
	end
	if not window.Visible then
		local onOpen = EstateUi.onOpen
		if onOpen then
			onOpen()
		end
		send("state")
	end
	setup()
	window.Visible = true
	render()
end

-- The ESTATE list (H, the HUD's ESTATE button).
function EstateUi.openList()
	show(function()
		page = "list"
		end)
end

-- A property's listing (fromSign: 6.12.1, no longer used: BUY works from anywhere).
function EstateUi.openListing(id: string, fromSign: boolean?)
	if not byId[id] then
		return
	end
	show(function()
		if current ~= id then
			confirmSell = nil
		end
		current = id
		page = "listing"
	end)
	if window and window.Visible then
		listingPage.CanvasPosition = Vector2.zero
	end
end

function EstateUi.toggleList()
	if EstateUi.isOpen() and page == "list" then
		EstateUi.close()
	else
		EstateUi.openList()
	end
end

function EstateUi.start()
	build()
	getRemote().OnClientEvent:Connect(function(open: any, raw: any)
		applyState(raw)
		if type(open) == "string" and byId[open] then
			EstateUi.openListing(open, true)
		elseif EstateUi.isOpen() then
			render()
		end
	end)
	-- The money (for the prices you can afford) comes with the game's state.
	Net.get("State").OnClientEvent:Connect(function(raw: any)
		if type(raw) == "table" and type(raw.money) == "number" and raw.money ~= money then
			money = raw.money
			if EstateUi.isOpen() then
				queueRender()
			end
		end
	end)
	player:GetAttributeChangedSignal("Level"):Connect(function()
		if EstateUi.isOpen() then
			queueRender()
		end
	end)
	-- The server's answers, in the window too (the toasts are behind it).
	Net.get("Notice").OnClientEvent:Connect(function(text: any)
		if EstateUi.isOpen() and type(text) == "string" then
			say(text, C.yellow)
		end
	end)
	-- H opens and closes the list (not while typing, e.g. in the chat). 6.12: not behind the wheel: H is the horn there
	-- (client/SoundScape.luau).
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() or input.KeyCode ~= Enum.KeyCode.H then
			return
		end
		local _, driving = require(script.Parent.Drive).seatedCar()
		if driving then
			return
		end
		if hudOn() then
			EstateUi.toggleList()
		end
	end)
	-- The interface went off (back to the start screen): the window goes too.
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = playerGui:FindFirstChild("ZombieDeliveryHud")
	if hud and hud:IsA("ScreenGui") then
		hud:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not hud.Enabled then
				EstateUi.close()
			end
		end)
	end
	send("state")
end

return EstateUi
