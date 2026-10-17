--!strict
-- 6.1, the key hints (the owner's wish: the player sees which keys do what): a quiet strip right under the HUD's top
-- right anchor (client/Hud.luau's "HudButtons"), right-aligned, small muted text on no background, one or two short
-- lines of key chips for what the keys do NOW (the real bindings of the client's modules; sandboxLines):
--   on foot   [E] Use · [G] Put down (something in your arms: Carrying) · [LMB/F] Grip (8.1: a piece with a grip, the
--             timing check: client/CarryGripUi.luau) · [O] List (on a move: client/MovingHud.luau) · [T] Chat (hold: on
--             a move, client/QuickChat.luau)
--   8.5 Danny's clipboard (orders mode; shared/SandboxPad.luau's "clipboard", "stow", "dannygive"): while Danny works for
--             your move and your hands are free, [Q] Clipboard (a gamepad's R1); with it out [E/LMB] Give to Danny in
--             place of [E] Use (E by a piece gives it: client/DannyOrders.luau; bright: the mode; R1) and [Q] Put away (B)
-- Hidden with the HUD and while a window or a dialog covers the game (KeyHints.covered, set by the client's Main). The
-- KEYS chip (a click, or F1) folds and unfolds it; the choice stays for the session (open at first). Looked at every
-- Check seconds; the text is set only when it changed. 6.5: folded it is a small "? KEYS [F1]" chip on a charcoal
-- backing.
-- 8.3 keys (shared/SandboxPad.luau's actions, client/PadGlyph.luau): the strip is for the device used now. A computer:
-- the keys. A gamepad used last (a computer's or a console's): its buttons' glyphs (the platform's pictures,
-- UserInputService:GetImageForKeyCode; else the button's word in brackets, "[R2]") before each word, in rows of their
-- own, only what a button does (X Use, B Put down, R2 Grip; the list and the chat have none), the KEYS chip without its
-- F1. A touch screen: none (its buttons say what they do). It changes at once when the last input's type does
-- (PadGlyph.watch) and at the next look anyway.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SandboxPad = require(Shared.SandboxPad) -- 8.3 keys
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local PadGlyph = require(script.Parent.PadGlyph) -- 8.3 keys: the device, the gamepad's glyphs

local KeyHints = {}

-- Set by client/Main.client.luau: does a window or a dialog cover the game now?
KeyHints.covered = nil :: (() -> boolean)?

local K = Config.KeyHints
local TOGGLE = Enum.KeyCode.F1
local player = Players.LocalPlayer

local open = true -- the session's choice (open at first: F1 or a click folds it)
local root: any = nil
local lines: { any } = {}
local MAX_LINES = 5 -- (narrow: the chips flow onto more, shorter lines; more than this folds the strip)
local chip: any = nil
local shown = ""
local device: SandboxPad.Device = "keys" -- 8.3 keys: what the strip is drawn for now
local padRows: { any } = {} -- 8.3 keys: a gamepad's rows of glyphs and words
local padShown = false -- (a gamepad's rows drawn: cleared when the keys come back)
local glyphs: { [string]: string } = {} -- 8.3 keys: a button's picture (asked once a device)
local GLYPH = K.TextSize + 6 -- 8.3 keys: a glyph's size (px)
local PAD_GAP = 10 -- 8.3 keys: px between a gamepad's chips

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

local KEY = hex(P.ink)
local WORD = hex(P.ink2)

type Chip = { rich: string, plain: string, word: string, on: boolean?, pads: { string }? }

-- One chip: the key bright, its word muted (`on`: the word bright too, the hand you hold). 8.3 keys: `action` (the
-- sandbox's, shared/SandboxPad.luau) gives it the gamepad's buttons for when one is used.
local function chipText(key: string, word: string, on: boolean?, action: string?): Chip
	return {
		rich = `<font color="{KEY}">[{key}]</font> <font color="{if on then KEY else WORD}">{word}</font>`,
		plain = `[{key}] {word}`,
		word = word,
		on = on,
		pads = if action then SandboxPad.pads(action) else nil,
	}
end

-- 8.3 keys: a chip for the device drawn now (with a gamepad only one a button does: the horn, the list and the chat
-- have none).
local function add(list: { Chip }, item: Chip)
	if device ~= "pad" or (item.pads ~= nil and #item.pads > 0) then
		table.insert(list, item)
	end
end

local function keyboard(): boolean
	if Ui.touchLayout() then
		return false
	end
	return UserInputService.KeyboardEnabled
end

-- The game's keys (see the header): on foot, a piece in your arms, Danny's clipboard, a move's list and chat
-- (8.3 keys: each with its action, shared/SandboxPad.luau: with a gamepad its buttons, or no chip).
local function sandboxLines(character: Model): { { Chip } }
	local first: { Chip } = {}
	local carrying = character:GetAttribute("Carrying") ~= nil
	local orders = not carrying and player:GetAttribute("MoveHelper") == "hired" and character:GetAttribute("ClipboardHeld") == true
	if orders then
		-- 9.0 the clipboard out: E by a piece gives it to Danny (client/DannyOrders.luau's prompts in place of Pick up), a
		-- click the one you point at (a gamepad: R1, the action's)
		local who = player:GetAttribute("MoveHelperName") -- (10.1 the crew's helper: his own name)
		add(first, chipText("E/LMB", `Give to {if type(who) == "string" and who ~= "" then who else Config.MoveHelper.Name}`, true, "dannygive"))
	else
		add(first, chipText("E", "Use", nil, "use"))
	end
	if carrying then
		add(first, chipText("G", "Put down", nil, "putdown"))
	elseif player:GetAttribute("MoveHelper") == "hired" then
		-- 8.5 Danny's clipboard (orders mode, client/DannyOrders.luau): only while he works for your move
		local key = Config.MoveHelper.Clipboard.Key
		if orders then
			add(first, chipText(key, "Put away", nil, "stow"))
		else
			add(first, chipText(key, "Clipboard", nil, "clipboard"))
		end
	end
	if type(character:GetAttribute("CarryGrip")) == "string" then
		add(first, chipText("LMB/F", "Grip", nil, "grip"))
	end
	local second: { Chip } = {}
	local onMove = player:GetAttribute("MoveWith") ~= nil
	if onMove then
		add(second, chipText("O", "List", nil, "list"))
		add(second, chipText("T", "Chat (hold)", nil, "chat"))
	end
	return if #second > 0 then { first, second } else { first }
end

-- What the strip says now: two groups of chips (each a line when there is room).
local function linesNow(): { { Chip } }
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return {}
	end
	if humanoid.SeatPart ~= nil then
		return {} -- (no seat of the game's has keys of its own)
	end
	return sandboxLines(character)
end

local GAP_TEXT = "  "

local function width(text: string): number
	return TextService:GetTextSize(text, K.TextSize, Theme.Font, Vector2.new(10000, 100)).X
end

-- The groups as lines no wider than `room` px (a group that fits stays one line). Nil when more than MAX_LINES.
local function flow(groups: { { Chip } }, room: number): { string }?
	local out: { string } = {}
	for _, group in groups do
		local rich: { string } = {}
		local plain: { string } = {}
		for _, item in group do
			local try = table.clone(plain)
			table.insert(try, item.plain)
			if #plain > 0 and width(table.concat(try, GAP_TEXT)) > room then
				table.insert(out, table.concat(rich, GAP_TEXT))
				rich, plain = {}, {}
			end
			table.insert(rich, item.rich)
			table.insert(plain, item.plain)
		end
		if #rich > 0 then
			table.insert(out, table.concat(rich, GAP_TEXT))
		end
	end
	if #out > MAX_LINES then
		return nil
	end
	return out
end

-- 8.3 keys: a button's picture (the platform's; "" none: its word in brackets), asked once a device.
local function glyphOf(pad: string): string
	local image = glyphs[pad]
	if image == nil then
		image = PadGlyph.image(pad)
		glyphs[pad] = image
	end
	return image
end

-- 8.3 keys: a gamepad's chip's width (px): its glyphs (or their words in brackets) and its word.
local function padWidth(item: Chip): number
	local w = width(item.word)
	local pads = item.pads
	if pads then
		for _, pad in pads do
			w += 3 + (if glyphOf(pad) ~= "" then GLYPH else width(`[{SandboxPad.button(pad)}]`))
		end
	end
	return w
end

-- 8.3 keys: a gamepad's chips in rows no wider than `room` px (as flow). Nil when more than MAX_LINES.
local function padFlow(groups: { { Chip } }, room: number): { { Chip } }?
	local out: { { Chip } } = {}
	for _, group in groups do
		local row: { Chip } = {}
		local used = 0
		for _, item in group do
			local w = padWidth(item)
			if #row > 0 and used + PAD_GAP + w > room then
				table.insert(out, row)
				row, used = {}, 0
			end
			used += (if #row > 0 then PAD_GAP else 0) + w
			table.insert(row, item)
		end
		if #row > 0 then
			table.insert(out, row)
		end
	end
	if #out > MAX_LINES then
		return nil
	end
	return out
end

-- 8.3 keys: what a gamepad's rows show (the look's key: drawn again only when it changes).
local function padKey(rows: { { Chip } }): string
	local parts: { string } = {}
	for _, row in rows do
		for _, item in row do
			table.insert(parts, `{item.word}:{table.concat(item.pads or {}, "/")}:{item.on == true}`)
		end
		table.insert(parts, "\n")
	end
	return table.concat(parts, ",")
end

-- 8.3 keys: one row of a gamepad's chips, right-aligned like the keys' lines: each its buttons' glyphs (else their
-- words in brackets) and its word (nil: the row hidden and emptied).
local function drawPadRow(row: any, chips: { Chip }?)
	for _, child in row:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	row.Visible = chips ~= nil
	if not chips then
		return
	end
	for index, item in chips do
		local holder = Ui.make("Frame", {
			Name = `Chip{index}`,
			Size = UDim2.fromOffset(0, GLYPH),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			LayoutOrder = index,
		}, row)
		Ui.make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 3),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, holder)
		local pads: { string } = item.pads or {}
		for order, pad in pads do
			local image = glyphOf(pad)
			if image ~= "" then
				Ui.make("ImageLabel", {
					Name = "Pad",
					Size = UDim2.fromOffset(GLYPH, GLYPH),
					BackgroundTransparency = 1,
					ScaleType = Enum.ScaleType.Fit,
					Image = image,
					LayoutOrder = order,
				}, holder)
			else
				P.text(holder, `[{SandboxPad.button(pad)}]`, UDim2.fromOffset(0, GLYPH), {
					Name = "Key",
					AutomaticSize = Enum.AutomaticSize.X,
					Font = Theme.Font,
					TextSize = K.TextSize,
					TextColor3 = P.ink,
					TextStrokeTransparency = 0.75,
					LayoutOrder = order,
				})
			end
		end
		P.text(holder, item.word, UDim2.fromOffset(0, GLYPH), {
			Name = "Word",
			AutomaticSize = Enum.AutomaticSize.X,
			Font = Theme.Font,
			TextSize = K.TextSize,
			TextColor3 = if item.on then P.ink else P.ink2,
			TextStrokeTransparency = 0.75,
			LayoutOrder = 100,
		})
	end
end

-- The room left of the strip's right edge: up to the contract column (client/Hud.luau's TopStack) when it reaches
-- down beside the strip (6.1 review: on a narrower window the long first line ran over it).
local function roomFor(gui: any): number
	local right = gui.AbsolutePosition.X + root.Position.X.Offset -- (anchored at its right: the position is the right edge)
	local leftEdge = gui.AbsolutePosition.X + 8
	local column = gui:FindFirstChild("TopStack", true)
	if column and column:IsA("GuiObject") and column.Visible then
		local top = root.Position.Y.Offset + gui.AbsolutePosition.Y
		local bottom = top + MAX_LINES * (K.TextSize + 5) + K.TextSize + 4
		local c0, c1 = column.AbsolutePosition, column.AbsolutePosition + column.AbsoluteSize
		if c1.Y > top and c0.Y < bottom and c1.X > leftEdge then
			leftEdge = c1.X + 12
		end
	end
	return right - leftEdge
end

local function isOpen(): boolean
	return open
end

local function line(parent: Instance, order: number): any
	return P.text(parent, "", UDim2.fromOffset(0, K.TextSize + 4), {
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.Font,
		TextSize = K.TextSize,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.75,
		LayoutOrder = order,
	})
end

-- Under the HUD's top right anchor (it moves with the layout: followed every look).
local function place(gui: any)
	local buttons = gui:FindFirstChild("HudButtons")
	if not buttons or not root then
		return
	end
	local origin = gui.AbsolutePosition
	local corner = buttons.AbsolutePosition + buttons.AbsoluteSize
	local position = UDim2.fromOffset(math.floor(corner.X - origin.X + 0.5), math.floor(corner.Y - origin.Y + 4.5))
	if root.Position ~= position then
		root.Position = position
	end
end

local function build(gui: Instance)
	root = Ui.make("Frame", {
		Name = "KeyHints",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 1),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, root)
	chip = Ui.make("TextButton", {
		Name = "Toggle",
		Size = UDim2.fromOffset(0, K.TextSize + 8),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = P.surface, -- (6.5: a small chip on a faint charcoal backing, the mockup's)
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Font = Theme.HeadingFont,
		TextSize = K.TextSize - 1,
		TextColor3 = P.ink2,
		TextStrokeTransparency = 0.75,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = 0,
	}, root)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, chip)
	chip.Activated:Connect(function()
		open = not isOpen()
		shown = ""
	end)
	for index = 1, MAX_LINES do
		lines[index] = line(root, index)
	end
	-- 8.3 keys: a gamepad's rows (hidden until one is used in the sandbox)
	for index = 1, MAX_LINES do
		local row = Ui.make("Frame", {
			Name = `PadLine{index}`,
			Size = UDim2.fromOffset(0, GLYPH),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Visible = false,
			LayoutOrder = MAX_LINES + index,
		}, root)
		Ui.make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, PAD_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, row)
		padRows[index] = row
	end
end

local function update(gui: any)
	local covered = KeyHints.covered
	-- 8.3 keys: the strip is for the device used now (a gamepad used last: its glyphs, on a computer or a console; a
	-- touch screen: none)
	local now: SandboxPad.Device = PadGlyph.device()
	if now ~= device then
		device = now
		table.clear(glyphs) -- (another device: its pictures asked again)
	end
	local pad = device == "pad"
	local hide = not gui.Enabled or (not pad and not keyboard())
	if not hide and covered then
		local ok, value = pcall(covered)
		hide = ok and value == true
	end
	local groups = if hide then {} else linesNow()
	hide = hide or #groups == 0
	if root.Visible == hide then
		root.Visible = not hide
	end
	if hide then
		return
	end
	place(gui)
	local unfolded = isOpen()
	local texts: { string }? = {}
	local rows: { { Chip } }? = nil
	if unfolded and pad then
		rows = padFlow(groups, roomFor(gui)) -- 8.3 keys
		texts = if rows then {} else nil
	elseif unfolded then
		texts = flow(groups, roomFor(gui))
	end
	local squeezed = texts == nil -- (no room even on MAX_LINES lines: only the KEYS chip)
	local shownTexts: { string } = texts or {}
	local key = `{unfolded}|{squeezed}|{device}|{if rows then padKey(rows) else table.concat(shownTexts, "\n")}`
	if key == shown then
		return
	end
	shown = key
	-- (6.4.1: plain text: the game font has no "▴", it showed as a missing-glyph box; 8.3 keys: a gamepad has no F1)
	local f1 = if pad then "" else "  [F1]"
	chip.Text = if unfolded and not squeezed then `KEYS · HIDE{f1}` else `? KEYS{f1}`
	for index, label in lines do
		local text = shownTexts[index]
		label.Visible = text ~= nil and text ~= ""
		label.Text = text or ""
	end
	if rows or padShown then -- 8.3 keys: a gamepad's rows (emptied when the keys come back)
		for index, row in padRows do
			drawPadRow(row, if rows then rows[index] else nil)
		end
		padShown = rows ~= nil
	end
end

function KeyHints.start()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("ZombieDeliveryHud", 30)
	if not gui then
		warn("[KeyHints] no HUD to sit in")
		return
	end
	build(gui)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= TOGGLE or UserInputService:GetFocusedTextBox() then
			return
		end
		open = not isOpen()
		shown = ""
	end)
	-- 8.3 keys: a gamepad picked up or put down: the strip for it at once
	PadGlyph.watch(function()
		shown = ""
		pcall(update, gui)
	end)
	task.spawn(function()
		while root and root.Parent do
			local ok, err: any = pcall(function()
				update(gui)
			end)
			if not ok then
				warn(`[KeyHints] {err}`)
			end
			task.wait(K.Check)
		end
	end)
end

return KeyHints
