--!strict
-- 6.1, the key hints (the owner's wish: the player sees which keys do what): a quiet strip right under the HUD's top
-- buttons (MAP · PHONE, client/Hud.luau's "HudButtons"), right-aligned, small muted text on no background, one or
-- two short lines of key chips for what the keys do NOW (the real bindings of the client's modules):
--   on foot   [1] Fists [2] Bag [3] Gun (what you have; the one you hold bright) · [E] Use · [G] Put down (cargo in
--             your hands) · [X] Throw (only while a throw is possible: the server's ThrowReady / ThrowTo) · [E] Pick up
--             bag (while yours lies on the ground: BagDown) · [V] Punch / Strike
--   in a seat [W/S] Drive [A/D] Steer · [E] Get out · [F] Shoot
-- A keyboard only: hidden on a touch screen and with a gamepad alone. Hidden with the HUD and while a window, the phone,
-- a dialog or the result card covers the game (KeyHints.covered, the bottom bar's rule, set by the client's Main).
-- The KEYS chip (a click, or F1) folds and unfolds it; the choice stays for the session. A courier with fewer than
-- Config.KeyHints.OpenUnder deliveries starts with it open, the others folded. Looked at every Check seconds; the text
-- is set only when it changed.
-- 6.5 (one of everything on screen): folded it is a small "? KEYS [F1]" chip on a charcoal backing, for everyone after
-- the first two deliveries. Unfolded it shows only the keys of the moment: the hands (1 / 2 / 3, V), E, G and X on foot,
-- the driving keys in a seat. [J] Jobs, [M] Map, [Q] Phone, [T] Guns, [Shift] Sprint and [4-8] Items went: the top
-- buttons, the bottom bar's numbers and the phone say them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local Holster = require(script.Parent.Holster)
local Drive = require(script.Parent.Drive)

local KeyHints = {}

-- Set by client/Main.client.luau: does a window, the phone or a dialog cover the game now?
KeyHints.covered = nil :: (() -> boolean)?

local K = Config.KeyHints
local TOGGLE = Enum.KeyCode.F1
local player = Players.LocalPlayer

local open: boolean? = nil -- the session's choice (nil: not chosen yet, from the deliveries)
local deliveries = 0
local hasGun = false
local hasBag = false
local root: any = nil
local lines: { any } = {}
local MAX_LINES = 5 -- (narrow: the chips flow onto more, shorter lines; more than this folds the strip)
local chip: any = nil
local shown = ""

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

local KEY = hex(P.ink)
local WORD = hex(P.ink2)

type Chip = { rich: string, plain: string }

-- One chip: the key bright, its word muted (`on`: the word bright too, the hand you hold).
local function chipText(key: string, word: string, on: boolean?): Chip
	return { rich = `<font color="{KEY}">[{key}]</font> <font color="{if on then KEY else WORD}">{word}</font>`, plain = `[{key}] {word}` }
end

local function keyboard(): boolean
	if Ui.touchLayout() then
		return false
	end
	return UserInputService.KeyboardEnabled
end

-- What the strip says now: two groups of chips (each a line when there is room).
local function linesNow(): { { Chip } }
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return {}
	end
	local first: { Chip } = {}
	local second: { Chip } = {}
	if humanoid.SeatPart ~= nil then
		-- (6.1 review: only the keys that work in this seat: the driver drives, a bus rider rings the bell)
		local car, driving = Drive.seatedCar()
		if typeof(player:GetAttribute("BusLine")) == "string" then
			table.insert(first, chipText("E", "Stop"))
		elseif car and driving then
			table.insert(first, chipText("W/S", "Drive"))
			table.insert(first, chipText("A/D", "Steer"))
			table.insert(first, chipText("E", "Get out"))
		else
			table.insert(first, chipText("E", "Get out"))
		end
		if hasGun then
			table.insert(first, chipText("F", "Shoot"))
		end
		return { first }
	end
	local hand = Holster.hand()
	table.insert(first, chipText("1", "Fists", hand == "fists"))
	if hasBag then
		table.insert(first, chipText("2", "Bag", hand == "bag"))
	end
	if hasGun then
		table.insert(first, chipText("3", "Gun", hand == "gun"))
	end
	local carrying = character:GetAttribute("Carrying") ~= nil
	if typeof(player:GetAttribute("BagDown")) == "Vector3" then
		table.insert(first, chipText("E", "Pick up bag"))
	else
		table.insert(first, chipText("E", "Use"))
	end
	if carrying then
		table.insert(first, chipText("G", "Put down"))
	end
	-- (6.1 review: not for fragile pieces only: X just says they can't be thrown)
	if player:GetAttribute("ThrowReady") == "piece" or (typeof(player:GetAttribute("ThrowTo")) == "Vector3" and player:GetAttribute("ThrowFragile") ~= true) then
		table.insert(first, chipText("X", "Throw"))
	end
	if not carrying then
		table.insert(second, chipText("V", if hand == "gun" then "Strike" else "Punch"))
	end
	return { first, second }
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
	if open == nil then
		return deliveries < K.OpenUnder
	end
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

-- Under the HUD's top buttons (they move with the layout: followed every look).
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
end

local function update(gui: any)
	local covered = KeyHints.covered
	local hide = not gui.Enabled or not keyboard()
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
	local texts = if unfolded then flow(groups, roomFor(gui)) else {}
	local squeezed = texts == nil -- (no room even on MAX_LINES lines: only the KEYS chip)
	local shownTexts: { string } = texts or {}
	local key = `{unfolded}|{squeezed}|{table.concat(shownTexts, "\n")}`
	if key == shown then
		return
	end
	shown = key
	-- (6.4.1: plain text: the game font has no "▴", it showed as a missing-glyph box)
	chip.Text = if unfolded and not squeezed then "KEYS · HIDE  [F1]" else "? KEYS  [F1]"
	for index, label in lines do
		local text = shownTexts[index]
		label.Visible = text ~= nil and text ~= ""
		label.Text = text or ""
	end
end

-- From the State (client/Main.client.luau): your deliveries (the strip's first look), the gun and the bag you have.
function KeyHints.setState(state: any)
	if type(state) ~= "table" then
		return
	end
	deliveries = tonumber(state.deliveries) or 0
	hasGun = type(state.weapon) == "string"
	hasBag = type(state.bag) == "string" -- 6.4: any bag (the server's active one)
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
