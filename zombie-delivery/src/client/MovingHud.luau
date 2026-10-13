--!strict
-- 7.0 prototype, MOVES on the client (server/Moving.luau decides everything; shared/MovingRules.luau has the rules):
--   * the contract card (the Moving remote's "contract": the depot's board or the admin panel): the house and its
--     client, the ★ must-haves, the pay big in green, the clock and the horde, the truck lent; START (the server checks
--     it again) or why it can't start;
--   * the move's panel at the top in the middle while a move runs ("state"): the house, the clock (amber with the
--     horde, red in the last minute), the checklist (things out x/y, ★ x/3, broken), the truck's room as a bar and what
--     to do next; a tap on it (or Tab) opens the list;
--   * the list (Tab): every thing with its picture, ★, how it is carried (✋ one hand, 🙌 both, 👥 two), fragile, where
--     it is (in the house, carried by …, on the ground, in the truck) and its condition; the owner's GIVE UP;
--   * the result card ("result"): delivered / left / broken, the stars 1 … 5, the pay's lines, your share and XP;
--   * the fade at a door ("fade": client/Fade.luau);
--   * the GPS: the house, or the Wall (the depot's drop-off) while you drive with a load;
--   * the move's prompts only for its crew (the tag MovePrompt: MoveOwner = the move's owner, shown when your player
--     attribute MoveWith is theirs; MoveOnly = for that player alone; MoveSkip = not for that player), hidden by
--     their reach like client/CargoPrompts.luau.
-- On a touch screen the list ends over the touch buttons (client/TouchLayout.luau), the panel is a button.
-- Presentation only.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Map = require(Shared.Map)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)
local Fade = require(script.Parent.Fade)
local MapView = require(script.Parent.MapView)
local TouchLayout = require(script.Parent.TouchLayout)
local MoveStoryUi = require(script.Parent.MoveStoryUi) -- MoveStory hook (7.0 story): the intro, the briefing, CHAPTERS, the thanks

local MovingHud = {}

local player = Players.LocalPlayer
local K = Theme.Contract
local C = CardKit.Color
local TAG = "MovePrompt"
local ORANGE = Color3.fromRGB(240, 132, 44)
local PANEL_W = 380
local LIST_W = 320
local CARD_W = 440

local remote = Net.get("Moving")
local gui: ScreenGui? = nil
local state: any = nil -- the server's view of your move (nil: none)
local refs: { [string]: any } = {} -- the panel's labels and bars
local listFrame: any = nil
local listOpen = false
local cardFrame: any = nil -- the contract card or the result (one at a time)
local gpsAt: Vector3? = nil -- the waypoint set here (cleared here)
local hidden: { [ProximityPrompt]: number } = {} -- the move prompts hidden for you, with their reach

-- ── Small helpers ──────────────────────────────────────────────────────────

local function screen(): ScreenGui?
	if gui and gui.Parent then
		return gui
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local made = Ui.make("ScreenGui", {
		Name = "MovingHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 7,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	gui = made
	return made
end

local function text(parent: Instance, value: string, size: UDim2, props: { [string]: any }): any
	local label = Ui.label(parent, value, size, { Font = Theme.Font, TextSize = 14, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	for key, prop in props do
		label[key] = prop
	end
	return label
end

local function scaled(frame: Instance)
	Ui.make("UIScale", { Name = "Scale", Scale = Ui.screenScale() }, frame)
end

local function sound(name: string)
	pcall(function()
		(require(script.Parent.Sounds) :: any).play(name, 0.7)
	end)
end

local function clock(seconds: number): string
	return Ui.clock(math.max(0, seconds))
end

local CLASS_TEXT: { [string]: string } = { hand = "✋ one hand", both = "🙌 both hands", pair = "👥 two people" }
local STATE_TEXT: { [string]: string } = { home = "IN THE HOUSE", carried = "CARRIED", ground = "ON THE GROUND", truck = "IN THE TRUCK" }

-- ── The prompts of your move only ──────────────────────────────────────────

local function shows(prompt: ProximityPrompt): boolean
	local only = prompt:GetAttribute("MoveOnly")
	if type(only) == "number" then
		return only == player.UserId
	end
	if prompt:GetAttribute("MoveSkip") == player.UserId then
		return false
	end
	local owner = prompt:GetAttribute("MoveOwner")
	return type(owner) ~= "number" or owner == player.UserId or player:GetAttribute("MoveWith") == owner
end

local function apply(prompt: ProximityPrompt)
	if shows(prompt) then
		local reach = hidden[prompt]
		if reach then
			hidden[prompt] = nil
			if prompt.MaxActivationDistance == 0 then
				prompt.MaxActivationDistance = reach
			end
		end
	elseif not hidden[prompt] and prompt.MaxActivationDistance > 0 then
		hidden[prompt] = prompt.MaxActivationDistance
		prompt.MaxActivationDistance = 0
	end
end

local function applyAll()
	for _, instance in CollectionService:GetTagged(TAG) do
		if instance:IsA("ProximityPrompt") then
			apply(instance)
		end
	end
end

local function watchPrompts()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance: Instance)
		if instance:IsA("ProximityPrompt") then
			apply(instance)
			-- (MoveSkip / MoveOnly change as the thing changes hands)
			instance.AttributeChanged:Connect(function()
				apply(instance)
			end)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance: Instance)
		if instance:IsA("ProximityPrompt") then
			hidden[instance] = nil
		end
	end)
	for _, instance in CollectionService:GetTagged(TAG) do
		if instance:IsA("ProximityPrompt") then
			apply(instance)
			instance.AttributeChanged:Connect(function()
				apply(instance)
			end)
		end
	end
	player:GetAttributeChangedSignal("MoveWith"):Connect(applyAll)
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if CollectionService:HasTag(prompt, TAG) and not shows(prompt) then
			hidden[prompt] = nil
			apply(prompt)
		end
	end)
end

-- ── The GPS ────────────────────────────────────────────────────────────────

local function setGps(at: Vector3?, name: string?, icon: string?)
	if at == nil then
		if gpsAt then
			gpsAt = nil
			MapView.setWaypoint(nil)
			pcall(function()
				MapView.onWaypoint(nil)
			end)
		end
		return
	end
	local current = gpsAt
	if current and (current - at).Magnitude < 1 then
		return
	end
	gpsAt = at
	MapView.setWaypoint(at)
	pcall(function()
		MapView.onWaypoint({ id = "move", name = name or "Move", icon = icon or "🏠", x = at.X, z = at.Z, kind = "shop", description = "" } :: any)
	end)
end

local function seated(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

-- The house, or the Wall while you drive with a load (or the horde is on and something is in).
local function updateGps()
	local s = state
	if type(s) ~= "table" then
		setGps(nil)
		return
	end
	local counts = s.counts or {}
	local out = tonumber(counts.out) or 0
	if out > 0 and (seated() or s.horde == true) then
		setGps(Vector3.new(s.dropOff.x, Map.RoadTop, s.dropOff.z), "The Wall (drop-off)", "🧱")
	else
		setGps(Vector3.new(s.house.x, Map.RoadTop, s.house.z), s.name, s.icon)
	end
end

-- ── The panel ──────────────────────────────────────────────────────────────

local toggleList: () -> ()

local function buildPanel(root: ScreenGui)
	local panel = Ui.make("TextButton", {
		Name = "MovePanel",
		Size = UDim2.fromOffset(PANEL_W, 98),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
	}, root)
	scaled(panel)
	Ui.corner(panel, 8)
	Ui.make("UIStroke", { Name = "Edge", Color = ORANGE, Thickness = 1, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
	refs.panel = panel
	refs.edge = panel:FindFirstChild("Edge")
	refs.title = text(panel, "", UDim2.new(1, -120, 0, 20), { Position = UDim2.fromOffset(12, 8), Font = Theme.HeadingFont, TextSize = 15, TextColor3 = C.title })
	refs.timer = text(panel, "", UDim2.fromOffset(100, 24), { Position = UDim2.new(1, -12, 0, 6), AnchorPoint = Vector2.new(1, 0), Font = Theme.HeadingFont, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Right })
	refs.check = text(panel, "", UDim2.new(1, -110, 0, 18), { Position = UDim2.fromOffset(12, 32), TextColor3 = K.secondary })
	refs.hint = text(panel, Ui.touchLayout() and "TAP: LIST" or "LIST [TAB]", UDim2.fromOffset(96, 16), {
		Position = UDim2.new(1, -12, 0, 34),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = C.faint,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	refs.truckLabel = text(panel, "", UDim2.fromOffset(110, 16), { Position = UDim2.fromOffset(12, 54), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = K.secondary })
	local track = Ui.make("Frame", { Name = "Track", Size = UDim2.new(1, -136, 0, 8), Position = UDim2.fromOffset(124, 58), BackgroundColor3 = K.track, BorderSizePixel = 0 }, panel)
	Ui.corner(track, 4)
	refs.fill = Ui.make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = ORANGE, BorderSizePixel = 0 }, track)
	Ui.corner(refs.fill, 4)
	refs.next = text(panel, "", UDim2.new(1, -24, 0, 18), { Position = UDim2.fromOffset(12, 74), TextSize = 13, TextColor3 = K.text })
	panel.Activated:Connect(function()
		toggleList()
	end)
end

-- What to do now, from the state.
local function nextStep(s: any): string
	local counts = s.counts or {}
	local out, total = tonumber(counts.out) or 0, tonumber(counts.total) or 0
	local carried = tonumber(counts.carried) or 0
	if s.horde == true then
		return if out > 0 then "🧟 THE HORDE! Drive the truck to the Wall NOW" else "🧟 THE HORDE! Load something and get out"
	end
	if s.inside == true then
		return if carried > 0 then "Carry it out: \"Leave house\" by the front door" else "Pick up the things (E) · ★ first"
	end
	if carried > 0 then
		return if s.backOpen == true then "Load it at the truck's back (E)" else "Open the truck's back (E), then Load"
	end
	if out >= total and total > 0 then
		return "Everything is in: drive to the Wall at the depot"
	end
	if seated() then
		return if out > 0 then "Drive to the Wall (GPS), or back for more" else `Drive to {s.name} (GPS)`
	end
	return `"Enter house" at {s.name}'s front door`
end

local function refreshPanel()
	local panel = refs.panel
	if not panel then
		return
	end
	local s = state
	panel.Visible = type(s) == "table"
	if type(s) ~= "table" then
		return
	end
	local nowAt = workspace:GetServerTimeNow()
	local left = (tonumber(s.endsAt) or nowAt) - nowAt
	local hordeIn = (tonumber(s.hordeAt) or nowAt) - nowAt
	local counts = s.counts or {}
	refs.title.Text = `{s.icon or "🏠"} {string.upper(s.name or "MOVE")}{if s.mine == true then "" else ` · {s.owner}'s move`}`
	refs.timer.Text = `⏱ {clock(left)}`
	refs.timer.TextColor3 = if left <= 60 then K.red elseif s.horde == true then K.warn else K.text
	local broken = tonumber(counts.broken) or 0
	refs.check.Text = `📦 {counts.out or 0}/{counts.total or 0} out · ★ {counts.starsOut or 0}/{counts.stars or 0}{if broken > 0 then ` · 💥 {broken}` else ""}{if s.horde ~= true and hordeIn > 0 then ` · 🧟 in {clock(hordeIn)}` else ""}`
	local fill = math.clamp(tonumber(s.fill) or 0, 0, 1)
	refs.truckLabel.Text = `🚚 TRUCK {math.floor(fill * 100 + 0.5)}%`
	refs.fill.Size = UDim2.fromScale(fill, 1)
	refs.fill.BackgroundColor3 = if fill > 0.9 then K.red elseif fill > 0.7 then K.warn else ORANGE
	refs.next.Text = nextStep(s)
	refs.next.TextColor3 = if s.horde == true then K.red else K.text
	if refs.edge then
		refs.edge.Color = if s.horde == true then K.red else ORANGE
	end
end

-- ── The list (Tab) ─────────────────────────────────────────────────────────

-- The list's top and height (unscaled px): under the panel, over the touch buttons on a touch screen.
local function listBox(): (number, number)
	local size = Ui.screenSize()
	local s = Ui.screenScale()
	local top = 8 + 98 * s + 10
	local bottom = size.Y - 120
	if Ui.touchLayout() then
		local cluster = TouchLayout.cluster(size.X, size.Y, s)
		bottom = math.min(bottom, cluster.top - TouchLayout.GAP)
	end
	return top, math.max(160, (bottom - top) / s)
end

local function itemRow(parent: Instance, item: any, order: number)
	local row = Ui.make("Frame", { Name = `Item{item.spot}`, Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = C.card, BorderSizePixel = 0, LayoutOrder = order }, parent)
	Ui.corner(row, 6)
	local accent = if item.broken == true then K.red elseif item.state == "truck" then K.good elseif item.star == true then C.gold else K.rule
	Ui.make("Frame", { Name = "Accent", Size = UDim2.new(0, 3, 1, -12), Position = UDim2.fromOffset(4, 6), BackgroundColor3 = accent, BorderSizePixel = 0 }, row)
	text(row, tostring(item.icon or "📦"), UDim2.fromOffset(36, 36), { Position = UDim2.fromOffset(12, 8), TextSize = 26, Font = Theme.Font, TextXAlignment = Enum.TextXAlignment.Center })
	text(row, `{item.name}{if item.star == true then " ★" else ""}`, UDim2.new(1, -150, 0, 18), {
		Position = UDim2.fromOffset(54, 7),
		Font = Theme.HeadingFont,
		TextSize = 14,
		TextColor3 = if item.star == true then C.gold else K.text,
	})
	local facts = CLASS_TEXT[item.class] or ""
	if item.fragile == true then
		facts ..= " · fragile"
	end
	text(row, facts, UDim2.new(1, -150, 0, 16), { Position = UDim2.fromOffset(54, 28), TextSize = 12, TextColor3 = C.faint })
	local where = STATE_TEXT[item.state] or ""
	if item.state == "carried" and type(item.by) == "string" then
		where = if item.mine == true then "IN YOUR HANDS" else `CARRIED · {string.upper(item.by)}`
	end
	text(row, where, UDim2.fromOffset(92, 16), {
		Position = UDim2.new(1, -8, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.HeadingFont,
		TextSize = 10,
		TextColor3 = if item.state == "truck" then K.good elseif item.state == "carried" then ORANGE else K.secondary,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local condition = math.floor((tonumber(item.condition) or 1) * 100 + 0.5)
	text(row, if item.broken == true then "BROKEN" else `{condition}%`, UDim2.fromOffset(92, 18), {
		Position = UDim2.new(1, -8, 0, 26),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.HeadingFont,
		TextSize = 14,
		TextColor3 = if item.broken == true then K.red elseif condition < 60 then K.warn else K.text,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
end

local function closeList()
	listOpen = false
	if listFrame then
		listFrame:Destroy()
		listFrame = nil
	end
end

local function drawList()
	local root = screen()
	local s = state
	if not root or type(s) ~= "table" then
		closeList()
		return
	end
	local scroll = listFrame and listFrame:FindFirstChild("Rows")
	local keep = if scroll then scroll.CanvasPosition else Vector2.zero
	if listFrame then
		listFrame:Destroy()
	end
	local top, height = listBox()
	local frame = Ui.make("Frame", {
		Name = "MoveList",
		Size = UDim2.fromOffset(LIST_W, height),
		Position = UDim2.new(1, -16, 0, top),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.WindowTransparency,
		BorderSizePixel = 0,
		Active = true,
	}, root)
	scaled(frame)
	Ui.corner(frame, 8)
	Ui.make("UIStroke", { Color = K.rule, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
	listFrame = frame
	text(frame, `{s.icon or "🏠"} {string.upper(s.name or "")} · THINGS`, UDim2.new(1, -60, 0, 22), { Position = UDim2.fromOffset(12, 10), Font = Theme.HeadingFont, TextSize = 14, TextColor3 = C.title })
	local counts = s.counts or {}
	text(frame, `★ must-haves first · {counts.out or 0} of {counts.total or 0} in the truck`, UDim2.new(1, -60, 0, 16), { Position = UDim2.fromOffset(12, 32), TextSize = 12, TextColor3 = C.faint })
	Ui.closeButton(frame, function()
		closeList()
	end)
	local footer = if s.mine == true then 52 else 0
	local rows = Ui.make("ScrollingFrame", {
		Name = "Rows",
		Size = UDim2.new(1, -16, 1, -(58 + footer)),
		Position = UDim2.fromOffset(8, 54),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, frame)
	Ui.list(rows, true, 6)
	local list = s.items or {}
	-- ★ first, then what is still in the house, then the rest
	local ordered = table.clone(list)
	local rank: { [string]: number } = { carried = 0, ground = 1, home = 2, truck = 3 }
	table.sort(ordered, function(a: any, b: any): boolean
		if (a.star == true) ~= (b.star == true) then
			return a.star == true
		end
		local ra, rb = rank[a.state] or 4, rank[b.state] or 4
		if ra ~= rb then
			return ra < rb
		end
		return (tonumber(a.spot) or 0) < (tonumber(b.spot) or 0)
	end)
	for index, item in ordered do
		itemRow(rows, item, index)
	end
	rows.CanvasPosition = keep
	if s.mine == true then
		local holder = Ui.make("Frame", { Name = "Footer", Size = UDim2.new(1, -24, 0, 40), Position = UDim2.new(0, 12, 1, -46), BackgroundTransparency = 1 }, frame)
		CardKit.bigButton(holder, {
			name = "GiveUp",
			text = "GIVE UP THE MOVE",
			kind = "shut",
			height = 40,
			textSize = 14,
			onClick = function()
				remote:FireServer("giveup")
			end,
		})
	end
end

toggleList = function()
	if listOpen then
		closeList()
	elseif type(state) == "table" then
		listOpen = true
		drawList()
	end
end

-- ── The cards: the contract, the result ────────────────────────────────────

local function closeCard()
	if cardFrame then
		cardFrame:Destroy()
		cardFrame = nil
	end
end

-- A dimmed backdrop and a card in the middle; returns the card's body (a vertical list).
local function cardShell(name: string, accent: Color3): any
	closeCard()
	local root = screen()
	if not root then
		return nil
	end
	local backdrop = Ui.make("TextButton", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 20,
	}, root)
	cardFrame = backdrop
	local card = Ui.make("Frame", {
		Name = "Card",
		Size = UDim2.fromOffset(CARD_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = K.charcoal,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 21,
	}, backdrop)
	scaled(card)
	Ui.corner(card, 12)
	Ui.make("UIStroke", { Color = accent, Thickness = 1, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 16) }, card)
	-- the words in a list; the close button over its top right corner (not one of the list's rows)
	local body = Ui.make("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 21 }, card)
	Ui.list(body, true, 8)
	local close = Ui.closeButton(card, closeCard)
	close.Position = UDim2.new(1, 10, 0, -8)
	close.ZIndex = 23
	return body
end

local function line(parent: Instance, value: string, order: number, props: { [string]: any }?): any
	local label = Ui.label(parent, value, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = K.secondary,
		TextWrapped = true,
		LayoutOrder = order,
		ZIndex = 22,
	})
	if props then
		for key, prop in props do
			label[key] = prop
		end
	end
	return label
end

local function chipRow(parent: Instance, order: number, chips: { string })
	local strip = Ui.make("Frame", { Name = "Chips", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 22 }, parent)
	local layout = Ui.make("UIGridLayout", { CellSize = UDim2.fromOffset(196, 26), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, strip)
	local _ = layout
	for index, value in chips do
		local chip = CardKit.chip(strip, { name = `Chip{index}`, text = value, order = index, static = true, stroke = K.rule })
		chip.ZIndex = 22
		chip.TextXAlignment = Enum.TextXAlignment.Center
	end
end

local function showContract(card: any)
	if type(card) ~= "table" then
		return
	end
	-- MoveStory hook: the first board ever opens on Marge's intro (client/MoveStoryUi.luau), this card after it
	if MoveStoryUi.intro(function()
		showContract(card)
	end) then
		return
	end
	local body = cardShell("MoveContract", ORANGE)
	if not body then
		return
	end
	line(body, "ZDC MOVING · CONTRACT", 1, { Font = Theme.HeadingFont, TextSize = 12, TextColor3 = ORANGE })
	line(body, `{card.icon or "🏠"} {string.upper(tostring(card.name))}`, 2, { Font = Theme.HeadingFont, TextSize = 24, TextColor3 = C.title })
	line(body, `Client: {card.client} · {card.address}`, 3, { TextColor3 = K.text })
	line(body, tostring(card.blurb or ""), 4)
	local minutes = math.floor((tonumber(card.time) or 0) / 60)
	chipRow(body, 5, {
		`⏱ {minutes} MIN`,
		`🧟 HORDE AT {clock(tonumber(card.hordeAt) or 0)} LEFT`,
		`📦 {card.items or 0} THINGS`,
		`🚚 {string.upper(tostring(card.truck))} LENT`,
	})
	local stars = card.stars or {}
	line(body, if #stars > 0 then `★ MUST-HAVES: {table.concat(stars, " · ")}` else "★ MUST-HAVES: none", 6, { TextColor3 = C.gold, Font = Theme.HeadingFont, TextSize = 13 })
	line(body, `UP TO {Ui.money(tonumber(card.estimate) or 0)}`, 7, { Font = Theme.HeadingFont, TextSize = 28, TextColor3 = C.money })
	line(body, "Paid by what arrives and its condition; ★ things ×1.5, a time bonus, broken things cost you. Your crew (K) helps and shares the pay.", 8, { TextSize = 12, TextColor3 = C.faint })
	local busy = card.busy
	if type(busy) == "string" then
		line(body, busy, 9, { TextColor3 = K.red, Font = Theme.HeadingFont, TextSize = 13 })
	end
	local holder = Ui.make("Frame", { Name = "Start", Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, LayoutOrder = 10, ZIndex = 22 }, body)
	local start = CardKit.bigButton(holder, {
		name = "StartMove",
		text = if type(busy) == "string" then "CAN'T START YET" else "▶ START THE MOVE",
		kind = if type(busy) == "string" then "shut" else "primary",
		height = 48,
		z = 23,
		onClick = function()
			if type(busy) ~= "string" then
				closeCard()
				-- MoveStory hook: the chapter's briefing first (once a game), then START; its ✕ brings this card back
				MoveStoryUi.briefing(card.id, function()
					remote:FireServer("start", card.id)
				end, function()
					showContract(card)
				end)
			end
		end,
	})
	Ui.gamepadFocus(start)
	MoveStoryUi.chapters(body, 11, card.id) -- MoveStory hook: the story road (CHAPTERS) under START
	sound("notify")
end

local HEAD: { [string]: string } = { done = "MOVE COMPLETE", late = "TIME'S UP", cancelled = "MOVE CALLED OFF", failed = "MOVE LOST" }

local function showResult(r: any)
	if type(r) ~= "table" then
		return
	end
	closeList()
	local good = r.how == "done" or r.how == "late"
	local body = cardShell("MoveResult", if good then K.good else K.red)
	if not body then
		return
	end
	line(body, `{HEAD[r.how] or "MOVE OVER"} · {r.icon or "🏠"} {string.upper(tostring(r.name))}`, 1, { Font = Theme.HeadingFont, TextSize = 13, TextColor3 = if good then K.good else K.red })
	local stars = math.clamp(tonumber(r.stars) or 0, 0, 5)
	line(body, string.rep("★", stars) .. string.rep("☆", 5 - stars), 2, { Font = Theme.HeadingFont, TextSize = 34, TextColor3 = C.gold, TextXAlignment = Enum.TextXAlignment.Center })
	line(body, tostring(r.howText or ""), 3, { TextColor3 = K.text, TextXAlignment = Enum.TextXAlignment.Center })
	chipRow(body, 4, {
		`📦 DELIVERED {r.delivered or 0}/{r.total or 0}`,
		`★ {r.starsOut or 0}/{r.starsTotal or 0}`,
		`🏠 LEFT BEHIND {r.left or 0}`,
		`💥 BROKEN {r.broken or 0}`,
	})
	if good then
		local parts = { `Things {Ui.money(tonumber(r.base) or 0)}`, `★ bonus {Ui.money(tonumber(r.starBonus) or 0)}`, `time bonus {Ui.money(tonumber(r.timeBonus) or 0)}` }
		local fine = tonumber(r.fine) or 0
		if fine > 0 then
			table.insert(parts, `broken −{Ui.money(fine)}`)
		end
		line(body, table.concat(parts, " · ") .. ` → {Ui.money(tonumber(r.pay) or 0)}`, 5, { TextSize = 13 })
		line(body, `YOUR SHARE {Ui.money(tonumber(r.money) or 0)} · +{r.xp or 0} XP`, 6, { Font = Theme.HeadingFont, TextSize = 24, TextColor3 = C.money, TextXAlignment = Enum.TextXAlignment.Center })
		if (tonumber(r.crew) or 1) > 1 then
			line(body, `Split with the crew at the truck ({r.crew} of you).`, 7, { TextSize = 12, TextColor3 = C.faint, TextXAlignment = Enum.TextXAlignment.Center })
		end
	end
	MoveStoryUi.thanks(body, 8, r, if type(state) == "table" then state.contract else nil) -- MoveStory hook: the client's thanks
	local holder = Ui.make("Frame", { Name = "Ok", Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = 9, ZIndex = 22 }, body)
	local ok = CardKit.bigButton(holder, { name = "Ok", text = "OK", kind = if good then "good" else "shut", height = 44, z = 23, onClick = closeCard })
	Ui.gamepadFocus(ok)
	sound(if good then "job_done" else "job_fail")
end

-- ── The state ──────────────────────────────────────────────────────────────

local function setState(view: any)
	state = if type(view) == "table" then view else nil
	refreshPanel()
	updateGps()
	if listOpen then
		drawList()
	end
end

function MovingHud.isOpen(): boolean
	return cardFrame ~= nil or listOpen or MoveStoryUi.isOpen() -- (MoveStory hook: a story card frees the mouse too)
end

function MovingHud.active(): boolean
	return state ~= nil
end

function MovingHud.start()
	local root = screen()
	if root then
		buildPanel(root)
	end
	watchPrompts()
	remote.OnClientEvent:Connect(function(kind: any, a: any, b: any)
		if kind == "state" then
			setState(a)
		elseif kind == "contract" then
			showContract(a)
		elseif kind == "result" then
			showResult(a)
		elseif kind == "fade" then
			local seconds = if type(b) == "number" then math.clamp(b, 0, 2) else nil
			if a == "out" then
				Fade.out(seconds)
			else
				Fade.into(seconds)
			end
		end
	end)
	-- Tab: the list (Roblox's own player list may take Tab as well: not waited for)
	UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
		if UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Tab and state ~= nil then
			toggleList()
		end
	end)
	-- the clock and the GPS once a second; the panel's words with them
	task.spawn(function()
		while true do
			task.wait(1)
			if state ~= nil then
				pcall(refreshPanel)
				pcall(updateGps)
			end
		end
	end)
	remote:FireServer("state")
end

return MovingHud
