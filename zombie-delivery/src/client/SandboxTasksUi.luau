--!strict
-- 8.2 SANDBOX: the daily tasks' TASKS panel (the owner: "daily tasks that bring players back"). server/SandboxTasks.luau
-- decides everything (shared/SandboxTasks.luau, Config.SandboxTasks); this shows its state and asks through the
-- "SandboxTasks" remote: { kind = "state" } when it needs the state, { kind = "claim", slot } on CLAIM.
--   * THE CHIP: "📋 TASKS 1/3" (the dailies done today; the key Config.SandboxTasks.Key on a computer, J) in a ScreenGui
--     of its own ("SandboxTasksChip"), just under client/SandboxHud.luau's money block: its place and scale are read
--     from the ScreenGui "SandboxHud" (its MoneyBlock: under its bottom, at its left, at its scale; followed when it
--     moves or grows), never written there. A spacer of the chip's size follows SandboxHud's in client/Hud.luau's left
--     column (Hud.topSlot "sandbox", second), so the HUD's toasts flow under the chip. A reward waiting: the chip goes
--     green with a badge (how many). Shown with SandboxHud (not on the start screen). A touch screen: a finger's size.
--   * THE PANEL (ScreenGui "SandboxTasksUi"): the key or the chip opens and closes it. "📋 TASKS" and when the dailies
--     are new ("New tasks in 5 h 12 min", counting down while open), the three dailies (Task_1 … Task_3: the emoji, the
--     title, "3 / 10" or "$150 / $400" and a progress bar, the reward in money green, a green CLAIM $250 once done,
--     ✓ CLAIMED after), the bonus for all three (Bonus: "1 / 3 done" or CLAIM), "THIS WEEK" and the weekly (Task_weekly,
--     gold). On a computer it hangs under the chip; on a screen too short for one column (a phone held sideways) the
--     bonus and the weekly stand beside the dailies, centred. Modal: the mouse is free while it is open; ✕, the key,
--     ESC, the gamepad's B, the Roblox menu or a tap beside it close it.
--   * A task done (the server's "done"): a toast ("✅ Task done: … · +$250 to claim in TASKS (J)") and the task sound;
--     a claim paid ("claimed"): a toast and the money's sound.
--   SandboxTasksUi.start()               listens (once; nothing when Config.Sandbox.On is false)
--   SandboxTasksUi.open() / close() / toggle() / isOpen()
--   SandboxTasksUi.state()               the last state (nil: none yet)
--   SandboxTasksUi.layout(W, H, touch, dock?)   the panel on a W × H screen (px under Roblox's top bar); dock: the chip's
--                                        bottom left (a computer's panel hangs there)
--   SandboxTasksUi.amount(n, unit) / left(seconds)   "3" / "$150", "5 h 12 min"
--   SandboxTasksUi.notify                a hook: the toasts (else client/Hud.luau's toast)
-- Presentation only.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)

local SandboxTasksUi = {}

SandboxTasksUi.notify = nil :: ((text: string) -> ())?

local K = Theme.Contract
local C = CardKit.Color
local T = Config.SandboxTasks
local HUD = Config.SandboxHud

export type Row = {
	slot: any,
	id: string,
	icon: string,
	title: string,
	target: number,
	progress: number,
	unit: string?,
	money: number,
	done: boolean,
	claimed: boolean,
	weekly: boolean,
}
export type Bonus = { money: number, done: boolean, claimed: boolean, count: number, total: number }
export type State = { daily: { Row }, bonus: Bonus, weekly: Row?, dayLeft: number, weekLeft: number, ready: number, at: number }
export type Layout = {
	touch: boolean,
	scale: number, -- the panel's UIScale
	x: number, -- its top left on the screen (px)
	y: number,
	w: number, -- its size (unscaled)
	h: number,
	pad: number,
	header: number,
	close: number, -- the ✕'s side
	columns: number, -- 1: everything under each other; 2: the bonus and the weekly beside the dailies
	colW: number, -- a column's width
	rowH: number,
	gap: number,
	bonusH: number,
	labelH: number,
	button: number, -- CLAIM's height
	buttonW: number,
}

local COLUMN = 440 -- a column's width (unscaled px): the longest title whole beside CLAIM
local GAP = 6
local LABEL = 18 -- "THIS WEEK · …"
local CHIP_GAP = 6 -- px at the block's scale between the money block and the chip

local started = false
local remote: RemoteEvent? = nil
local current: State? = nil
local opened = false
local shownKey = ""
local panelGui: any = nil
local shade: any = nil -- the panel's shade over the screen (the panel: shade's Tasks)
local parts: { [string]: any } = {} -- the chip: gui, chip, label, key, badge, stroke, scale, spacer
local hudGui: any = nil -- the ScreenGui "SandboxHud"
local key: Enum.KeyCode? = nil
local arrangeQueued = false
local pressedAt: { [string]: number } = {}
local opens = 0 -- the panel's opening (its countdown's loop stops with another)

local function sandboxOn(): boolean
	local sandbox = (Config :: any).Sandbox
	return type(sandbox) == "table" and sandbox.On == true
end

-- ── Words (pure) ────────────────────────────────────────────────────────────

-- 5 h 12 min, 3 d 4 h, 12 min, 40 s
function SandboxTasksUi.left(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 86400 then
		return `{s // 86400} d {(s % 86400) // 3600} h`
	elseif s >= 3600 then
		return `{s // 3600} h {(s % 3600) // 60} min`
	elseif s >= 60 then
		return `{s // 60} min`
	end
	return `{s} s`
end

-- A count, or money ("$" unit).
function SandboxTasksUi.amount(n: number, unit: string?): string
	return if unit == "$" then Ui.money(n) else tostring(math.floor(n))
end

-- ── The layout (pure) ───────────────────────────────────────────────────────

function SandboxTasksUi.layout(W: number, H: number, touch: boolean, dock: Vector2?): Layout
	local margin = if touch then 8 else 16
	local scale = if touch
		then math.clamp(math.min(W / 860, H / 380), 0.8, Ui.MaxScale)
		else math.max(Ui.scaleFor(Vector2.new(W, H)), 0.7)
	local function plan(s: number, columns: number): Layout
		local pad = if touch then 10 else 12
		local button = if touch then math.max(36, math.ceil(Ui.MinTouch / s)) else 30
		local close = if touch then math.max(36, math.ceil(Ui.MinTouch / s)) else 32
		local header = math.max(48, close + 8)
		local rowH = math.max(56, button + 14)
		local bonusH = math.max(40, button + 8)
		local daily = 3 * rowH + 2 * GAP
		local week = bonusH + GAP + LABEL + rowH
		local w = if columns == 1 then COLUMN + 2 * pad else 2 * COLUMN + GAP + 2 * pad
		local h = header + (if columns == 1 then daily + GAP + week else math.max(daily, week)) + pad
		return {
			touch = touch,
			scale = s,
			x = 0,
			y = 0,
			w = w,
			h = h,
			pad = pad,
			header = header,
			close = close,
			columns = columns,
			colW = COLUMN,
			rowH = rowH,
			gap = GAP,
			bonusH = bonusH,
			labelH = LABEL,
			button = button,
			buttonW = if touch then 96 else 88, -- (CLAIM's least width)
		}
	end
	local room = H - 2 * margin
	local layout = plan(scale, 1)
	if layout.h * scale > room or layout.w * scale > W - 2 * margin then
		layout = plan(scale, 2)
	end
	if layout.w * scale > W - 2 * margin or layout.h * scale > room then
		-- (still too big: smaller, the buttons a finger's size all the same)
		local fit = math.max(0.5, math.min((W - 2 * margin) / layout.w, room / layout.h))
		layout = plan(fit, layout.columns)
		fit = math.max(0.5, math.min(fit, (W - 2 * margin) / layout.w, room / layout.h))
		layout.scale = fit
	end
	local s = layout.scale
	-- a computer: it hangs under the chip (a little smaller when the room under it is short: the chat open)
	local under = if dock then H - margin - (dock.Y + 8) else 0
	if dock and not touch and layout.columns == 1 and layout.h * math.max(0.7, math.min(s, under / layout.h)) <= under + 0.5 then
		s = math.max(0.7, math.min(s, under / layout.h))
		layout.scale = s
		layout.x = math.floor(math.clamp(dock.X, margin, math.max(margin, W - margin - layout.w * s)))
		layout.y = math.floor(dock.Y + 8)
	else
		layout.x = math.floor((W - layout.w * s) / 2)
		layout.y = math.floor((H - layout.h * s) / 2)
	end
	return layout
end

-- ── Sending ─────────────────────────────────────────────────────────────────

-- One request a slot at most every 1.5 s (a double tap is one claim).
local function send(message: { [string]: any }): boolean
	local id = `{message.kind}:{tostring(message.slot)}`
	local now = os.clock()
	if pressedAt[id] and now - pressedAt[id] < 1.5 then
		return false
	end
	pressedAt[id] = now
	local target = remote
	if target then
		target:FireServer(message)
	end
	return true
end

local function toast(text: string)
	local notify = SandboxTasksUi.notify
	if notify then
		notify(text)
		return
	end
	pcall(function()
		require(script.Parent.Hud).toast(text)
	end)
end

local function sound(name: string)
	pcall(function()
		local play = (require(script.Parent.Sounds) :: any).play
		if type(play) == "function" then
			play(name)
		end
	end)
end

-- ── The state ───────────────────────────────────────────────────────────────

local function number(value: any): number?
	return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then value else nil
end

local function rowFrom(raw: any, weekly: boolean): Row?
	if type(raw) ~= "table" or type(raw.title) ~= "string" or type(raw.id) ~= "string" then
		return nil
	end
	local target = number(raw.target)
	if not target or target < 1 then
		return nil
	end
	return {
		slot = if weekly then "weekly" else number(raw.slot),
		id = raw.id,
		icon = if type(raw.icon) == "string" then raw.icon else "📋",
		title = raw.title,
		target = target,
		progress = math.clamp(number(raw.progress) or 0, 0, target),
		unit = if raw.unit == "$" then "$" else nil,
		money = math.max(0, number(raw.money) or 0),
		done = raw.done == true,
		claimed = raw.claimed == true,
		weekly = weekly,
	}
end

local function stateFrom(raw: any): State
	local daily: { Row } = {}
	if type(raw.daily) == "table" then
		for _, item in raw.daily do
			local row = rowFrom(item, false)
			if row and row.slot ~= nil then
				table.insert(daily, row)
			end
		end
	end
	local bonus = if type(raw.bonus) == "table" then raw.bonus else {}
	local done = 0
	for _, row in daily do
		done += if row.done then 1 else 0
	end
	return {
		daily = daily,
		bonus = {
			money = math.max(0, number(bonus.money) or T.AllDaily),
			done = bonus.done == true,
			claimed = bonus.claimed == true,
			count = number(bonus.count) or done,
			total = number(bonus.total) or #daily,
		},
		weekly = rowFrom(raw.weekly, true),
		dayLeft = math.max(0, number(raw.dayLeft) or 0),
		weekLeft = math.max(0, number(raw.weekLeft) or 0),
		ready = math.max(0, math.floor(number(raw.ready) or 0)),
		at = os.clock(),
	}
end

function SandboxTasksUi.state(): State?
	return current
end

-- s left of the dailies' (the weekly's) day now
local function leftNow(state: State, weekly: boolean): number
	return (if weekly then state.weekLeft else state.dayLeft) - (os.clock() - state.at)
end

-- ── The chip ────────────────────────────────────────────────────────────────

-- The scale the HUD's columns put on `object` (the UIScales above it multiplied, up to its ScreenGui).
local function scaleAbove(object: Instance): number
	local scale = 1
	local node = object.Parent
	while node and not node:IsA("PlayerGui") do
		for _, child in node:GetChildren() do
			if child:IsA("UIScale") then
				scale *= (child :: UIScale).Scale
			end
		end
		node = node.Parent
	end
	return scale
end

-- The money block of client/SandboxHud.luau (its ScreenGui "SandboxHud"), nil before it is there.
local function moneyBlock(): any
	if not hudGui or not hudGui.Parent then
		local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
		hudGui = if playerGui then playerGui:FindFirstChild("SandboxHud") else nil
		if hudGui and parts.gui then
			parts.gui.Enabled = hudGui.Enabled
			hudGui:GetPropertyChangedSignal("Enabled"):Connect(function()
				parts.gui.Enabled = hudGui.Enabled
			end)
		end
	end
	return if hudGui then hudGui:FindFirstChild("MoneyBlock") else nil
end

-- Where the chip goes (screen px) and its scale: under the money block at its scale; else in Hud's column; else the
-- top left at the screen's scale.
local function anchor(): (number, number, number)
	local block = moneyBlock()
	if block then
		local blockScale = block:FindFirstChildOfClass("UIScale")
		local scale = if blockScale then (blockScale :: UIScale).Scale else 1
		local at, size = block.AbsolutePosition, block.AbsoluteSize
		return at.X, at.Y + size.Y + CHIP_GAP * scale, scale
	end
	local spacer = parts.spacer
	if spacer then
		local at = spacer.AbsolutePosition
		return at.X, at.Y, math.max(0.6, scaleAbove(spacer))
	end
	return 16, 120, Ui.screenScale()
end

local function arrange()
	local chip = parts.chip
	if not chip then
		return
	end
	local touch = Ui.touchLayout()
	local x, y, scale = anchor()
	if touch then
		scale = math.max(scale, HUD.TouchScale)
	end
	parts.scale.Scale = scale
	local state = current
	local done, total, ready = 0, T.Daily, 0
	if state then
		done, total, ready = state.bonus.count, math.max(state.bonus.total, #state.daily), state.ready
	end
	local text = `📋 TASKS {done}/{total}`
	parts.label.Text = text
	local keyShown = not touch and key ~= nil
	parts.key.Visible = keyShown
	parts.badge.Visible = ready > 0
	parts.badge.Text = tostring(ready)
	local chipH = HUD.Chip
	local chipW = CardKit.width(text, HUD.ChipText, Theme.HeadingFont) + 24 + (if keyShown then 28 else 0) + (if ready > 0 then 26 else 0)
	if touch then
		chipH = math.max(chipH, math.ceil(Ui.MinTouch / scale))
		chipW = math.max(chipW, math.ceil(Ui.MinTouch / scale))
	end
	chipW = math.ceil(chipW)
	chip.Size = UDim2.fromOffset(chipW, chipH)
	chip.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	chip.BackgroundColor3 = if ready > 0 then C.goodFace else K.row
	parts.stroke.Color = if ready > 0 then K.good else K.line
	parts.stroke.Transparency = if ready > 0 then 0.2 else 0.6
	parts.corner.CornerRadius = UDim.new(0, math.floor(chipH / 2))
	parts.label.Size = UDim2.new(1, -(12 + (if keyShown then 28 else 0) + (if ready > 0 then 26 else 0)), 1, 0)
	parts.badge.Position = UDim2.new(1, if keyShown then -36 else -8, 0.5, 0)
	local spacer = parts.spacer
	if spacer then
		-- (the room it takes in Hud's column, in the column's own px: the toasts start under it)
		local unit = math.max(0.05, scaleAbove(spacer))
		spacer.Size = UDim2.fromOffset(math.ceil(chipW * scale / unit), math.ceil(chipH * scale / unit))
	end
end

local function queueArrange()
	if arrangeQueued then
		return
	end
	arrangeQueued = true
	task.delay(0.05, function()
		arrangeQueued = false
		arrange()
	end)
end

local function buildChip()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Ui.make("ScreenGui", { Name = "SandboxTasksChip", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 1, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	parts.gui = gui
	local chip = Ui.make("TextButton", {
		Name = "TasksChip",
		BackgroundColor3 = K.row,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
	}, gui)
	parts.chip = chip
	parts.scale = Ui.make("UIScale", { Name = "Scale", Scale = 1 }, chip)
	parts.corner = Ui.make("UICorner", { CornerRadius = UDim.new(0, 16) }, chip)
	parts.stroke = Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.6 }, chip)
	parts.label = Ui.label(chip, "📋 TASKS", UDim2.fromScale(1, 1), {
		Name = "Label",
		Position = UDim2.fromOffset(12, 0),
		Font = Theme.HeadingFont,
		TextSize = HUD.ChipText,
		TextColor3 = K.text,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	parts.badge = Ui.label(chip, "1", UDim2.fromOffset(20, 20), {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		BackgroundColor3 = K.good,
		BackgroundTransparency = 0,
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = C.goldInk,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	})
	Ui.corner(parts.badge, 10)
	parts.key = Ui.label(chip, T.Key, UDim2.fromOffset(20, 20), {
		Name = "Key",
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = K.secondary,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.4 }, parts.key)
	Ui.corner(parts.key, 4)
	chip.MouseEnter:Connect(function()
		if not (current and current.ready > 0) then
			chip.BackgroundColor3 = K.raised
		end
	end)
	chip.MouseLeave:Connect(arrange)
	chip.Activated:Connect(function()
		CardKit.click()
		SandboxTasksUi.toggle()
	end)
	-- the room in client/Hud.luau's left column, under SandboxHud's (the HUD's toasts flow under the chip)
	local ok, hud = pcall(function(): any
		return require(script.Parent.Hud)
	end)
	if ok and type(hud) == "table" and type(hud.topSlot) == "function" then
		local made, slot = pcall(hud.topSlot, "sandbox")
		if made and slot then
			parts.spacer = Ui.make("Frame", { Name = "TasksSpace", Size = UDim2.fromOffset(120, 32), BackgroundTransparency = 1, LayoutOrder = 1 }, slot)
		end
	end
	if moneyBlock() == nil then
		gui.Enabled = false -- (until the HUD shows: SandboxHud's gui, found by the watch below)
	end
end

-- ── The panel ───────────────────────────────────────────────────────────────

local draw: () -> ()

local function ensurePanelGui(): any
	if panelGui then
		return panelGui
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	panelGui = Ui.make("ScreenGui", {
		Name = "SandboxTasksUi",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 6, -- (over the HUD and the touch buttons; the warehouse's windows over it)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	return panelGui
end

function SandboxTasksUi.isOpen(): boolean
	return opened
end

function SandboxTasksUi.close()
	if not opened then
		return
	end
	opened = false
	opens += 1
	if shade then
		Ui.gamepadRelease(panelGui)
		shade:Destroy()
		shade = nil
	end
	shownKey = ""
end

local function claim(slot: any)
	if send({ kind = "claim", slot = slot }) then
		local button = shade and shade:FindFirstChild(if slot == "bonus" then "Bonus" else `Task_{slot}`, true)
		local claimButton = button and button:FindFirstChild("Claim")
		if claimButton then
			claimButton.Text = "…"
			claimButton.Active = false
		end
	end
end

local function stateKey(layout: Layout): string
	local state = current
	local parts2 = { `{layout.w}x{layout.h}@{layout.scale}/{layout.x},{layout.y}` }
	if state then
		for _, row in state.daily do
			table.insert(parts2, `{row.id}:{row.target}:{row.progress}:{row.done}:{row.claimed}`)
		end
		local weekly = state.weekly
		if weekly then
			table.insert(parts2, `{weekly.id}:{weekly.target}:{weekly.progress}:{weekly.done}:{weekly.claimed}`)
		end
		table.insert(parts2, `{state.bonus.done}:{state.bonus.claimed}:{state.bonus.count}`)
	else
		table.insert(parts2, "none")
	end
	return table.concat(parts2, "|")
end

-- The right of a row: the reward, CLAIM, or ✓ CLAIMED, each as wide as its words. Returns the room it takes.
local function rightSide(frame: any, layout: Layout, money: number, done: boolean, claimed: boolean, slot: any, weekly: boolean): number
	if claimed then
		local w = CardKit.width("✓ CLAIMED", 12, Theme.HeadingFont) + 4
		Ui.label(frame, "✓ CLAIMED", UDim2.fromOffset(w, 20), {
			Name = "Claimed",
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Font = Theme.HeadingFont,
			TextSize = 12,
			TextColor3 = C.dim,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		return w + 10
	elseif done then
		local text = `CLAIM {Ui.money(money)}`
		local w = math.max(layout.buttonW, CardKit.width(text, 13, Theme.HeadingFont) + 22)
		local button = CardKit.bigButton(frame, {
			name = "Claim",
			text = text,
			kind = if weekly then "gold" else "good",
			height = layout.button,
			textSize = 13,
			onClick = function()
				claim(slot)
			end,
		})
		button.Size = UDim2.fromOffset(w, layout.button)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -6, 0.5, 0)
		return w + 6
	end
	local text = Ui.money(money)
	local w = CardKit.width(text, 17, Theme.DisplayFont) + 4
	Ui.label(frame, text, UDim2.fromOffset(w, 22), {
		Name = "Reward",
		Position = UDim2.new(1, -10, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Font = Theme.DisplayFont,
		TextSize = 17,
		TextColor3 = if weekly then C.gold else C.money,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	return w + 10
end

local function drawRow(parent: any, row: Row, layout: Layout, x: number, y: number)
	local w, h = layout.colW, layout.rowH
	local frame = Ui.make("Frame", {
		Name = `Task_{row.slot}`,
		Size = UDim2.fromOffset(w, h),
		Position = UDim2.fromOffset(x, y),
		BackgroundColor3 = K.row,
		BorderSizePixel = 0,
	}, parent)
	Ui.corner(frame, Config.UiKit.RowCorner)
	local edge = if row.claimed then K.line elseif row.done then (if row.weekly then C.gold else C.money) elseif row.weekly then C.gold else K.line
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = edge, Thickness = 1, Transparency = if row.done and not row.claimed then 0.3 elseif row.weekly then 0.5 else 0.8 }, frame)
	-- the emoji on charcoal
	local side = 36
	local picture = Ui.make("Frame", { Name = "Picture", Size = UDim2.fromOffset(side, side), Position = UDim2.fromOffset(8, math.floor((h - side) / 2)), BackgroundColor3 = K.charcoal, BorderSizePixel = 0 }, frame)
	Ui.corner(picture, 8)
	Ui.label(picture, row.icon, UDim2.fromScale(1, 1), { Name = "Emoji", TextSize = 20, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center })
	local right = rightSide(frame, layout, row.money, row.done, row.claimed, row.slot, row.weekly)
	-- the title, the progress, the bar
	local textX = 8 + side + 10
	local room = w - textX - right - 10
	local top = math.floor((h - 44) / 2)
	Ui.label(frame, row.title, UDim2.fromOffset(room, 18), {
		Name = "Title",
		Position = UDim2.fromOffset(textX, top),
		Font = Theme.HeadingFont,
		TextSize = 14,
		TextColor3 = if row.claimed then C.dim else K.text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local count = `{SandboxTasksUi.amount(row.progress, row.unit)} / {SandboxTasksUi.amount(row.target, row.unit)}`
	Ui.label(frame, count, UDim2.fromOffset(room, 14), {
		Name = "Progress",
		Position = UDim2.fromOffset(textX, top + 20),
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = K.secondary,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local track = Ui.make("Frame", { Name = "Bar", Size = UDim2.fromOffset(room, 5), Position = UDim2.fromOffset(textX, top + 38), BackgroundColor3 = K.track, BorderSizePixel = 0 }, frame)
	Ui.corner(track, 3)
	local share = math.clamp(row.progress / row.target, 0, 1)
	local fill = Ui.make("Frame", { Name = "Fill", Size = UDim2.fromScale(share, 1), BackgroundColor3 = if row.weekly then C.gold else C.money, BorderSizePixel = 0, Visible = share > 0 }, track)
	Ui.corner(fill, 3)
end

local function drawBonus(parent: any, state: State, layout: Layout, x: number, y: number)
	local w, h = layout.colW, layout.bonusH
	local bonus = state.bonus
	local frame = Ui.make("Frame", { Name = "Bonus", Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(x, y), BackgroundColor3 = K.recessed, BorderSizePixel = 0 }, parent)
	Ui.corner(frame, Config.UiKit.RowCorner)
	local done = bonus.done and not bonus.claimed
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = if done then C.money else K.line, Thickness = 1, Transparency = if done then 0.3 else 0.8 }, frame)
	local words = if bonus.claimed then "⭐ All three done: bonus claimed" else `⭐ All three done: +{Ui.money(bonus.money)}`
	local count = `{bonus.count} / {bonus.total} done`
	local right = if bonus.done or bonus.claimed
		then rightSide(frame, layout, bonus.money, bonus.done, bonus.claimed, "bonus", false)
		else CardKit.width(count, 12, Theme.HeadingFont) + 14
	Ui.label(frame, words, UDim2.fromOffset(w - 10 - right - 8, 18), {
		Name = "Words",
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = if bonus.claimed then C.dim else K.text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	if not (bonus.done or bonus.claimed) then
		Ui.label(frame, count, UDim2.fromOffset(right - 10, 18), {
			Name = "Count",
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Font = Theme.HeadingFont,
			TextSize = 12,
			TextColor3 = K.secondary,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	end
end

local function countdowns()
	local state = current
	local panel = shade and shade:FindFirstChild("Tasks")
	if not state or not panel then
		return
	end
	local subtitle = panel:FindFirstChild("Subtitle")
	if subtitle then
		subtitle.Text = `New tasks in {SandboxTasksUi.left(leftNow(state, false))}`
	end
	local label = panel:FindFirstChild("WeekLabel")
	if label then
		label.Text = `THIS WEEK · NEW IN {string.upper(SandboxTasksUi.left(leftNow(state, true)))}`
	end
end

draw = function()
	if not opened then
		return
	end
	local size = Ui.screenSize()
	local touch = Ui.touchLayout()
	local chip = parts.chip
	local dock = if chip and chip.Parent then Vector2.new(chip.AbsolutePosition.X, chip.AbsolutePosition.Y + chip.AbsoluteSize.Y) else nil
	local layout = SandboxTasksUi.layout(size.X, size.Y, touch, dock)
	local key2 = stateKey(layout)
	if shade and key2 == shownKey then
		countdowns()
		return -- (nothing it shows changed: no redraw, a tap is never lost)
	end
	shownKey = key2
	if shade then
		shade:Destroy()
	end
	local root = ensurePanelGui()
	-- a clear shade over the world: a tap beside the panel closes it; Modal frees the mouse
	shade = Ui.make("TextButton", {
		Name = "TasksShade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = if touch then 0.55 else 0.85,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		Modal = true,
	}, root)
	shade.Activated:Connect(SandboxTasksUi.close)
	local panel = Ui.make("Frame", {
		Name = "Tasks",
		Size = UDim2.fromOffset(layout.w, layout.h),
		Position = UDim2.fromOffset(layout.x, layout.y),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.WindowTransparency,
		BorderSizePixel = 0,
		Active = true,
	}, shade)
	Ui.make("UIScale", { Name = "Scale", Scale = layout.scale }, panel)
	Ui.corner(panel, Config.UiKit.Corner)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.rule, Thickness = 1 }, panel)
	-- the header: the title, when the dailies are new, the ✕
	local pad = layout.pad
	local wide = layout.w - (pad * 2 + layout.close + 8)
	local titleY = math.floor((layout.header - 40) / 2)
	Ui.label(panel, "📋 TASKS", UDim2.fromOffset(wide, 22), { Name = "Title", Position = UDim2.fromOffset(pad, titleY + 2), Font = Theme.HeadingFont, TextSize = 17, TextColor3 = K.text, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Left })
	Ui.label(panel, if current then "" else "Loading your tasks…", UDim2.fromOffset(wide, 16), { Name = "Subtitle", Position = UDim2.fromOffset(pad, titleY + 24), TextSize = 12, TextColor3 = K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	local close = Ui.closeButton(panel, SandboxTasksUi.close)
	close.Size = UDim2.fromOffset(layout.close, layout.close)
	close.Position = UDim2.new(1, -6, 0, math.floor((layout.header - layout.close) / 2))
	close.AnchorPoint = Vector2.new(1, 0)
	local state = current
	local first: any = nil
	if state then
		local y = layout.header
		for index, row in state.daily do
			drawRow(panel, row, layout, pad, y + (index - 1) * (layout.rowH + layout.gap))
		end
		local x2, y2 = pad, y + 3 * layout.rowH + 3 * layout.gap
		if layout.columns == 2 then
			x2, y2 = pad + layout.colW + layout.gap, y
		end
		drawBonus(panel, state, layout, x2, y2)
		y2 += layout.bonusH + layout.gap
		local weekly = state.weekly
		if weekly then
			Ui.label(panel, "THIS WEEK", UDim2.fromOffset(layout.colW, layout.labelH), { Name = "WeekLabel", Position = UDim2.fromOffset(x2 + 2, y2), Font = Theme.HeadingFont, TextSize = 11, TextColor3 = C.gold, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
			drawRow(panel, weekly, layout, x2, y2 + layout.labelH)
		end
		countdowns()
		for _, name in { "Task_1", "Task_2", "Task_3", "Bonus", "Task_weekly" } do
			local made = panel:FindFirstChild(name)
			local button = made and made:FindFirstChild("Claim")
			if button then
				first = button
				break
			end
		end
	end
	Ui.gamepadFocus(first or close)
end

function SandboxTasksUi.open()
	if opened then
		return
	end
	opened = true
	shownKey = ""
	opens += 1
	local mine = opens
	draw()
	if remote then
		send({ kind = "state" })
	end
	-- the countdowns while it is open (only the words: no redraw)
	task.spawn(function()
		while opened and opens == mine do
			task.wait(1)
			if opened and opens == mine then
				countdowns()
			end
		end
	end)
end

function SandboxTasksUi.toggle()
	if opened then
		SandboxTasksUi.close()
	else
		SandboxTasksUi.open()
	end
end

-- ── Listening ───────────────────────────────────────────────────────────────

local function onEvent(message: any)
	if type(message) ~= "table" then
		return
	end
	local kind = message.kind
	if kind == "state" then
		current = stateFrom(message)
		arrange()
		if opened then
			draw()
		end
	elseif kind == "done" and type(message.title) == "string" then
		local money = number(message.money) or 0
		local where = if Ui.touchLayout() then "TASKS" else `TASKS ({T.Key})`
		toast(`✅ {if message.weekly == true then "Weekly task" else "Task"} done: {message.title} · claim {Ui.money(money)} in {where}`)
		sound("task_done")
	elseif kind == "claimed" and type(message.title) == "string" then
		toast(`💰 {message.title}: +{Ui.money(number(message.money) or 0)}`)
		sound("cash")
	end
end

function SandboxTasksUi.start()
	if started or not sandboxOn() then
		return
	end
	started = true
	local ok, found = pcall(function(): any
		return (Enum.KeyCode :: any)[T.Key]
	end)
	key = if ok then found else nil
	buildChip()
	arrange()
	-- the key toggles the panel (not while typing, not on the start screen); ESC, the gamepad's B and the menu close it
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if UserInputService:GetFocusedTextBox() then
			return
		end
		if (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) and opened then
			SandboxTasksUi.close()
		elseif input.KeyCode == key and key ~= nil and not processed and parts.gui and parts.gui.Enabled then
			SandboxTasksUi.toggle()
		end
	end)
	GuiService.MenuOpened:Connect(SandboxTasksUi.close)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			queueArrange()
			if opened then
				task.defer(draw)
			end
		end)
	end
	-- SandboxHud's money block: followed when it moves, grows or scales (its gui's Enabled too); looked for until found
	task.spawn(function()
		for _ = 1, 60 do
			local block = moneyBlock()
			if block then
				block:GetPropertyChangedSignal("AbsolutePosition"):Connect(queueArrange)
				block:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueArrange)
				local blockScale = block:FindFirstChildOfClass("UIScale")
				if blockScale then
					blockScale:GetPropertyChangedSignal("Scale"):Connect(queueArrange)
				end
				arrange()
				return
			end
			task.wait(0.5)
		end
	end)
	task.spawn(function()
		local has, made = pcall(Net.get, "SandboxTasks")
		if not has then
			warn(`[SandboxTasksUi] no SandboxTasks remote: {made}`)
			return
		end
		remote = made
		made.OnClientEvent:Connect(onEvent)
		made:FireServer({ kind = "state" })
	end)
end

return SandboxTasksUi
