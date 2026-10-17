--!strict
-- 10.x THE MAP (the owner: "I need you to add a way to look at the map"; Config.SandboxMapUi): the sandbox's big map, a
-- window in the game's contract look (client/Theme.luau; the city's map window, client/MapView.luau, its model: a
-- charcoal window, the map glyph and MAP, a fine line, the square ✕). What it shows is client/SandboxMapData.luau's,
-- drawn by client/SandboxMapDraw.luau; where it all goes is shared/SandboxMapRules.luau's (window, fit).
--   * In the lobby: its plan (SandboxMap.Lobby): the plaza and the hedge, the four plots (yours in gold: YOUR
--     WAREHOUSE, its UPGRADES desk), the PAINT shop, the TOP MOVERS board, the DISPATCH, 10.4 the PLAY circle (its
--     ring amber while a lobby counts down; its line: STEP IN, 2 OPEN LOBBIES, STARTING), the players as dots with
--     their names and you as a ▲; the side column's OPEN LOBBIES (a row a lobby: its host and house over its
--     difficulty, n/4, FRIENDS ONLY, STARTING) and IN A RUN (a row a run: its house over its difficulty and party),
--     server/Parties.luau's attribute on the PLAY circle. A click or a tap on the circle (on the map, on the side
--     column's PLAY row or on a lobby's row) has the guide show the way there (client/SandboxGuide.luau goTo) and
--     closes the map.
--   * In a run: the house's floor plan (rooms, walls, doorways, fixtures, windows) over a strip of its front yard (the
--     front door, the truck), who is where (you, your party, Danny and the helpers, the zombies near you), the loot you
--     saw (dots in their tiers' colours; an uncarried Epic or Legendary pulses) and the dangers' markers; the side
--     column: the clock, IN THE TRUCK n / total, the van's fill, the loot seen, the party, the legend.
--   * Opening it: M (Config.SandboxMapUi.Key), the gamepad's L2 on foot (SandboxPad.Actions.map: not in a seat, not
--     while carrying: B would put the piece down), the 🗺 MAP chip; M again, ESC (Main's Hud.onCloseWindows: close), the
--     gamepad's B, the ✕ or a click beside the window close it. A window like the others (client/Main.client.luau's
--     windows: one at a time, it frees the mouse: CameraRig.mouseNeeded).
--   * The 🗺 MAP chip: beside client/SandboxTasksUi.luau's 📋 TASKS chip, in its ScreenGui "SandboxTasksChip" (so what
--     keeps clear of the HUD's chips keeps clear of it too: Danny's line and card, the offer card, the guide's line),
--     at its scale and height (a finger's size on a touch screen); its key outline M on a computer, the gamepad's L2
--     glyph with a gamepad, none on a touch screen. Hidden while client/PlayUi.luau's lobby bar stands where it would be
--     (a small phone). Without the TASKS chip: under the money block, in a ScreenGui of its own.
--   * Cheap: the plan is drawn once an open (again only when the place or the screen changes), the markers move every
--     Config.SandboxMapUi.Every s while it is open, nothing runs while it is shut but the chip's place (on its signals
--     and every half second).
--   SandboxMapUi.start()             listens (once; nothing outside the sandbox); starts SandboxMapData
--   SandboxMapUi.open() / close() / toggle() / isOpen()
--   SandboxMapUi.step()              one look at the markers and the lines (the loop's; the checks')
--   SandboxMapUi.arrange()           the chip's place now (the checks')
--   SandboxMapUi.parts()             its pieces (window, map, side, canvas, chip) for the checks
--   SandboxMapUi.onOpen              a hook: it opened (client/Main.client.luau: the other windows close)
--   SandboxMapUi.notify              a hook: a toast (client/SandboxHud.luau's)
-- Presentation only.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SandboxMap = require(Shared.SandboxMap)
local SandboxPad = require(Shared.SandboxPad)
local RunRules = require(Shared.RunRules)
local Rules = require(Shared.SandboxMapRules)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)
local PadGlyph = require(script.Parent.PadGlyph)
local Data = require(script.Parent.SandboxMapData)
local Draw = require(script.Parent.SandboxMapDraw)

local SandboxMapUi = {}

SandboxMapUi.onOpen = nil :: (() -> ())?
SandboxMapUi.notify = nil :: ((text: string) -> ())?

local C = Config.SandboxMapUi
local HUD = Config.SandboxHud
local K = Theme.Contract
local player = Players.LocalPlayer
local CHIP_GAP = 6 -- px at the chips' scale between 📋 TASKS and 🗺 MAP

local started = false
local opened = false
local opens = 0 -- (the loop of an open stops with the next one)
local ui: { [string]: any } = {} -- gui, shade, window, map, side, canvas, key, rows, status lines
local chip: { [string]: any } = {} -- gui, button, label, key, scale, corner, own
local placeNow: Data.Place? = nil

local function sandboxOn(): boolean
	local sandbox = (Config :: any).Sandbox
	return type(sandbox) == "table" and sandbox.On == true
end

local function toast(text: string)
	local notify = SandboxMapUi.notify
	if notify then
		pcall(notify, text)
		return
	end
	pcall(function()
		(require(script.Parent.Hud) :: any).toast(text)
	end)
end

-- The HUD shows (not the start screen): client/SandboxHud.luau's ScreenGui.
local function hudShown(): boolean
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("SandboxHud")
	return hud == nil or (hud :: any).Enabled ~= false
end

-- ── The window ───────────────────────────────────────────────────────────────

-- (`cut`: a line whose words change, cut at its end when too long; the others must fit: tools/phone-ui/sandboxmap.luau)
local function label(parent: Instance, name: string, text: string, x: number, y: number, w: number, size: number, c: Color3, bold: boolean?, z: number?, cut: boolean?): TextLabel
	return Ui.make("TextLabel", {
		Name = name,
		Text = text,
		TextSize = size,
		Font = if bold then Theme.HeadingFont else Theme.Font,
		TextColor3 = c,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = if cut then Enum.TextTruncate.AtEnd else Enum.TextTruncate.None,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(w, size + 6),
		Position = UDim2.fromOffset(x, y),
		ZIndex = z or 3,
	}, parent)
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function screenGui(): ScreenGui?
	local made = ui.gui
	if made and made.Parent then
		return made
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = Ui.make("ScreenGui", { Name = "SandboxMapUi", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 6, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false }, playerGui)
	ui.gui = gui
	return gui
end

-- 10.4 the PLAY circle picked (on the map, its row or a lobby's): the guide shows the way to it.
local function guideToPlay()
	local ok, guide = pcall(function(): any
		return require(script.Parent.SandboxGuide)
	end)
	if not ok or type(guide) ~= "table" or type(guide.goTo) ~= "function" then
		return
	end
	local p = SandboxMap.Lobby.play
	pcall(guide.goTo, Vector3.new(p.x, SandboxMap.GroundTop + 1, p.z), "PLAY")
	CardKit.click()
	SandboxMapUi.close()
	toast("🧭 The guide shows the way to PLAY")
end

local function canGuide(): boolean
	local ok, guide = pcall(function(): any
		return require(script.Parent.SandboxGuide)
	end)
	return ok and type(guide) == "table" and type(guide.goTo) == "function"
end

-- The side column: the lobby's HOUSES (a row each, its state's line), or the run's status; the legend under them.
local function buildSide(side: ScrollingFrame, place: Data.Place, u: number, width: number)
	local labelSize, smallSize = Rules.textSize(C.Text.Label, u), Rules.textSize(C.Text.Small, u)
	local touch = Ui.touchLayout()
	local y = 0
	local inner = width - 8
	ui.rows = {}
	ui.lines = {}
	local function title(text: string)
		label(side, "Title", text, 0, y, inner, smallSize, K.secondary, true)
		y += smallSize + 10
	end
	if place.kind == "lobby" then
		-- 10.4: the PLAY circle (a row: the guide shows the way), the open lobbies and the runs now (rows the look fills)
		local guided = canGuide()
		local rowH = math.max(if touch then Ui.MinTouch else 0, math.floor(2 * labelSize + 16))
		local function row(name: string, y0: number): any
			local made = Ui.make("TextButton", {
				Name = name,
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = K.row,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(inner, rowH),
				Position = UDim2.fromOffset(0, y0),
				ZIndex = 3,
			}, side)
			Ui.make("UICorner", { CornerRadius = UDim.new(0, 4) }, made)
			local bar = Ui.make("Frame", { Name = "State", Size = UDim2.new(0, 4, 1, -8), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = rgb(Config.Runs.Play.Free), BorderSizePixel = 0, ZIndex = 4 }, made)
			local top = label(made, "Top", "", 14, 4, inner - 20, labelSize, K.text, true, 4, true)
			local bottom = label(made, "Bottom", "", 14, 4 + labelSize + 4, inner - 20, smallSize, K.secondary, false, 4, true)
			if guided then
				made.Activated:Connect(guideToPlay)
			else
				made.Selectable = false
			end
			made.MouseEnter:Connect(function()
				made.BackgroundColor3 = K.raised
			end)
			made.MouseLeave:Connect(function()
				made.BackgroundColor3 = K.row
			end)
			return { row = made, bar = bar, top = top, bottom = bottom }
		end
		title(if guided then (if touch then "PLAY · TAP TO GO" else "PLAY · CLICK TO GO") else "PLAY")
		local play = row("Play", y)
		play.top.Text = "▶ THE PLAY CIRCLE"
		play.top.TextColor3 = rgb(Config.Runs.Play.Free)
		play.bottom.Text = "STEP IN: CREATE A LOBBY OR JOIN ONE"
		ui.play = play
		y += rowH + 12
		ui.listTop = y
		ui.rowH = rowH
		ui.rows = {}
		ui.titles = {
			open = label(side, "OpenTitle", "OPEN LOBBIES", 0, y, inner, smallSize, K.secondary, true),
			none = label(side, "None", "NONE YET: STEP INTO PLAY TO MAKE ONE", 0, y, inner, smallSize, K.secondary, false, nil, true),
			runs = label(side, "RunsTitle", "IN A RUN", 0, y, inner, smallSize, K.secondary, true),
		}
		for n = 1, C.Rows do
			local r = row(`Row{n}`, y)
			r.row.Visible = false
			ui.rows[n] = r
		end
		ui.legend = {}
		for _, entry in { { "▲", "YOU", "You" }, { "●", "PLAYERS", "Player" }, { "■", "YOUR WAREHOUSE", "Yours" }, { "■", "UPGRADES DESK", "Desk" } } do
			table.insert(ui.legend, label(side, `Legend_{entry[2]}`, `{entry[1]}  {entry[2]}`, 0, y, inner, smallSize, rgb(C.Colors[entry[3]]), true))
		end
		ui.legendTitle = label(side, "LegendTitle", "ON THE MAP", 0, y, inner, smallSize, K.secondary, true)
		ui.small = smallSize
		y += smallSize + 10 -- (the look lays the rest out: SandboxMapUi.step)
	else
		label(side, "House", place.name, 0, y, inner, labelSize, K.text, true, nil, true)
		y += labelSize + 6
		if place.difficulty then
			local def = RunRules.def(string.lower(place.difficulty))
			label(side, "Difficulty", string.upper(place.difficulty), 0, y, inner, smallSize, if def then rgb(def.color) else K.secondary, true)
			y += smallSize + 6
		end
		y += 4
		ui.lines.clock = label(side, "Clock", "⏱ –:––", 0, y, inner, math.floor(labelSize * 1.4 + 0.5), K.text, true)
		y += math.floor(labelSize * 1.4 + 0.5) + 10
		ui.lines.truck = label(side, "Truck", "🚚 IN THE TRUCK 0 / 0", 0, y, inner, labelSize, K.good, true)
		y += labelSize + 8
		ui.lines.fill = label(side, "Fill", "VAN 0 % FULL", 0, y, inner, smallSize, K.secondary, true)
		y += smallSize + 8
		ui.lines.seen = label(side, "Seen", "LOOT SEEN 0", 0, y, inner, smallSize, K.secondary, true, nil, true)
		y += smallSize + 14
		title("WHO IS WHERE")
		for _, entry in { { "▲", "YOU", "You" }, { "●", "YOUR PARTY", "Party" }, { "●", "DANNY · HELPERS", "Helper" }, { "●", "ZOMBIES", "Zombie" }, { "■", "THE TRUCK", "Truck" } } do
			label(side, `Legend_{entry[2]}`, `{entry[1]}  {entry[2]}`, 0, y, inner, smallSize, rgb(C.Colors[entry[3]]), true)
			y += smallSize + 8
		end
		y += 6
		title("LOOT YOU SAW")
		local x = 0
		for _, id in Config.Collection.Order do
			local tier = Config.Collection.Tiers[id]
			local text = `● {string.upper(tier.name)}`
			local w = Draw.width(text, smallSize, Theme.HeadingFont)
			if x > 0 and x + w > inner then
				x = 0
				y += smallSize + 8
			end
			label(side, `Tier_{id}`, text, x, y, w + 2, smallSize, rgb(tier.color), true)
			x += w + 10
		end
		y += smallSize + 14
		-- (the dangers there now, over two lines: none, none shown)
		local dangers = label(side, "Dangers", "", 0, y, inner, smallSize, K.warn, true, nil, true)
		dangers.TextWrapped = true
		dangers.TextYAlignment = Enum.TextYAlignment.Top
		dangers.Size = UDim2.fromOffset(inner, 2 * smallSize + 10)
		ui.lines.danger = dangers
		y += 2 * smallSize + 14
	end
	local device = PadGlyph.device()
	if device ~= "touch" then
		local how = if device == "pad" then `{SandboxPad.keyWord("map", "pad") or "L2"} / B: CLOSE` else `{C.Key} / ESC: CLOSE`
		y += 4
		label(side, "Keys", how, 0, y, inner, smallSize, K.secondary, true)
		y += smallSize + 8
	end
	side.CanvasSize = UDim2.fromOffset(0, y)
end

local function closeNow()
	local gui = ui.gui
	if gui then
		gui.Enabled = false
		Ui.gamepadRelease(gui)
	end
end

-- The window for the place now (drawn again only when the place or the screen changed).
local function build(place: Data.Place)
	local gui = screenGui()
	if not gui then
		return
	end
	local size = Ui.screenSize()
	local touch = Ui.touchLayout()
	local layout = Rules.window(size.X, size.Y, Ui.screenScale(), touch)
	local key = `{place.key}|{layout.w}x{layout.h}|{touch}|{PadGlyph.device()}`
	if ui.window and ui.key == key then
		return
	end
	ui.key = key
	if ui.window then
		ui.window:Destroy()
		ui.window = nil
	end
	if not ui.shade then
		local shade = Ui.make("TextButton", {
			Name = "MapShade",
			Text = "",
			AutoButtonColor = false,
			Selectable = false,
			BackgroundColor3 = Color3.fromRGB(8, 10, 13),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
		}, gui)
		shade.Activated:Connect(SandboxMapUi.close)
		ui.shade = shade
	end
	local u = layout.u
	local window = Ui.make("Frame", {
		Name = "MapWindow",
		Size = UDim2.fromOffset(layout.w, layout.h),
		Position = UDim2.fromOffset(layout.x, layout.y),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.WindowTransparency,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 2,
		SelectionGroup = true,
	}, gui)
	Ui.make("UIStroke", { Color = K.rule, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, window)
	ui.window = window
	-- the header: the map glyph and MAP, the place, the ✕; a fine line under it
	local titleSize = Rules.textSize(C.Text.Title, u)
	local heading = Ui.heading(window, "Map", { glyph = "map", textSize = titleSize, height = layout.header - 8 })
	heading.frame.Size = UDim2.fromOffset(math.floor(130 * u), layout.header - 8)
	heading.frame.BackgroundTransparency = 1
	heading.title.TextColor3 = K.text
	heading.frame.Position = UDim2.fromOffset(layout.pad, 4)
	local closeSize = if touch then Ui.MinTouch else math.floor(32 * u + 0.5)
	local placeX = layout.pad + math.floor(130 * u) + 8
	label(window, "Place", place.name, placeX, math.floor((layout.header - Rules.textSize(C.Text.Label, u) - 6) / 2), layout.w - placeX - closeSize - 2 * layout.pad,
		Rules.textSize(C.Text.Label, u), K.secondary, true, nil, true)
	local close = Ui.closeButton(window, SandboxMapUi.close)
	close.Size = UDim2.fromOffset(closeSize, closeSize)
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -layout.pad, 0, math.floor(layout.header / 2))
	close.ZIndex = 4
	ui.close = close
	Ui.make("Frame", { Name = "HeaderLine", Size = UDim2.new(1, -2 * layout.pad, 0, 1), Position = UDim2.fromOffset(layout.pad, layout.header - 2), BackgroundColor3 = K.rule, BorderSizePixel = 0, ZIndex = 3 }, window)
	-- the map
	local m = layout.map
	local holder = Ui.make("Frame", {
		Name = "Map",
		Size = UDim2.fromOffset(m.w, m.h),
		Position = UDim2.fromOffset(m.x, m.y),
		BackgroundColor3 = rgb(C.Colors.Back),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 3,
	}, window)
	ui.map = holder
	local canvas: Draw.Canvas
	if place.kind == "lobby" then
		local frame = Rules.fit(Rules.lobbyBox(), 0, m.w, m.h, 6)
		canvas = Draw.lobby(holder, frame, u, m.w, m.h, if canGuide() then guideToPlay else nil, Data.plots())
	else
		local plan, yard = place.plan, place.yard
		local box = if plan then Rules.houseBox(plan, yard) elseif yard then yard.strip else { x0 = -20, z0 = -20, x1 = 20, z1 = 20 }
		local frame = Rules.fit(box, 180, m.w, m.h, 10)
		canvas = Draw.house(holder, frame, u, m.w, m.h, place, false)
		if not plan then
			label(holder, "Loading", "THE HOUSE'S PLAN COMES IN A MOMENT…", 12, 12, m.w - 24, Rules.textSize(C.Text.Label, u), K.text, true, 12)
		end
	end
	ui.canvas = canvas
	-- the side column
	ui.side = nil
	if layout.side > 0 then
		local side = Ui.make("ScrollingFrame", {
			Name = "Side",
			Size = UDim2.fromOffset(layout.side, m.h),
			Position = UDim2.fromOffset(m.x + m.w + layout.pad, m.y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = K.line,
			CanvasSize = UDim2.fromOffset(0, 0),
			ZIndex = 3,
		}, window)
		ui.side = side
		buildSide(side, place, u, layout.side)
	end
end

-- ── A look ───────────────────────────────────────────────────────────────────

-- 10.4: the side column's OPEN LOBBIES and IN A RUN rows for `entries` (SandboxMapData.lobbies), laid out under the PLAY
-- row, the legend under them (the side's canvas follows).
local function layoutRows(entries: { any })
	local side, rows, titles = ui.side, ui.rows, ui.titles
	if not side or not rows or not titles then
		return
	end
	local small, rowH = ui.small or 12, ui.rowH or 40
	local y = ui.listTop or 0
	local open, runs = {}, {}
	for _, e in entries do
		table.insert(if e.state == "run" then runs else open, e)
	end
	local used = 0
	local function put(list: { any })
		for _, e in list do
			used += 1
			local r = rows[used]
			if not r then
				return
			end
			local top, bottom, tone = Rules.lobbyLine(e)
			if r.top.Text ~= top then
				r.top.Text = top
			end
			if r.bottom.Text ~= bottom then
				r.bottom.Text = bottom
			end
			local c = if tone == "run" then K.red elseif tone == "starting" then rgb(Config.Runs.Play.Waiting) elseif tone == "full" then K.secondary else rgb(Config.Runs.Play.Free)
			r.bar.BackgroundColor3 = c
			r.bottom.TextColor3 = if tone == "starting" then c else K.secondary
			r.row.Position = UDim2.fromOffset(0, y)
			r.row.Visible = true
			y += rowH + 6
		end
	end
	titles.open.Position = UDim2.fromOffset(0, y)
	y += small + 10
	titles.none.Visible = #open == 0
	if #open == 0 then
		titles.none.Position = UDim2.fromOffset(0, y)
		y += small + 12
	end
	put(open)
	titles.runs.Visible = #runs > 0
	if #runs > 0 then
		y += 6
		titles.runs.Position = UDim2.fromOffset(0, y)
		y += small + 10
		put(runs)
	end
	for n = used + 1, #rows do
		rows[n].row.Visible = false
	end
	y += 6
	ui.legendTitle.Position = UDim2.fromOffset(0, y)
	y += small + 10
	for _, l in ui.legend do
		l.Position = UDim2.fromOffset(0, y)
		y += small + 8
	end
	local keys = side:FindFirstChild("Keys")
	if keys and keys:IsA("GuiObject") then
		y += 4
		keys.Position = UDim2.fromOffset(0, y)
		y += small + 8
	end
	side.CanvasSize = UDim2.fromOffset(0, y)
end

function SandboxMapUi.step()
	if not opened then
		return
	end
	local place = Data.place()
	if not placeNow or place.key ~= placeNow.key then
		placeNow = place
		build(place)
	end
	local canvas = ui.canvas
	if not canvas then
		return
	end
	local people = Data.people(place)
	local loot = Data.loot(place)
	local dangers = Data.dangers(place)
	Draw.marks(canvas, people, loot, dangers, Data.truck(place))
	if place.kind == "lobby" then
		local entries = Data.lobbies()
		Draw.play(canvas, entries)
		layoutRows(entries)
	else
		local status = Data.status(place)
		local lines = ui.lines
		if status and lines and lines.clock then
			lines.clock.Text = if status.left then `⏱ {Rules.clock(status.left)}` else "⏱ –:––"
			lines.clock.TextColor3 = if status.left and status.left <= 60 then K.red else K.text
			lines.truck.Text = `🚚 IN THE TRUCK {status.out} / {status.total}`
			lines.fill.Text = `VAN {math.floor(status.fill * 100 + 0.5)} % FULL`
			lines.seen.Text = `👁 LOOT SEEN: {#loot}`
			local present: { [string]: boolean } = {}
			local icons: { string } = {}
			for _, d in dangers do
				local def = C.Danger[d.tag]
				if def and not present[d.tag] then
					present[d.tag] = true
					table.insert(icons, `{def.icon} {def.name}`)
				end
			end
			lines.danger.Text = table.concat(icons, "  ")
			lines.danger.Visible = #icons > 0
		end
	end
end

-- ── Opening and closing ──────────────────────────────────────────────────────

function SandboxMapUi.isOpen(): boolean
	return opened
end

function SandboxMapUi.open()
	if opened or not sandboxOn() then
		return
	end
	opened = true
	opens += 1
	local mine = opens
	placeNow = nil
	local gui = screenGui()
	if gui then
		gui.Enabled = true
	end
	local hook = SandboxMapUi.onOpen
	if hook then
		pcall(hook)
	end
	local ok, err = pcall(SandboxMapUi.step :: any)
	if not ok then
		warn(`[SandboxMapUi] {err}`)
	end
	-- the gamepad's selection on the PLAY row (the lobby) or the ✕
	local first: GuiObject? = if ui.play and ui.play.row.Parent then ui.play.row else nil
	Ui.gamepadFocus(first or ui.close)
	task.spawn(function()
		while opened and opens == mine do
			task.wait(C.Every)
			if not opened or opens ~= mine then
				break
			end
			local stepped, why = pcall(SandboxMapUi.step :: any)
			if not stepped then
				warn(`[SandboxMapUi] {why}`)
			end
		end
	end)
end

function SandboxMapUi.close()
	if not opened then
		return
	end
	opened = false
	closeNow()
end

function SandboxMapUi.toggle()
	if opened then
		SandboxMapUi.close()
	else
		SandboxMapUi.open()
	end
end

function SandboxMapUi.parts(): { [string]: any }
	return { gui = ui.gui, window = ui.window, map = ui.map, side = ui.side, canvas = ui.canvas, close = ui.close, rows = ui.rows, play = ui.play, lines = ui.lines, chip = chip.button, chipGui = chip.gui }
end

-- ── The 🗺 MAP chip ──────────────────────────────────────────────────────────

local function find(gui: string, name: string): GuiObject?
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local holder = playerGui and playerGui:FindFirstChild(gui)
	local found = holder and holder:FindFirstChild(name, true)
	return if found and found:IsA("GuiObject") then found else nil
end

local function boxOf(object: GuiObject): { x0: number, y0: number, x1: number, y1: number }
	local at, size = object.AbsolutePosition, object.AbsoluteSize
	return { x0 = at.X, y0 = at.Y, x1 = at.X + size.X, y1 = at.Y + size.Y }
end

local function scaleOf(object: GuiObject): number
	local s = object:FindFirstChildOfClass("UIScale")
	return if s then (s :: UIScale).Scale else 1
end

function SandboxMapUi.arrange()
	local button = chip.button
	if not button then
		return
	end
	local touch = Ui.touchLayout()
	local tasks = find("SandboxTasksChip", "TasksChip")
	local x, y, scale
	if tasks then
		local b = boxOf(tasks)
		scale = scaleOf(tasks)
		x, y = b.x1 + CHIP_GAP * scale, b.y0
	else
		local block = find("SandboxHud", "MoneyBlock")
		if block then
			local b = boxOf(block)
			scale = scaleOf(block)
			x, y = b.x0, b.y1 + CHIP_GAP * scale
		else
			scale = Ui.screenScale()
			x, y = 16, 160
		end
	end
	if touch then
		scale = math.max(scale, HUD.TouchScale)
	end
	chip.scale.Scale = scale
	local text = "🗺 MAP"
	chip.label.Text = text
	local device = PadGlyph.device()
	local key = chip.key
	local keyShown = device ~= "touch"
	local glyph: any = key:FindFirstChild("Pad")
	if device == "pad" then
		local pad = SandboxPad.pads("map")[1] or C.Button
		local image = PadGlyph.image(pad)
		if image ~= "" then
			if not glyph then
				glyph = Ui.make("ImageLabel", { Name = "Pad", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit }, key)
			end
			glyph.Image = image
			glyph.Visible = true
			key.Text = ""
		else
			key.Text = SandboxPad.button(pad)
			if glyph then
				glyph.Visible = false
			end
		end
	else
		key.Text = C.Key
		if glyph then
			glyph.Visible = false
		end
	end
	key.Visible = keyShown
	local chipH = HUD.Chip
	local chipW = CardKit.width(text, HUD.ChipText, Theme.HeadingFont) + 24 + (if keyShown then 28 else 0)
	if touch then
		chipH = math.max(chipH, math.ceil(Ui.MinTouch / scale))
		chipW = math.max(chipW, math.ceil(Ui.MinTouch / scale))
	end
	chipW = math.ceil(chipW)
	button.Size = UDim2.fromOffset(chipW, chipH)
	local origin = if chip.gui then (chip.gui :: any).AbsolutePosition else Vector2.new(0, 0)
	button.Position = UDim2.fromOffset(math.floor(x - origin.X + 0.5), math.floor(y - origin.Y + 0.5))
	chip.corner.CornerRadius = UDim.new(0, math.floor(chipH / 2))
	chip.label.Size = UDim2.new(1, -(12 + (if keyShown then 28 else 0)), 1, 0)
	-- (a small phone: the lobby bar of client/PlayUi.luau may stand where it would be; then it waits)
	local panel = find("PlayUi", "PlayBar")
	local clear = true
	if panel and panel.Visible then
		local a, b = boxOf(button), boxOf(panel)
		clear = not (math.min(a.x1, b.x1) - math.max(a.x0, b.x0) > 0 and math.min(a.y1, b.y1) - math.max(a.y0, b.y0) > 0)
	end
	button.Visible = clear
end

local function buildChip()
	local playerGui = player:WaitForChild("PlayerGui")
	-- the TASKS chip's ScreenGui (its chips' row), a few seconds at most; else one of its own that follows the HUD
	local holder = playerGui:FindFirstChild("SandboxTasksChip")
	local waited = 0
	while not holder and waited < 3 do
		task.wait(0.25)
		waited += 0.25
		holder = playerGui:FindFirstChild("SandboxTasksChip")
	end
	if not holder then
		holder = Ui.make("ScreenGui", { Name = "SandboxMapChip", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 1, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
		local hud = playerGui:FindFirstChild("SandboxHud")
		if hud then
			(holder :: any).Enabled = (hud :: any).Enabled
			hud:GetPropertyChangedSignal("Enabled"):Connect(function()
				(holder :: any).Enabled = (hud :: any).Enabled
			end)
		end
		chip.own = true
	end
	chip.gui = holder
	local button = Ui.make("TextButton", {
		Name = "MapChip",
		BackgroundColor3 = K.row,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
	}, holder)
	chip.button = button
	chip.scale = Ui.make("UIScale", { Name = "Scale", Scale = 1 }, button)
	chip.corner = Ui.make("UICorner", { CornerRadius = UDim.new(0, 16) }, button)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.6 }, button)
	chip.label = Ui.label(button, "🗺 MAP", UDim2.fromScale(1, 1), {
		Name = "Label",
		Position = UDim2.fromOffset(12, 0),
		Font = Theme.HeadingFont,
		TextSize = HUD.ChipText,
		TextColor3 = K.text,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	chip.key = Ui.label(button, C.Key, UDim2.fromOffset(20, 20), {
		Name = "Key",
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = K.secondary,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.4 }, chip.key)
	Ui.corner(chip.key, 4)
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = K.raised
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = K.row
	end)
	button.Activated:Connect(function()
		CardKit.click()
		SandboxMapUi.toggle()
	end)
	-- follow the TASKS chip (its moves and sizes), the device, the screen; the pad panel: every half second
	local tasks = find("SandboxTasksChip", "TasksChip")
	if tasks then
		tasks:GetPropertyChangedSignal("AbsolutePosition"):Connect(SandboxMapUi.arrange)
		tasks:GetPropertyChangedSignal("AbsoluteSize"):Connect(SandboxMapUi.arrange)
	end
	PadGlyph.watch(SandboxMapUi.arrange)
	SandboxMapUi.arrange()
	task.spawn(function()
		while true do
			task.wait(0.5)
			pcall(SandboxMapUi.arrange :: any)
		end
	end)
end

-- ── Starting ─────────────────────────────────────────────────────────────────

local function seated(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and (humanoid :: Humanoid).SeatPart ~= nil
end

local function carrying(): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute("Carrying") ~= nil
end

function SandboxMapUi.start()
	if started or not sandboxOn() then
		return
	end
	started = true
	Data.start()
	local key: Enum.KeyCode? = nil
	pcall(function()
		key = (Enum.KeyCode :: any)[C.Key]
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if UserInputService:GetFocusedTextBox() then
			return
		end
		local code = input.KeyCode
		if opened and code == Enum.KeyCode.ButtonB then
			SandboxMapUi.close()
			return
		end
		if processed then
			return
		end
		if key and code == key then
			if opened or hudShown() then
				SandboxMapUi.toggle()
			end
			return
		end
		-- the gamepad's L2 (SandboxPad's "map"): on foot, not carrying, no window's selection (but this one's)
		local pad = SandboxPad.pads("map")[1]
		if pad and code.Name == pad and not seated() and not carrying() then
			local selected = GuiService.SelectedObject
			local gui = ui.gui
			if selected == nil or (gui and selected:IsDescendantOf(gui)) then
				if opened or hudShown() then
					SandboxMapUi.toggle()
				end
			end
		end
	end)
	-- a new screen size: the window again (its key has the size)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if opened then
				placeNow = nil
				pcall(SandboxMapUi.step :: any)
			end
			-- (the chip after the TASKS chip has its new place: client/SandboxTasksUi.luau's 0.05 s)
			task.delay(0.1, function()
				pcall(SandboxMapUi.arrange :: any)
			end)
		end)
	end
	task.spawn(buildChip)
end

return SandboxMapUi
