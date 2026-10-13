-- 8.0 SANDBOX: the stand-ins for the sandbox's HUD and the warehouse picker (tools/phone-ui/sandbox.luau), on top of the
-- MISSIONS window's (missions_mock.luau): Vector2 maths, a layout (where a recorded piece sits on the screen: Position,
-- Size, AnchorPoint, the UIScales, a ScrollingFrame's canvas; no list layouts), a text width close to Gotham's, the Ui
-- and Theme bits the two modules call, client/Hud.luau's left column (Hud.topSlot, where Hud's layout puts it) and its
-- toasts, client/Juice.luau's countMoney, shared/FurnitureLooks.luau's catalogue (the real one, loaded on the recorder)
-- with a recorded build (a model a piece, counted), shared/ItemLooks.luau's camera maths and the "Collection" remote.
local M = require("./missions_mock")

-- ── Vector2 maths ───────────────────────────────────────────────────────────
local v2 = {}
v2.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y)
	end
	return nil
end
v2.__add = function(a, b)
	return M.Vector2.new(a.X + b.X, a.Y + b.Y)
end
v2.__sub = function(a, b)
	return M.Vector2.new(a.X - b.X, a.Y - b.Y)
end
M.Vector2.new = function(x, y)
	return setmetatable({ X = x or 0, Y = y or 0, kind = "Vector2" }, v2)
end
M.Vector2.zero = M.Vector2.new(0, 0)

-- ── Services ────────────────────────────────────────────────────────────────
M.services.UserInputService.InputEnded = M.signal()
M.services.GuiService.GetGuiInset = function()
	return M.Vector2.new(0, 0)
end
M.services.Players.GetPlayers = function()
	return { M.player }
end

-- A text's width close to Gotham's (px): caps and digits wide, lower case narrower, an emoji a square. The check's
-- "text fits" and client/CardKit.luau's widths (TextService) both use it.
local function charWidth(c, bold)
	if c == " " then
		return 0.28
	elseif string.match(c, "^[%u%d%$%%#@&]$") then
		return if bold then 0.7 else 0.66
	elseif string.match(c, "^[%l]$") then
		return if bold then 0.57 else 0.54
	elseif string.match(c, "^[%.,:;'!|]$") then
		return 0.28
	elseif #c == 1 then
		return 0.45
	end
	return 1.15 -- (an emoji or a symbol)
end
function M.textWidth(text, size, font)
	local bold = font == nil or string.find(tostring(font and font.Name), "Bold") ~= nil or string.find(tostring(font and font.Name), "Black") ~= nil
	local total = 0
	for _, code in utf8.codes(text) do
		if code ~= 0xFE0F then -- (an emoji's variation selector has no width)
			total += charWidth(utf8.char(code), bold)
		end
	end
	return total * size
end
M.services.TextService = {
	GetTextSize = function(_, value, size, font)
		return M.Vector2.new(M.textWidth(value, size, font), size)
	end,
}

-- shared/CollectionRules.luau when it is there (the real one, copied with the shared modules): Shared:FindFirstChild
M.rulesFound = false
rawset(M.services.ReplicatedStorage.Shared, "FindFirstChild", function(_, name)
	local ok = pcall(require, "./" .. name)
	if ok and name == "CollectionRules" then
		M.rulesFound = true
	end
	return if ok then "./" .. name else nil
end)

-- ── Ui and Theme ────────────────────────────────────────────────────────────
M.scale = 1
M.MUi.ScaleBase = M.Vector2.new(1150, 680)
M.MUi.MinScale, M.MUi.MaxScale, M.MUi.MinTouch = 0.55, 1.1, 44
function M.MUi.scaleFor(size)
	return math.clamp(math.min(size.X / 1150, size.Y / 680), 0.55, 1.1)
end
function M.MUi.screenScale()
	return M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
end
function M.MUi.screenSize()
	return M.Vector2.new(M.width, M.height)
end
function M.MUi.touchLayout()
	return M.touch
end
function M.MUi.gamepadActive()
	return false
end
function M.MUi.closeButton(parent, fn)
	local made = M.make("TextButton", { Name = "Close", Text = "✕", Size = M.UDim2.fromOffset(40, 40), Position = M.UDim2.new(1, -8, 0, 8), AnchorPoint = M.Vector2.new(1, 0), TextSize = 18, BackgroundTransparency = 1, TextColor3 = M.MTheme.Contract.text }, parent)
	M.make("UIStroke", { Color = M.MTheme.Contract.rule, Thickness = 1 }, made)
	made.Activated:Connect(fn)
	return made
end
M.MUi.MinTouch = 44
M.MTheme.PanelTransparency = 0.12
M.MTheme.WindowTransparency = 0.02
M.MTheme.Font = M.Enum.Font.GothamMedium

-- ── A layout: where a recorded piece sits (px from the screen's top left) ──
local function uiScale(object)
	for _, child in object:GetChildren() do
		if child.ClassName == "UIScale" then
			return child.Scale or 1
		end
	end
	return 1
end
M.uiScale = uiScale
local function layout(object)
	local class = object.ClassName
	if class == "ScreenGui" or class == "PlayerGui" or object.Parent == nil then
		return 0, 0, M.width, M.height, 1
	end
	local px, py, pw, ph, inherited = layout(object.Parent)
	local own = uiScale(object)
	local size = object.Size or M.UDim2.new()
	local w = (pw * size.X.Scale + size.X.Offset * inherited) * own
	local h = (ph * size.Y.Scale + size.Y.Offset * inherited) * own
	local position = object.Position or M.UDim2.new()
	local anchor = object.AnchorPoint or M.Vector2.new(0, 0)
	local x = px + pw * position.X.Scale + position.X.Offset * inherited - anchor.X * w
	local y = py + ph * position.Y.Scale + position.Y.Offset * inherited - anchor.Y * h
	local parent = object.Parent
	if parent and parent.ClassName == "ScrollingFrame" then
		local canvas = parent.CanvasPosition or M.Vector2.zero
		x -= canvas.X * inherited
		y -= canvas.Y * inherited
	end
	return x, y, w, h, inherited * own
end
M.layout = layout
local meta = getmetatable(M.make("Frame"))
local baseIndex = meta.__index
meta.__index = function(self, key)
	if key == "AbsolutePosition" or key == "AbsoluteSize" then
		local x, y, w, h = layout(self)
		return if key == "AbsolutePosition" then M.Vector2.new(x, y) else M.Vector2.new(w, h)
	end
	return baseIndex(self, key)
end
function M.box(object)
	local x, y, w, h = layout(object)
	return { x0 = x, y0 = y, x1 = x + w, y1 = y + h }
end
function M.scaleOf(object)
	local _, _, _, _, s = layout(object)
	return s
end

-- ── client/Hud.luau's left column (TopStack) and its toasts ────────────────
-- Hud's layout() puts the column at the left margin under Roblox's top bar on a computer (under the chat when it is
-- open), and on a touch screen right of the left column (the cash, the minimap, the health: 200 × 258 at the HUD's
-- scale S, its top left at 16, 16); the column's scale is S there (the room under it allows it on these screens).
M.toasts = {}
M.hudGui = M.gui:FindFirstChild("ZombieDeliveryHud")
local topStack = M.make("Frame", { Name = "TopStack", Size = M.UDim2.fromOffset(380, 0), BackgroundTransparency = 1 }, M.hudGui)
M.make("UIScale", { Name = "LayoutScale", Scale = 1 }, topStack)
M.topStack = topStack
M.leftColumn = nil
function M.placeHud()
	local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
	topStack:FindFirstChild("LayoutScale").Scale = S
	if M.touch then
		M.leftColumn = { x0 = 16, y0 = 16, x1 = 16 + 200 * S, y1 = 16 + 258 * S }
		topStack.Position = M.UDim2.fromOffset(M.leftColumn.x1 + 8, 16)
	else
		M.leftColumn = nil
		topStack.Position = M.UDim2.fromOffset(16, if M.chatOpen then 208 else 14)
	end
	topStack:FindFirstChild("LayoutScale"):GetPropertyChangedSignal("Scale"):Fire()
end
M.Hud = {
	topSlot = function(name)
		local found = topStack:FindFirstChild("Slot_" .. name)
		if found then
			return found
		end
		M.slotsMade = (M.slotsMade or 0) + 1
		return M.make("Frame", { Name = "Slot_" .. name, Size = M.UDim2.new(1, 0, 0, 0), LayoutOrder = 10, BackgroundTransparency = 1 }, topStack)
	end,
	toast = function(text)
		table.insert(M.toasts, text)
	end,
}

-- client/Juice.luau's countMoney: the amount counted to (recorded) and shown
M.counted = {}
M.Juice = {
	countMoney = function(label, amount)
		table.insert(M.counted, amount)
		label.Text = M.MUi.money(amount)
	end,
}
M.ItemModel = { view = function() return nil end, has = function() return false end }

-- ── shared/FurnitureLooks.luau: the real catalogue, a recorded build ───────
local real = require("./FurnitureLooksReal")
M.builds = {}
M.FurnitureLooks = {
	Items = real.Items,
	Order = real.Order,
	build = function(id, variant)
		local key = id .. "#" .. tostring(variant or 1)
		M.builds[key] = (M.builds[key] or 0) + 1
		local def = real.Items[id] or real.Items.box
		local model = M.make("Model", { Name = def.name })
		model:SetAttribute("FurnitureId", id)
		local root = M.make("Part", { Name = "Root", Size = def.size }, model)
		M.make("Part", { Name = "Body" }, model)
		M.make("SurfaceGui", { Name = "Label" }, root) -- (stripped from a picture's model)
		return model
	end,
}
M.ItemLooks = {
	bounds = function()
		return { -1, -1, -1 }, { 1, 1, 1 }
	end,
	frame = function(_, _, aspect)
		M.lastAspect = aspect
		return { 3, 2, -4 }, { 0, 0, 0 }
	end,
}

-- the remotes the two modules use (mock.luau's Net, recording what goes to the server)
M.Net = M.Net

return M
