-- 6.8: the stand-ins for the MISSIONS window's check (tools/phone-ui/missions.luau), on top of mock.luau: the Ui and
-- Theme helpers the window calls (recorded instances: no layout, no fonts), Color3 with Lerp / ToHex, Vector3 maths,
-- a CFrame that only keeps positions, Instance.new, Clone / PivotTo, and threads that wait until M.resume().
-- 6.12.13: NumberSequence for the chapter banner's gradient.
local M = require("./mock")

-- Color3: Lerp and ToHex (the window's colours, the portraits' gradients).
local color = {}
color.__index = color
function color:Lerp(other, t)
	return M.Color3.new(self.R + (other.R - self.R) * t, self.G + (other.G - self.G) * t, self.B + (other.B - self.B) * t)
end
function color:ToHex()
	local function byte(v)
		return math.clamp(math.floor(v * 255 + 0.5), 0, 255)
	end
	return string.format("%02X%02X%02X", byte(self.R), byte(self.G), byte(self.B))
end
M.Color3.new = function(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0, kind = "Color3" }, color)
end
M.Color3.fromRGB = function(r, g, b)
	return M.Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

-- Vector3: + and * (the busts' sizes).
local vector = getmetatable(M.Vector3.new(0, 0, 0))
vector.__add = function(a, b)
	return M.Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
vector.__mul = function(a, b)
	if type(a) == "number" then
		a, b = b, a
	end
	if type(b) == "number" then
		return M.Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return M.Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
M.Vector3.one = M.Vector3.new(1, 1, 1)
M.Vector3.zero = M.Vector3.new(0, 0, 0)

-- CFrame: positions only (enough to record where the busts' parts and the camera go).
local frame = { kind = "CFrame" }
frame.__index = function(self, key)
	if key == "Position" then
		return M.Vector3.new(self.X, self.Y, self.Z)
	elseif key == "LookVector" then
		return M.Vector3.new(0, 0, -1)
	end
	return nil
end
M.CFrame = {}
function M.CFrame.new(x, y, z)
	if type(x) == "table" then
		return setmetatable({ X = x.X, Y = x.Y, Z = x.Z, kind = "CFrame" }, frame)
	end
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, kind = "CFrame" }, frame)
end
frame.__mul = function(a, b)
	if b.kind == "CFrame" then
		return M.CFrame.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
	end
	return M.Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
function M.CFrame.Angles()
	return M.CFrame.new(0, 0, 0)
end
function M.CFrame.lookAt(at)
	return M.CFrame.new(at.X, at.Y, at.Z)
end
M.ColorSequence = { new = function(a, b)
	return { a = a, b = b }
end }
-- 6.12.13: the chapter banner's dark gradient (client/MissionArtUi.luau): the keypoints kept as given.
M.NumberSequence = { new = function(points)
	return { Keypoints = points, kind = "NumberSequence" }
end }
M.NumberSequenceKeypoint = { new = function(time, value)
	return { Time = time, Value = value }
end }
M.Instance = { new = function(class)
	return M.make(class)
end }

-- The instance methods the window and the portraits use on top of mock.luau's.
function M.methods:Clone()
	local copy = M.make(self.ClassName)
	for key, value in self._p do
		if key ~= "Parent" then
			copy._p[key] = value
		end
	end
	for _, child in self._children do
		child:Clone().Parent = copy
	end
	return copy
end
function M.methods:PivotTo(cframe)
	self._p.Pivot = cframe
end
-- 6.8 review: the gamepad's selection is put back by Name after a rebuild (a recursive find, IsDescendantOf).
function M.methods:IsDescendantOf(ancestor)
	local node = self.Parent
	while node do
		if node == ancestor then
			return true
		end
		node = node.Parent
	end
	return false
end
function M.methods:FindFirstChild(name, recursive)
	for _, child in self._children do
		if child.Name == name then
			return child
		end
	end
	if recursive then
		for _, child in self._children do
			local found = child:FindFirstChild(name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function M.methods:FindFirstAncestorWhichIsA(class)
	local node = self.Parent
	while node do
		if node:IsA(class) then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- Threads: task.spawn starts one, task.wait suspends it until M.resume() (so a `while true do task.wait()` loop
-- runs once per resume, never forever).
local threads = {}
M.task.spawn = function(fn, ...)
	local thread = coroutine.create(fn)
	table.insert(threads, thread)
	local ok, err = coroutine.resume(thread, ...)
	assert(ok, err)
	return thread
end
M.task.wait = function()
	coroutine.yield()
	return 0.25
end
function M.resume()
	for _, thread in table.clone(threads) do
		if coroutine.status(thread) == "suspended" then
			local ok, err = coroutine.resume(thread)
			assert(ok, err)
		end
	end
end

-- Theme: the contract tokens the window names.
local function rgb(r, g, b)
	return M.Color3.fromRGB(r, g, b)
end
local Contract = {
	text = rgb(242, 242, 240), secondary = rgb(196, 199, 203), charcoal = rgb(20, 23, 28), raised = rgb(30, 34, 41),
	line = rgb(133, 139, 147), red = rgb(215, 74, 70), good = rgb(126, 196, 120), warn = rgb(228, 170, 82), scrim = 0.35,
	lineAlpha = 0.45, row = rgb(25, 29, 35), recessed = rgb(15, 17, 21), track = rgb(52, 57, 64), rule = rgb(82, 87, 93),
}
local Postage = {
	paper = Contract.raised, ticket = Contract.row, lavender = Contract.charcoal, lavenderDeep = Contract.recessed,
	ink = Contract.text, ink2 = Contract.secondary, sage = Contract.raised, violet = Contract.text, line = Contract.rule,
	shadow = rgb(0, 0, 0), danger = Contract.red, good = Contract.good, warn = Contract.warn, quiet = Contract.secondary,
}
local Colors = {
	yellow = rgb(255, 200, 70), green = rgb(126, 196, 120), red = rgb(215, 74, 70), blue = rgb(90, 160, 255),
	money = rgb(140, 220, 120), dim = Contract.secondary,
}
M.MTheme = {
	Contract = Contract,
	Postage = Postage,
	Colors = Colors,
	Font = M.Enum.Font.GothamMedium,
	HeadingFont = M.Enum.Font.GothamBold,
	DisplayFont = M.Enum.Font.GothamBold,
	MonoFont = M.Enum.Font.GothamMedium,
	textOn = function()
		return Contract.text
	end,
}

-- Ui: recorded instances with the properties the window gives them (the real one draws them; that needs Studio).
local Ui = { HAIRLINE = 0.8, HAIRLINE_SELECTED = 0.5, Colors = Colors, onClick = nil }
M.MUi = Ui
Ui.make = M.make
function Ui.label(parent, text, size, props)
	local made = M.make("TextLabel", { Text = text, Size = size, BackgroundTransparency = 1 }, parent)
	for key, value in props or {} do
		made[key] = value
	end
	return made
end
function Ui.caps(parent, text, size, props)
	return Ui.label(parent, string.upper(text), size, props)
end
function Ui.stroke(parent, c, thickness)
	return M.make("UIStroke", { Color = c, Thickness = thickness or 1 }, parent)
end
function Ui.list(parent, vertical, gap)
	M.make("UIListLayout", { FillDirection = if vertical then M.Enum.FillDirection.Vertical else M.Enum.FillDirection.Horizontal, Padding = M.UDim.new(0, gap) }, parent)
end
function Ui.padding(parent)
	M.make("UIPadding", {}, parent)
end
-- 6.18: the UI kit's corners (client/CardKit.luau draws the hero, the rows and the chips).
Ui.corner = M.Ui.corner
function Ui.button(parent, text, size, c, onClick)
	local made = M.make("TextButton", { Text = text, Size = size, BackgroundColor3 = c }, parent)
	made.Activated:Connect(onClick)
	return made
end
function Ui.ghostButton(parent, text, size, _, onClick)
	return Ui.button(parent, text, size, Contract.charcoal, onClick)
end
function Ui.bar(parent, size, c)
	local back = M.make("Frame", { Name = "Bar", Size = size }, parent)
	local fill = M.make("Frame", { Name = "Fill", Size = M.UDim2.fromScale(1, 1), BackgroundColor3 = c }, back)
	return back, fill
end
function Ui.tabs(parent, items, onPick, options)
	local holder = M.make("Frame", { Name = "Tabs" }, parent)
	local buttons = {}
	for _, item in items do
		local button = M.make("TextButton", { Name = item.id .. "Tab", Text = item.text }, holder)
		button.Activated:Connect(function()
			onPick(item.id)
		end)
		buttons[item.id] = button
	end
	local tabs = { frame = holder, buttons = buttons, selected = options and options.selected }
	function tabs.select(id)
		tabs.selected = id
	end
	return tabs
end
function Ui.selectRow(card, on)
	card:SetAttribute("Selected", on)
end
function Ui.tactile() end
function Ui.heading(parent, title)
	local holder = M.make("Frame", { Name = "Heading" }, parent)
	return { frame = holder, title = Ui.label(holder, string.upper(title), M.UDim2.new(1, 0, 1, 0)), glyph = M.make("Frame", {}, holder) }
end
function Ui.window(parent, title, subtitle, _, size)
	local window = M.make("Frame", { Name = "Window", Size = size }, parent)
	local surface = M.make("Frame", { Name = "Surface", Size = M.UDim2.fromScale(1, 1) }, window)
	local header = M.make("Frame", { Name = "Header" }, surface)
	local heading = Ui.heading(header, title)
	local subtitleLabel = Ui.label(header, subtitle, M.UDim2.new(), { Name = "Subtitle" })
	local content = M.make("Frame", { Name = "Content" }, surface)
	local footer = M.make("Frame", { Name = "Footer" }, surface)
	local context = Ui.label(footer, "", M.UDim2.new(), { Name = "Context" })
	local close = M.make("TextButton", { Name = "Close", Text = "✕" }, header)
	local chrome = {
		frame = window, surface = surface, header = header, content = content, footer = footer, icon = M.make("TextLabel", {}, header),
		title = heading.title, subtitle = subtitleLabel, close = close, context = context, heading = heading, glyph = heading.glyph,
		onClose = nil,
	}
	close.Activated:Connect(function()
		if chrome.onClose then
			chrome.onClose()
		else
			window.Visible = false
		end
	end)
	return window, content, chrome
end
function Ui.icon(parent, _, fallback, size, props)
	return Ui.label(parent, fallback, size, props)
end
function Ui.dashes(parent, _, _, c, size, position)
	return M.make("Frame", { Size = size, Position = position, BackgroundColor3 = c }, parent)
end
function Ui.edge(parent, c)
	return M.make("Frame", { Name = "Edge", BackgroundColor3 = c }, parent)
end
Ui.clear = M.Ui.clear
function Ui.stars(count)
	local n = math.clamp(count, 0, 3)
	return string.rep("★", n) .. string.rep("☆", 3 - n)
end
function Ui.money(amount)
	local text = tostring(math.floor(amount))
	while true do
		local swapped
		text, swapped = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
		if swapped == 0 then
			break
		end
	end
	return "$" .. text
end
Ui.clock = M.Ui.clock
function Ui.screenSize()
	return M.Vector2.new(M.width, M.height)
end
function Ui.gamepadFocus(target)
	M.focus = target
end
function Ui.gamepadRelease()
	M.focus = nil
end
-- (like GuiService.SelectedObject: a destroyed button is no selection)
function Ui.gamepadSelection()
	return if M.focus and M.focus.Parent ~= nil then M.focus else nil
end

M.MHud = {
	topSlot = function(name)
		return M.make("Frame", { Name = name .. "Slot" }, M.gui)
	end,
	resultOpen = function()
		return false
	end,
}
M.MCrewPanel = { open = function()
	M.crewOpened = true
end }
M.MDialogKeys = { hint = function()
	return "SPACE"
end, watch = function() end }

return M
