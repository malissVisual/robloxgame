--!strict
-- The admin panel (P or the small ADMIN button top right; only for players with the "Admin" attribute, see
-- server/Admin.luau, which checks every command and argument again). The answers come back as toasts (the Notice
-- remote), and in the window's footer while it is open (the toasts are behind it). While it is open the mouse is free
-- (Main: CameraRig.mouseNeeded checks AdminPanel.isOpen()), so the mouse wheel scrolls the panel, not the camera.
-- 3.8 (the contract UI, design/ui-contract/): the charcoal window (Ui.window, its ✕ closes it) with the sections as a
-- sidebar of flat tabs (the selected one with the red rule).
-- 4.5: a TARGET picker at the top (you and every player in the server, by display name; you by default): every command
-- goes to the target (the server sends the target's UserId on).
-- The sections:
--   SANDBOX  the first tab, open by default: the owner's quick test tools (shared/SandboxAdmin.luau's groups and
--            buttons, each ("sandbox", id) to the TARGET: money, the runs (their difficulty, a run in any house, its
--            end, the clock, a horde), the warehouse's stock and stands, the book, the teleports, the upgrades, the
--            warehouse's level, the paints) and 🔍 SHOW ZONES (client/SandboxZones.luau: debug marks on your screen
--            only); 8.3: the Badges line (read-only: which Roblox badges are set up, server/SandboxBadges.luau's
--            AdminBadges attribute)
--   OP       FLY and NOCLIP for the TARGET with their ON / OFF state (the attributes the server set on the target:
--            client/AdminFly.luau moves the body), and 6.13.1's PERFORMANCE overlay (client/PerfOverlay.luau, yours only:
--            AdminPanel.onPerformance, set by client/Main.client.luau)

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SandboxAdmin = require(Shared.SandboxAdmin)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local SandboxZones = require(script.Parent.SandboxZones) -- SHOW ZONES

local C = Ui.Colors
local P = Theme.Postage
local AdminPanel = {}
-- 6.13.1: the OP tab's PERFORMANCE toggle (client/PerfOverlay.luau; client/Main.client.luau sets these)
AdminPanel.onPerformance = nil :: (() -> ())?
AdminPanel.performanceOn = nil :: (() -> boolean)?

local player = Players.LocalPlayer
local remote: RemoteEvent? = nil

-- The window's parts (one table: the 200-register limit).
local parts: { [string]: any } = {}
local tabButtons: { [string]: any } = {}
local section = "sandbox" -- (the game's tools first)
local targetId = player.UserId -- 4.5: who the commands go to (a player in this server)

-- In a Studio Play test everybody is an admin (Config.Admin.InStudio): the panel opens even before the server's
-- "Admin" attribute arrives. The server checks every command again anyway.
local function isAdmin(): boolean
	return player:GetAttribute("Admin") == true or (Config.Admin.InStudio and RunService:IsStudio())
end

-- The target: the picked player while they are in the server, else you.
local function target(): Player
	local found = Players:GetPlayerByUserId(targetId)
	if found and found.Parent == Players then
		return found
	end
	targetId = player.UserId
	return player
end

local function send(name: string, arg: any?)
	if not remote then
		remote = Net.get("Admin")
	end
	if remote then
		remote:FireServer(name, arg, targetId)
	end
end

-- ── Building blocks ────────────────────────────────────────────────────────

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function heading(text: string, hint: string?)
	Ui.label(parts.content, text, UDim2.new(1, -10, 0, 26), { LayoutOrder = nextOrder(), TextSize = 18, Font = Theme.DisplayFont, TextColor3 = C.text })
	if hint then
		Ui.label(parts.content, hint, UDim2.new(1, -10, 0, 0), {
			LayoutOrder = nextOrder(),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = 14,
			Font = Theme.Font,
			TextColor3 = C.dim,
		})
	end
end

-- A block of equal buttons that wraps.
local function grid(cellWidth: number): any
	local frame = Ui.make("Frame", {
		Size = UDim2.new(1, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
	}, parts.content)
	Ui.make("UIGridLayout", {
		CellSize = UDim2.fromOffset(cellWidth, 40),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, frame)
	return frame
end

local function action(parent: any, text: string, color: Color3, onClick: () -> ()): any
	local button = Ui.button(parent, text, UDim2.fromOffset(150, 40), color, onClick)
	button.TextSize = 15
	button.TextWrapped = true
	button.LayoutOrder = nextOrder()
	return button
end

-- An ON / OFF toggle: ON is the main look (the raised face and its red rule), OFF a quiet grey one.
local function toggle(parent: any, label: string, on: boolean, onClick: () -> ()): any
	return action(parent, `{label}  ·  {if on then "ON" else "OFF"}`, if on then C.yellow else C.grey, onClick)
end

-- A name for the hints: "you" or the target's display name.
local function whom(): string
	local who = target()
	return if who == player then "you" else who.DisplayName
end

-- ── Sections ───────────────────────────────────────────────────────────────

local SECTIONS: { { string } } = {
	{ "sandbox", "SANDBOX" },
	{ "op", "OP" },
}

local render: (keepScroll: boolean?) -> ()
local R: { [string]: () -> () } = {} -- the sections' renderers

-- SANDBOX: the owner's quick test tools (shared/SandboxAdmin.luau's groups and buttons; the server, server/Admin.luau's
-- "sandbox", checks each again). Every button goes to the TARGET; SHOW ZONES is yours.
R.sandbox = function()
	local plot = target():GetAttribute("Plot")
	heading(
		`Sandbox · {whom()}{if type(plot) == "number" then ` · plot {plot}` else " · no plot"}`,
		"Quick tools for the game. Every button goes to the TARGET picked at the top; the answer comes in the footer."
	)
	-- 8.3: the Roblox badges, read-only (server/SandboxBadges.luau keeps AdminBadges on the admins; ids: Config.SandboxBadges)
	heading("Badges", tostring(player:GetAttribute("AdminBadges") or "No answer from the server yet."))
	local colors: { [string]: Color3 } = { green = C.green, grey = C.grey, yellow = C.yellow, red = C.red, blue = C.blue, gold = P.gold, violet = P.violet }
	for _, group in SandboxAdmin.Groups do
		heading(group.name, group.hint)
		local cells = grid(200)
		for _, def in SandboxAdmin.Actions do
			if def.group == group.id then
				local id = def.id
				action(cells, def.label, colors[def.color] or C.grey, function()
					send("sandbox", id)
				end)
			end
		end
		if group.id == "debug" then
			toggle(cells, "🔍 SHOW ZONES", SandboxZones.isOn(), function()
				SandboxZones.toggle()
				render(true)
			end)
		end
	end
end

-- The OP toggles: the target's player attributes (the server sets them).
local FLAGS: { { command: string, attribute: string, label: string } } = {
	{ command = "fly", attribute = "AdminFly", label = "FLY" },
	{ command = "noclip", attribute = "AdminNoclip", label = "NOCLIP" },
}

-- OP: fly and noclip for the TARGET; the performance overlay (yours).
R.op = function()
	local who = target()
	heading(`OP tools · {who.DisplayName}`, "FLY: WASD where the camera looks, Space up, Ctrl down, Shift faster (the stick on a phone). NOCLIP: through walls.")
	local toggles = grid(200)
	for _, flag in FLAGS do
		local on = who:GetAttribute(flag.attribute) == true
		toggle(toggles, flag.label, on, function()
			send(flag.command, not on)
		end)
	end
	-- 6.13.1: the performance overlay (client/PerfOverlay.luau, for a screenshot from a phone: design/performance/NAVOD.md)
	heading("Performance", "A small box at the top of your screen: FPS, memory, ping, the parts, shadows and lights around you, streaming. Only you see it. Open the live game on a phone, turn it on, send a screenshot.")
	local perf = grid(200)
	local shown = AdminPanel.performanceOn
	toggle(perf, "PERFORMANCE", shown ~= nil and shown(), function()
		local flip = AdminPanel.onPerformance
		if flip then
			flip()
		end
		render(true)
	end)
end

render = function(keepScroll: boolean?)
	local content = parts.content
	if not content then
		return
	end
	local scroll = content.CanvasPosition
	Ui.clear(content)
	order = 0
	for id, button in tabButtons do
		local selected = id == section
		-- The section tabs: the selected one raised with the narrow red rule, the others quiet rows.
		Ui.selectRow(button, selected)
		button.TextColor3 = if selected then C.text else C.dim
	end
	-- The target picker's selection, and the target in the header.
	local who = target()
	for _, button in parts.picker:GetChildren() do
		if button:IsA("TextButton") then
			local on = button:GetAttribute("UserId") == targetId
			Ui.selectRow(button, on)
			button.TextColor3 = if on then C.text else C.dim
		end
	end
	parts.chrome.subtitle.Text = `Testing tools · P · target: {who.DisplayName}`
	local renderer = R[section]
	if renderer then
		renderer()
	end
	if keepScroll then
		task.defer(function()
			if content.Parent then
				content.CanvasPosition = scroll
			end
		end)
	else
		content.CanvasPosition = Vector2.zero
	end
end

-- One re-render per frame at most (several attributes may change at once), keeping the scroll.
local renderQueued = false
local function rerender()
	if renderQueued or not parts.window or not parts.window.Visible then
		return
	end
	renderQueued = true
	task.defer(function()
		renderQueued = false
		if parts.window.Visible then
			render(true)
		end
	end)
end

-- ── The target picker ──────────────────────────────────────────────────────

local function buildPicker()
	local picker = parts.picker
	if not picker then
		return
	end
	for _, child in picker:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		if a == player or b == player then
			return a == player
		end
		return string.lower(a.DisplayName) < string.lower(b.DisplayName)
	end)
	for index, other in list do
		local id = other.UserId
		local name = if other == player then `{other.DisplayName} (you)` else other.DisplayName
		local button = Ui.button(picker, name, UDim2.fromOffset(150, 34), P.lavenderDeep, function()
			targetId = id
			render(true)
		end)
		button.TextSize = 14
		button.TextWrapped = false
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.LayoutOrder = index
		button:SetAttribute("UserId", id)
	end
end

-- ── The window ─────────────────────────────────────────────────────────────

local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera or not parts.scale then
		return
	end
	local size = camera.ViewportSize
	parts.scale.Scale = math.clamp(math.min(size.X / 1150, size.Y / 680), 0.55, 1.1)
end

local function setOpen(open: boolean)
	local window = parts.window
	if not window then
		return
	end
	window.Visible = open and isAdmin()
	if window.Visible then
		buildPicker()
		render()
	end
end

local WINDOW_SIZE = Vector2.new(880, 600)
local PICKER_HEIGHT = 50
local SIDEBAR_WIDTH = 190

local function build()
	local gui = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryAdmin",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
	}, player:WaitForChild("PlayerGui"))
	parts.gui = gui

	local window, inner, chrome = Ui.window(gui, "Admin", "Testing tools · P", "🛠", UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y))
	window.Visible = false
	chrome.onClose = function()
		setOpen(false)
	end
	parts.window = window
	parts.chrome = chrome
	parts.scale = Ui.make("UIScale", {}, window)
	-- The server's last answer, in the footer (the toasts are behind the window).
	parts.status = chrome.context
	parts.status.TextColor3 = C.text

	-- 4.5: the target picker: a strip over everything (you first, then everybody by name), a fine line under it.
	local strip = Ui.make("Frame", {
		Name = "Target",
		Size = UDim2.new(1, -28, 0, PICKER_HEIGHT - 8),
		Position = UDim2.fromOffset(14, 6),
		BackgroundTransparency = 1,
	}, inner)
	Ui.label(strip, "TARGET", UDim2.new(0, 70, 1, 0), {
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = C.dim,
		TextWrapped = false,
	})
	parts.picker = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -76, 1, 0),
		Position = UDim2.fromOffset(76, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = P.ink2,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
	}, strip)
	Ui.list(parts.picker, false, 6)
	local pickerLayout = parts.picker:FindFirstChildOfClass("UIListLayout")
	if pickerLayout then
		pickerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	Ui.make("Frame", {
		Name = "Line",
		Size = UDim2.new(1, -28, 0, 1),
		Position = UDim2.fromOffset(14, PICKER_HEIGHT),
		BackgroundColor3 = Theme.Contract.rule,
		BorderSizePixel = 0,
	}, inner)

	-- The sections: a recessed sidebar of tabs.
	local sidebar = Ui.make("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, SIDEBAR_WIDTH, 1, -(PICKER_HEIGHT + 1)),
		Position = UDim2.fromOffset(0, PICKER_HEIGHT + 1),
		BackgroundColor3 = P.lavenderDeep,
		BorderSizePixel = 0,
	}, inner)
	local tabs = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, -20),
		Position = UDim2.fromOffset(14, 12),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, sidebar)
	Ui.list(tabs, true, 6)
	for index, entry in SECTIONS do
		local id = entry[1]
		local button = Ui.button(tabs, entry[2], UDim2.new(1, -4, 0, 40), P.lavenderDeep, function()
			section = id
			render()
		end)
		button.TextSize = 15
		button.TextXAlignment = Enum.TextXAlignment.Left
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 8) }, button)
		button.LayoutOrder = index
		tabButtons[id] = button
	end

	local content = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -(SIDEBAR_WIDTH + 30), 1, -(PICKER_HEIGHT + 14)),
		Position = UDim2.fromOffset(SIDEBAR_WIDTH + 18, PICKER_HEIGHT + 10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = P.ink2,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, inner)
	Ui.list(content, true, 8)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 10), PaddingRight = UDim.new(0, 8) }, content)
	parts.content = content

	-- The small button top right (under Roblox's own buttons; a phone opens the panel with it).
	-- A quiet dark action (only admins see it), the red is just its accent and text.
	local openButton = Ui.button(gui, "🛠  ADMIN", UDim2.fromOffset(96, 32), C.red, function()
		setOpen(not window.Visible)
	end)
	openButton.AnchorPoint = Vector2.new(1, 0)
	openButton.Position = UDim2.new(1, -16, 0, 56)
	openButton.TextSize = 13
	openButton.TextColor3 = C.red
	openButton.Visible = false
	Ui.make("UIScale", {}, openButton)
	parts.openButton = openButton
end

-- The ADMIN button shows for admins once the game's interface is on (after PLAY on the start screen).
local function refreshButton()
	local openButton = parts.openButton
	if not openButton then
		return
	end
	local playerGui = player:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	local hudOn = not (hud and hud:IsA("ScreenGui")) or hud.Enabled
	openButton.Visible = isAdmin() and hudOn
	if not isAdmin() and parts.window and parts.window.Visible then
		parts.window.Visible = false
	end
end

-- The attributes the sections show (on the target): a change re-renders the open panel.
local WATCHED: { [string]: boolean } = {
	AdminFly = true,
	AdminNoclip = true,
	Plot = true, -- server/SandboxPlots.luau
}

local function watchPlayer(other: Player)
	other.AttributeChanged:Connect(function(name: string)
		if WATCHED[name] and other.UserId == targetId then
			rerender()
		end
	end)
end

function AdminPanel.start()
	build()
	updateScale()
	local stamp = 0
	Net.get("Notice").OnClientEvent:Connect(function(text: any)
		local status = parts.status
		if not status then
			return
		end
		stamp += 1
		local mine = stamp
		status.Text = tostring(text)
		task.delay(4, function()
			if stamp == mine then
				status.Text = ""
			end
		end)
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	player:GetAttributeChangedSignal("Admin"):Connect(refreshButton)
	-- 4.5: everybody in the server can be the target; the picker follows who comes and goes.
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(function(other: Player)
		watchPlayer(other)
		if parts.window.Visible then
			buildPicker()
			render(true)
		end
	end)
	Players.PlayerRemoving:Connect(function(other: Player)
		task.defer(function()
			if other.UserId == targetId then
				targetId = player.UserId
			end
			if parts.window.Visible then
				buildPicker()
				render(true)
			end
		end)
	end)
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = playerGui:FindFirstChild("ZombieDeliveryHud")
	if hud and hud:IsA("ScreenGui") then
		hud:GetPropertyChangedSignal("Enabled"):Connect(refreshButton)
	end
	refreshButton()

	-- P opens and closes the panel (not while typing in a text box, e.g. the chat). Bound at a high priority, so no
	-- other binding of the game or of Roblox can swallow it.
	ContextActionService:BindActionAtPriority("ZombieDeliveryAdmin", function(_name, state, _input)
		if state ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if isAdmin() then
			setOpen(not parts.window.Visible)
			print(`[AdminPanel] P: the panel is {if parts.window.Visible then "open" else "closed"}`)
			return Enum.ContextActionResult.Sink
		end
		warn("[AdminPanel] P pressed, but you are not an admin (Config.Admin)")
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 100, Enum.KeyCode.P)
	print(`[AdminPanel] ready: press P (admin: {isAdmin()})`)
end

function AdminPanel.isOpen(): boolean
	local window = parts.window
	return window ~= nil and window.Visible == true
end

return AdminPanel
