--!strict
-- 10.1 THE CREW WINDOW and the down ring (Config.Crew; the owner: "you'll be able to get different employees who can do
-- something different … And maybe when one dies, then … something"). server/HelperCrew.luau decides everything (who is
-- in your crew, who comes into your runs, the hospital, the money); shared/CrewRules.luau's rows and words. This only
-- shows them and asks, through the Crew remote:
--   { kind = "state", rows, pick, comes, instead, money }   kept; an open window is drawn again only when what it
--                                       shows changed (the countdowns follow in place)
--   { kind = "open" }                   your helper's "Crew" prompt by your warehouse, his card's 👥 CREW
--                                       (client/MoveHelperCard.luau asks the server): THE WINDOW
-- THE WINDOW: a modal card "👥 YOUR CREW" (who comes into your runs under it, ✕) over one row a kind in Config.Crew.Order:
-- his icon on his shirt's colour, his name and role, what he does (Ability), his health and pace, and at the right his
-- state:
--   * yours and ready: PICK ({ kind = "pick", id }: he comes into your runs from now on, saved), or ✓ PICKED (the one
--     who comes);
--   * in hospital (down in a run, nobody revived him in time): "🏥 3:12" counting down, and DISCHARGE $X
--     ({ kind = "discharge", id }: out now for the money; without it the button is grey and a tap says what it costs);
--     your pick there: "PICKED" by his name, the first ready one comes instead (the subtitle says so);
--   * not yours yet: "🔒 Rescue him in a run" (a trapped helper waits in some runs' houses: free him, he joins you).
-- ✕, ESC, the gamepad's B, the Roblox menu or a tap beside the card close it. Modal (the mouse free), one window at a
-- time (client/Main.client.luau: onOpen). Follows client/UpgradeUi.luau's kit (CardKit, Theme).
-- THE DOWN RING: over a helper down in a run (server/HelperCrew.luau tags his model CrewDown with CrewDownUntil, the
-- server time he is out at) a ring of Config.Crew.Ring.Size px whose dots go out as the seconds run (the last
-- Down.Seconds / 3 red), the seconds left in its middle and "REVIVE <NAME>" under it (his revive prompt: hold E by
-- him); seen through walls within Ring.Range studs, gone once he is up or out. Looked at every Ring.Every s (the tag,
-- no scan of the world).
--   CrewUi.start()                      listens (once)
--   CrewUi.open() / close() / isOpen()
--   CrewUi.state()                      the last state (nil: none yet)
--   CrewUi.step()                       one look: the rings and the window's countdowns (the loop's; the checks')
--   CrewUi.rings()                      the rings shown now (by model: the checks)
--   CrewUi.layout(W, H, touch)          the card on a W × H screen (px under Roblox's top bar)
--   CrewUi.notify / onOpen              hooks: the toasts, the window opened
-- Presentation only.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local CrewRules = require(Shared.CrewRules)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)

local CrewUi = {}

CrewUi.notify = nil :: ((text: string) -> ())?
CrewUi.onOpen = nil :: (() -> ())?

local K = Theme.Contract
local C = CardKit.Color
local W = Config.Crew.Window
local R = Config.Crew.Ring

export type Row = CrewRules.Row
export type State = { rows: { Row }, pick: string, comes: string?, instead: boolean, money: number, at: number }
export type Layout = {
	touch: boolean,
	scale: number,
	x: number,
	y: number,
	w: number,
	h: number,
	pad: number,
	header: number,
	close: number,
	listY: number,
	listH: number,
	rowW: number,
	rowH: number,
	gap: number,
	button: number,
	buttonW: number,
	statusW: number,
}
type Ring = { gui: any, dots: { any }, left: any, untilAt: number, lit: number }

local HEADER = 52
local LIST_GAP = 4
local SCROLLBAR = 6
local WORDS = 62 -- a row's words: his name, what he does (two lines), his health and pace
local DOTS = 24 -- the ring's dots
local DOT = 8
local LABEL_H = 22 -- "REVIVE DANNY" under the ring
local AMBER = Color3.fromRGB(240, 132, 44) -- the movers' colour (client/MovingHud.luau's)
local RED = Color3.fromRGB(229, 83, 75)
local SPENT = Color3.fromRGB(60, 64, 70)
local DOWN_TAG = "CrewDown"

local started = false
local remote: RemoteEvent? = nil
local current: State? = nil
local gui: any = nil
local opened = false
local shownKey = ""
local card: any = nil
local sentAt: { [string]: number } = {}
local asked = false -- (a countdown ran out: the state asked once)
local rings: { [Instance]: Ring } = {}
local nextLook = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rgb(c: { number }?): Color3
	return if c then Color3.fromRGB(c[1], c[2], c[3]) else K.raised
end

-- ── The layout (pure) ───────────────────────────────────────────────────────

function CrewUi.layout(width: number, height: number, touch: boolean): Layout
	local margin = if touch then 8 else 16
	local rows = #Config.Crew.Order
	local pad = if touch then 10 else 16
	local gap = 6
	local full = HEADER + LIST_GAP + rows * W.Row + (rows - 1) * gap + pad
	-- a touch screen: as big as fits (the rows whole), not under TouchScale
	local scale = if touch
		then math.clamp(math.min(width / (W.Width + 2 * margin), (height - 2 * margin) / full), W.TouchScale, Ui.MaxScale)
		else math.max(Ui.scaleFor(Vector2.new(width, height)), 0.7)
	local finger = math.ceil(Ui.MinTouch / scale)
	local button = if touch then math.max(44, finger) else 36
	local rowH = math.max(W.Row, button + 16)
	-- too tall for the screen: the rows get lower, as low as their words and buttons allow; only below that it scrolls
	local room = math.floor((height - 2 * margin) / scale) - HEADER - LIST_GAP - pad
	if rows * rowH + (rows - 1) * gap > room then
		gap = 4
		rowH = math.clamp(math.floor((room - (rows - 1) * gap) / rows), math.max(WORDS + 4, button + 8), rowH)
	end
	local want = HEADER + LIST_GAP + rows * rowH + (rows - 1) * gap + pad
	local w = math.floor(math.min(W.Width, (width - 2 * margin) / scale))
	local h = math.floor(math.min(want, (height - 2 * margin) / scale))
	return {
		touch = touch,
		scale = scale,
		x = math.floor((width - w * scale) / 2),
		y = math.floor((height - h * scale) / 2),
		w = w,
		h = h,
		pad = pad,
		header = HEADER,
		close = if touch then math.max(40, finger) else 40,
		listY = HEADER + LIST_GAP,
		listH = h - HEADER - LIST_GAP - pad,
		rowW = w - 2 * pad,
		rowH = rowH,
		gap = gap,
		button = button,
		buttonW = 150, -- ("DISCHARGE $1,250" whole)
		statusW = 78, -- ("🏥 12:34")
	}
end

-- ── Sending ─────────────────────────────────────────────────────────────────

-- One request a helper at most every 0.6 s (a double tap is one request).
local function send(message: { [string]: any }): boolean
	local key = `{message.kind}:{tostring(message.id)}`
	local clock = os.clock()
	if sentAt[key] and clock - sentAt[key] < 0.6 then
		return false
	end
	sentAt[key] = clock
	local target = remote
	if target then
		target:FireServer(message)
	end
	return true
end

local function toast(text: string)
	local notify = CrewUi.notify
	if notify then
		notify(text)
		return
	end
	pcall(function()
		require(script.Parent.Hud).toast(text)
	end)
end

-- ── The state ───────────────────────────────────────────────────────────────

-- A hospital row's seconds left now (the state's, less the time since it came).
local function leftOf(row: Row, state: State): number
	return math.max(0, math.ceil(row.left - (now() - state.at)))
end

local function priceOf(row: Row, state: State): number
	return CrewRules.dischargePrice(leftOf(row, state))
end

local function nameOf(id: string?): string
	local def = CrewRules.def(id)
	return if def then `{def.Icon} {def.Name}` else "Nobody"
end

local function subtitleOf(state: State?): string
	if not state then
		return "Asking your crew…"
	end
	if not state.comes then
		return "Everybody is in hospital: nobody comes into your runs until one is out"
	elseif state.instead then
		return `{nameOf(state.pick)} is in hospital: {nameOf(state.comes)} comes into your runs instead`
	end
	local have = 0
	for _, row in state.rows do
		if row.have then
			have += 1
		end
	end
	local more = if have < #state.rows then " · rescue trapped helpers in runs for more" else ""
	return `{nameOf(state.comes)} comes into your runs{more}`
end

local function stateKey(state: State?, layout: Layout): string
	local parts = { `{layout.w}x{layout.h}@{layout.scale}` }
	if state then
		table.insert(parts, `{state.pick}|{tostring(state.comes)}|{state.instead}`)
		for _, row in state.rows do
			local hospital = row.state == "hospital" and leftOf(row, state) > 0
			local price = if hospital then priceOf(row, state) else 0
			table.insert(parts, `{row.id}:{row.have}:{row.pick}:{if hospital then "h" else row.state}:{price}:{state.money >= price}`)
		end
	else
		table.insert(parts, "none")
	end
	return table.concat(parts, "|")
end

-- ── The window ──────────────────────────────────────────────────────────────

local draw: (keepScroll: boolean) -> ()

local function ensureGui(): any
	if gui then
		return gui
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.make("ScreenGui", {
		Name = "CrewUi",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 7, -- (with the other windows: over the HUD and the touch buttons)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	return gui
end

function CrewUi.close()
	if not opened then
		return
	end
	opened = false
	if card then
		Ui.gamepadRelease(gui)
		card:Destroy()
		card = nil
	end
	shownKey = ""
end

function CrewUi.isOpen(): boolean
	return opened
end

function CrewUi.state(): State?
	return current
end

local function words(parent: any, text: string, size: number, at: Vector2, w: number, h: number, props: { [string]: any })
	local made = Ui.label(parent, text, UDim2.fromOffset(w, h), props)
	made.Position = UDim2.fromOffset(at.X, at.Y)
	made.TextSize = size
	made.TextXAlignment = Enum.TextXAlignment.Left
	return made
end

local function drawRow(parent: any, row: Row, index: number, layout: Layout, rowW: number, state: State)
	local h = layout.rowH
	local def = CrewRules.def(row.id)
	local look = if def then def.Look else nil
	local hospital = row.state == "hospital" and leftOf(row, state) > 0
	local locked = not row.have
	local comes = row.id == state.comes
	local frame = Ui.make("Frame", {
		Name = `Crew_{row.id}`,
		Size = UDim2.fromOffset(rowW, h),
		Position = UDim2.fromOffset(0, (index - 1) * (h + layout.gap)),
		BackgroundColor3 = K.row,
		BorderSizePixel = 0,
	}, parent)
	Ui.corner(frame, Config.UiKit.RowCorner)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = if comes then C.gold elseif hospital then K.warn else K.line, Thickness = 1, Transparency = if comes or hospital then 0.45 else 0.8 }, frame)
	-- the picture: his icon on his shirt's colour (faded while he is not yours)
	local side = h - 12
	local picture = Ui.make("Frame", { Name = "Picture", Size = UDim2.fromOffset(side, side), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = rgb(look and look.shirt), BackgroundTransparency = if locked then 0.7 else 0.15, BorderSizePixel = 0 }, frame)
	Ui.corner(picture, 8)
	Ui.label(picture, row.icon, UDim2.fromScale(1, 1), { Name = "Emoji", TextSize = math.floor(side * 0.5), TextTransparency = if locked then 0.55 else 0, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center })
	-- the right: his state and its button
	local right = layout.buttonW + 10
	local buttonY = math.floor((h - layout.button) / 2)
	local statusX = rowW - right - 8 - layout.statusW
	if locked then
		local why = Ui.label(frame, `🔒 Rescue {CrewRules.him(row.id)} in a run`, UDim2.fromOffset(layout.statusW + 8 + layout.buttonW, layout.button), {
			Name = "Locked",
			Position = UDim2.new(1, -(right + 8 + layout.statusW), 0, buttonY),
			Font = Theme.HeadingFont,
			TextSize = 12,
			TextColor3 = C.dim,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		why.Selectable = false
	else
		if hospital then
			Ui.label(frame, `🏥 {CrewRules.clock(leftOf(row, state))}`, UDim2.fromOffset(layout.statusW, 22), {
				Name = "Left",
				Position = UDim2.fromOffset(statusX, math.floor(h / 2) - 11),
				Font = Theme.DisplayFont,
				TextSize = 15,
				TextColor3 = K.warn,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Right,
			})
			local price = priceOf(row, state)
			local can = state.money >= price
			local id, name = row.id, row.name
			local out = CardKit.bigButton(frame, {
				name = "Discharge",
				text = `DISCHARGE {CrewRules.money(price)}`,
				kind = if can then "good" else "shut",
				height = layout.button,
				textSize = 13,
				onClick = function()
					local live = current
					local cost = if live then priceOf(row, live) else price
					if not live or live.money < cost then
						toast(`🏥 Discharging {name} costs {CrewRules.money(cost)}: you have {CrewRules.money(if live then live.money else 0)}.`)
						return
					end
					if send({ kind = "discharge", id = id }) then
						local button = frame:FindFirstChild("Discharge")
						if button then
							button.Text = "…"
							button.Active = false
						end
					end
				end,
			})
			out.Size = UDim2.fromOffset(layout.buttonW, layout.button)
			out.Position = UDim2.new(1, -right, 0, buttonY)
		elseif row.pick then
			local picked = Ui.label(frame, "✓ PICKED", UDim2.fromOffset(layout.buttonW, layout.button), {
				Name = "Picked",
				Position = UDim2.new(1, -right, 0, buttonY),
				BackgroundColor3 = C.gold,
				BackgroundTransparency = 0,
				Font = Theme.HeadingFont,
				TextSize = 14,
				TextColor3 = C.goldInk,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Center,
				Selectable = true, -- (the gamepad reaches every row: the list scrolls to it)
			})
			Ui.corner(picked, 8)
		else
			Ui.label(frame, if comes then "Comes now" else "Ready", UDim2.fromOffset(layout.statusW, 18), {
				Name = "Ready",
				Position = UDim2.fromOffset(statusX, math.floor(h / 2) - 9),
				Font = Theme.HeadingFont,
				TextSize = 12,
				TextColor3 = C.money,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Right,
			})
			local id = row.id
			local pick = CardKit.bigButton(frame, {
				name = "Pick",
				text = "PICK",
				kind = "good",
				height = layout.button,
				textSize = 15,
				onClick = function()
					if send({ kind = "pick", id = id }) then
						local button = frame:FindFirstChild("Pick")
						if button then
							button.Text = "…"
							button.Active = false
						end
					end
				end,
			})
			pick.Size = UDim2.fromOffset(layout.buttonW, layout.button)
			pick.Position = UDim2.new(1, -right, 0, buttonY)
		end
	end
	-- the words: his name and role (PICKED by it while in hospital), what he does, his health and pace
	local x = 6 + side + 12
	local room = math.max(80, statusX - 8 - x)
	local y = math.floor((h - WORDS) / 2)
	local nameW = math.min(room, CardKit.width(row.name, 16, Theme.HeadingFont) + 10)
	words(frame, row.name, 16, Vector2.new(x, y), nameW, 18, { Name = "CrewName", Font = Theme.HeadingFont, TextColor3 = if locked then K.secondary else K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local role = string.upper(row.role) .. (if hospital and row.pick then " · PICKED" else "")
	local roleW = math.min(math.max(0, room - nameW - 6), CardKit.width(role, 11, Theme.HeadingFont) + 14)
	if roleW > 24 then
		local chip = Ui.label(frame, role, UDim2.fromOffset(roleW, 18), {
			Name = "Role",
			Position = UDim2.fromOffset(x + nameW + 6, y),
			BackgroundColor3 = K.raised,
			BackgroundTransparency = 0,
			Font = Theme.HeadingFont,
			TextSize = 11,
			TextColor3 = if locked then C.dim else AMBER,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		Ui.corner(chip, 9)
	end
	words(frame, row.ability, 12, Vector2.new(x, y + 20), room, 28, { Name = "Ability", Font = Theme.Font, TextColor3 = if locked then C.dim else K.secondary, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	local stats = if def then `♥ {def.Health} health · {string.format("×%.1f", def.Speed)} pace` else ""
	words(frame, stats, 11, Vector2.new(x, y + 49), room, 13, { Name = "Stats", Font = Theme.HeadingFont, TextColor3 = C.faint, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
end

draw = function(keepScroll: boolean)
	if not opened then
		return
	end
	local size = Ui.screenSize()
	local layout = CrewUi.layout(size.X, size.Y, Ui.touchLayout())
	local state = current
	local key = stateKey(state, layout)
	if card and key == shownKey then
		return -- (nothing it shows changed: no redraw, a tap is never lost)
	end
	shownKey = key
	local list = card and card:FindFirstChild("Crew") and card:FindFirstChild("Crew"):FindFirstChild("List")
	local scroll = if keepScroll and list then list.CanvasPosition else Vector2.zero
	local selected = Ui.gamepadSelection()
	local heldInside = card ~= nil and selected ~= nil and selected:IsDescendantOf(card)
	if card then
		card:Destroy()
	end
	local root = ensureGui()
	-- a shade over the world (the touch buttons too): a tap beside the card closes it; Modal frees the mouse
	card = Ui.make("TextButton", {
		Name = "CrewShade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		Modal = true,
	}, root)
	card.Activated:Connect(CrewUi.close)
	local frame = Ui.make("Frame", {
		Name = "Crew",
		Size = UDim2.fromOffset(layout.w, layout.h),
		Position = UDim2.fromOffset(layout.x, layout.y),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.WindowTransparency,
		BorderSizePixel = 0,
		Active = true,
		SelectionGroup = true, -- (the gamepad's selection stays in the window)
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, card)
	Ui.make("UIScale", { Name = "Scale", Scale = layout.scale }, frame)
	Ui.corner(frame, Config.UiKit.Corner)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.rule, Thickness = 1 }, frame)
	-- the header: the title, who comes, the ✕
	local wide = layout.w - (layout.pad * 2 + layout.close + 8)
	Ui.label(frame, "👥 YOUR CREW", UDim2.fromOffset(wide, 24), { Name = "Title", Position = UDim2.fromOffset(layout.pad, 10), Font = Theme.HeadingFont, TextSize = 18, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	Ui.label(frame, subtitleOf(state), UDim2.fromOffset(wide, 16), { Name = "Subtitle", Position = UDim2.fromOffset(layout.pad, 33), TextSize = 12, TextColor3 = if state and state.instead then K.warn else K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	local close = Ui.closeButton(frame, CrewUi.close)
	close.Size = UDim2.fromOffset(layout.close, layout.close)
	close.Position = UDim2.new(1, -6, 0, 6)
	close.AnchorPoint = Vector2.new(1, 0)
	-- the rows (a list that scrolls when the screen is short)
	local rows: { Row } = if state then state.rows else {}
	local tall = #rows * (layout.rowH + layout.gap) - layout.gap
	local scrolls = tall > layout.listH
	local listFrame = Ui.make("ScrollingFrame", {
		Name = "List",
		Size = UDim2.fromOffset(layout.rowW, layout.listH),
		Position = UDim2.fromOffset(layout.pad, layout.listY),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = if scrolls then SCROLLBAR else 0,
		ScrollBarImageColor3 = K.line,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.fromOffset(0, math.max(0, tall)),
		CanvasPosition = Vector2.new(0, math.clamp(scroll.Y, 0, math.max(0, tall - layout.listH))),
	}, frame)
	local rowW = layout.rowW - (if scrolls then SCROLLBAR + 2 else 0)
	for index, row in rows do
		drawRow(listFrame, row, index, layout, rowW, state :: State)
	end
	local first: any = nil
	for _, row in rows do
		local made = listFrame:FindFirstChild(`Crew_{row.id}`)
		local button = made and (made:FindFirstChild("Pick") or made:FindFirstChild("Picked"))
		if button then
			first = button
			break
		end
	end
	if not keepScroll or heldInside then
		Ui.gamepadFocus(first or close) -- (a redraw while open moves the gamepad only when its selection went with it)
	end
end

-- The countdowns in place (a redraw only when a price or a state changes).
local function follow()
	local state = current
	if not state then
		return
	end
	local due = false
	for _, row in state.rows do
		if row.state == "hospital" and row.have then
			local left = leftOf(row, state)
			if left <= 0 then
				due = true
			end
			local frame = card and card:FindFirstChild("Crew")
			local list = frame and frame:FindFirstChild("List")
			local made = list and list:FindFirstChild("Crew_" .. row.id)
			local label = made and made:FindFirstChild("Left")
			if label then
				label.Text = `🏥 {CrewRules.clock(left)}`
			end
		end
	end
	if due and not asked then
		asked = true -- (out of hospital: the server's word on it, once)
		send({ kind = "state" })
	end
	if opened then
		draw(true)
	end
end

local function amount(value: any): number?
	return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then value else nil
end

local function text(value: any, fallback: string): string
	return if type(value) == "string" then value else fallback
end

local function setState(raw: any)
	local rows: { Row } = {}
	if type(raw.rows) == "table" then
		for _, r in raw.rows do
			if type(r) == "table" and CrewRules.def(r.id) then
				table.insert(rows, {
					id = r.id,
					name = text(r.name, r.id),
					icon = text(r.icon, "👷"),
					role = text(r.role, ""),
					ability = text(r.ability, ""),
					carry = text(r.carry, ""),
					have = r.have == true,
					pick = r.pick == true,
					state = text(r.state, "locked"),
					left = amount(r.left) or 0,
					price = amount(r.price) or 0,
				})
			end
		end
	end
	local was = current
	current = {
		rows = rows,
		pick = text(raw.pick, Config.Crew.Default),
		comes = if type(raw.comes) == "string" then raw.comes else nil,
		instead = raw.instead == true,
		money = amount(raw.money) or (if was then was.money else 0),
		at = now(),
	}
	asked = false
	if opened then
		draw(true)
	end
end

function CrewUi.open()
	local was = opened
	opened = true
	shownKey = ""
	if not was then
		local onOpen = CrewUi.onOpen
		if onOpen then
			onOpen()
		end
	end
	draw(false)
	if not current and remote then
		send({ kind = "state" })
	end
end

local function onEvent(message: any)
	if type(message) ~= "table" then
		return
	end
	if message.kind == "state" then
		setState(message)
	elseif message.kind == "open" then
		CrewUi.open()
	end
end

-- The money from the player's State (a sale, the stands' income): DISCHARGE follows it while open.
local function onMoney(state: any)
	local money = if type(state) == "table" then amount(state.money) else nil
	local live = current
	if money and live and money ~= live.money then
		live.money = money
		if opened then
			draw(true)
		end
	end
end

-- ── The down ring ───────────────────────────────────────────────────────────

local function makeRing(model: Instance, adornee: Instance, untilAt: number): Ring
	local size = R.Size
	local width = math.max(size, 132)
	local billboard = Ui.make("BillboardGui", {
		Name = "CrewDownRing",
		Size = UDim2.fromOffset(width, size + LABEL_H + 4),
		StudsOffset = Vector3.new(0, 3.4, 0),
		AlwaysOnTop = true,
		MaxDistance = R.Range,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Adornee = adornee,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))
	local ring = Ui.make("Frame", { Name = "Ring", Size = UDim2.fromOffset(size, size), Position = UDim2.new(0.5, -size / 2, 0, 0), BackgroundTransparency = 1 }, billboard)
	local disc = Ui.make("Frame", { Name = "Disc", Size = UDim2.fromOffset(size - 2 * DOT - 8, size - 2 * DOT - 8), Position = UDim2.fromOffset(DOT + 4, DOT + 4), BackgroundColor3 = K.charcoal, BackgroundTransparency = 0.2, BorderSizePixel = 0 }, ring)
	Ui.corner(disc, size)
	local dots: { any } = {}
	local radius = size / 2 - DOT / 2 - 1
	for n = 1, DOTS do
		local angle = (n - 1) / DOTS * 2 * math.pi
		local dot = Ui.make("Frame", {
			Name = `Dot{n}`,
			Size = UDim2.fromOffset(DOT, DOT),
			Position = UDim2.fromOffset(size / 2 + radius * math.sin(angle) - DOT / 2, size / 2 - radius * math.cos(angle) - DOT / 2),
			BackgroundColor3 = AMBER,
			BorderSizePixel = 0,
		}, ring)
		Ui.corner(dot, DOT)
		table.insert(dots, dot)
	end
	local left = Ui.label(ring, "", UDim2.fromScale(1, 1), { Name = "Left", Font = Theme.DisplayFont, TextSize = 28, TextColor3 = K.text, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center })
	local kind = model:GetAttribute("CrewKind")
	local def = CrewRules.def(kind)
	local name = if def then string.upper(def.Name) else "HIM"
	local label = Ui.label(billboard, `REVIVE {name}`, UDim2.fromOffset(width, LABEL_H), {
		Name = "Revive",
		Position = UDim2.fromOffset(0, size + 4),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.2,
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = K.text,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Ui.corner(label, 6)
	return { gui = billboard, dots = dots, left = left, untilAt = untilAt, lit = -1 }
end

local function paintRing(ring: Ring, clock: number)
	local seconds = Config.Crew.Down.Seconds
	local left = math.max(0, ring.untilAt - clock)
	ring.left.Text = tostring(math.ceil(left))
	local lit = math.clamp(math.ceil(left / seconds * DOTS), 0, DOTS)
	local hurry = left <= seconds / 3
	if lit ~= ring.lit or hurry then
		ring.lit = lit
		for n, dot in ring.dots do
			local on = n <= lit
			dot.BackgroundColor3 = if not on then SPENT elseif hurry then RED else AMBER
			dot.BackgroundTransparency = if on then 0 else 0.35
		end
	end
	ring.left.TextColor3 = if hurry then RED else K.text
end

local function lookAtRings(clock: number)
	local seen: { [Instance]: boolean } = {}
	for _, model in CollectionService:GetTagged(DOWN_TAG) do
		local untilAt = model:GetAttribute("CrewDownUntil")
		local adornee = if model:IsA("Model") then (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) else nil
		if type(untilAt) == "number" and adornee and model.Parent then
			seen[model] = true
			local was: Ring? = rings[model]
			if was and was.untilAt ~= untilAt then
				was.gui:Destroy() -- (down again: a new ring, its seconds full)
				was = nil
			end
			local ring: Ring = was or makeRing(model, adornee, untilAt)
			rings[model] = ring
			paintRing(ring, clock)
		end
	end
	for model, ring in rings do
		if not seen[model] then
			ring.gui:Destroy()
			rings[model] = nil
		end
	end
end

function CrewUi.rings(): { [Instance]: any }
	local out: { [Instance]: any } = {}
	for model, ring in rings do
		out[model] = ring.gui
	end
	return out
end

function CrewUi.step()
	local clock = now()
	lookAtRings(clock)
	if current then
		follow()
	end
end

function CrewUi.start()
	if started then
		return
	end
	started = true
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) and opened and not UserInputService:GetFocusedTextBox() then
			CrewUi.close()
		end
	end)
	GuiService.MenuOpened:Connect(CrewUi.close)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if opened then
				draw(true)
			end
		end)
	end
	RunService.Heartbeat:Connect(function()
		local clock = now()
		if clock < nextLook then
			return
		end
		nextLook = clock + R.Every
		local ok, err = pcall(CrewUi.step :: any)
		if not ok then
			warn(`[CrewUi] {err}`)
		end
	end)
	task.spawn(function()
		local ok, found = pcall(Net.get, "Crew")
		if not ok then
			warn(`[CrewUi] no Crew remote: {found}`)
			return
		end
		remote = found
		found.OnClientEvent:Connect(onEvent)
		found:FireServer({ kind = "state" })
		local hasState, state = pcall(Net.get, "State")
		if hasState then
			state.OnClientEvent:Connect(onMoney)
		end
	end)
end

return CrewUi
