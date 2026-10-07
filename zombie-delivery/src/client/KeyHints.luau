--!strict
-- 6.1, the key hints (the owner's wish: the player sees which keys do what): a quiet strip right under the HUD's top
-- buttons (MAP · CREW · MENU, client/Hud.luau's "HudButtons"), right-aligned, small muted text on no background, one or
-- two short lines of key chips for what the keys do NOW (the real bindings of the client's modules):
--   on foot   [1] Fists [2] Bag [3] Gun (what you have; the one you hold bright) · [4-8] Items · [E] Use · [G] Put down
--             (cargo in your hands) · [X] Throw (only while a throw is possible: the server's ThrowReady / ThrowTo) ·
--             [E] Pick up bag (while yours lies on the ground: BagDown) · [V] Punch / Strike · [T] Guns · [Shift] Sprint
--             · [Q] Phone · [J] Jobs · [M] Map
--   in a seat [W/S] Drive [A/D] Steer · [E] Get out · [F] Shoot · [4-8] Items · [Q] Phone · [M] Map
-- A keyboard only: hidden on a touch screen and with a gamepad alone. Hidden with the HUD and while a window, the phone,
-- a dialog or the result card covers the game (KeyHints.covered, the bottom bar's rule, set by the client's Main).
-- The KEYS chip (a click, or F1) folds and unfolds it; the choice stays for the session. A courier with fewer than
-- Config.KeyHints.OpenUnder deliveries starts with it open, the others folded. Looked at every Check seconds; the text
-- is set only when it changed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local Holster = require(script.Parent.Holster)

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
local chip: any = nil
local shown = ""

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

local KEY = hex(P.ink)
local WORD = hex(P.ink2)

-- One chip: the key bright, its word muted (`on`: the word bright too, the hand you hold).
local function chipText(key: string, word: string, on: boolean?): string
	return `<font color="{KEY}">[{key}]</font> <font color="{if on then KEY else WORD}">{word}</font>`
end

local function keyboard(): boolean
	if Ui.touchLayout() then
		return false
	end
	return UserInputService.KeyboardEnabled
end

-- What the strip says now: up to two lines.
local function linesNow(): { string }
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return {}
	end
	local first: { string } = {}
	local second: { string } = {}
	if humanoid.SeatPart ~= nil then
		table.insert(first, chipText("W/S", "Drive"))
		table.insert(first, chipText("A/D", "Steer"))
		table.insert(first, chipText("E", "Get out"))
		table.insert(first, chipText("F", "Shoot"))
		table.insert(second, chipText("4-8", "Items"))
		table.insert(second, chipText("Q", "Phone"))
		table.insert(second, chipText("M", "Map"))
		return { table.concat(first, "  "), table.concat(second, "  ") }
	end
	local hand = Holster.hand()
	table.insert(first, chipText("1", "Fists", hand == "fists"))
	if hasBag then
		table.insert(first, chipText("2", "Bag", hand == "bag"))
	end
	if hasGun then
		table.insert(first, chipText("3", "Gun", hand == "gun"))
	end
	table.insert(first, chipText("4-8", "Items"))
	local carrying = character:GetAttribute("Carrying") ~= nil
	if typeof(player:GetAttribute("BagDown")) == "Vector3" then
		table.insert(first, chipText("E", "Pick up bag"))
	else
		table.insert(first, chipText("E", "Use"))
	end
	if carrying then
		table.insert(first, chipText("G", "Put down"))
	end
	if player:GetAttribute("ThrowReady") ~= nil or typeof(player:GetAttribute("ThrowTo")) == "Vector3" then
		table.insert(first, chipText("X", "Throw"))
	end
	if not carrying then
		table.insert(second, chipText("V", if hand == "gun" then "Strike" else "Punch"))
	end
	if hasGun then
		table.insert(second, chipText("T", "Guns"))
	end
	table.insert(second, chipText("Shift", "Sprint"))
	table.insert(second, chipText("Q", "Phone"))
	table.insert(second, chipText("J", "Jobs"))
	table.insert(second, chipText("M", "Map"))
	return { table.concat(first, "  "), table.concat(second, "  ") }
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
		Size = UDim2.fromOffset(0, K.TextSize + 4),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Theme.HeadingFont,
		TextSize = K.TextSize - 1,
		TextColor3 = P.ink2,
		TextStrokeTransparency = 0.75,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = 0,
	}, root)
	chip.Activated:Connect(function()
		open = not isOpen()
		shown = ""
	end)
	lines[1] = line(root, 1)
	lines[2] = line(root, 2)
end

local function update(gui: any)
	local covered = KeyHints.covered
	local hide = not gui.Enabled or not keyboard()
	if not hide and covered then
		local ok, value = pcall(covered)
		hide = ok and value == true
	end
	local texts = if hide then {} else linesNow()
	hide = hide or #texts == 0
	if root.Visible == hide then
		root.Visible = not hide
	end
	if hide then
		return
	end
	place(gui)
	local unfolded = isOpen()
	local key = `{unfolded}|{texts[1] or ""}|{texts[2] or ""}`
	if key == shown then
		return
	end
	shown = key
	chip.Text = if unfolded then "KEYS ▴  [F1]" else "? KEYS  [F1]"
	for index, label in lines do
		local text = texts[index]
		label.Visible = unfolded and text ~= nil and text ~= ""
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
	hasBag = type(state.kit) == "table" and state.kit[Config.Courier.BagKit] == true
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
