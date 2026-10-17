--!strict
-- 10.x THE MAP, the minimap (Config.SandboxMapUi.Mini): in a run, a small square of the house's floor plan round you in
-- a corner (client/SandboxMapDraw.luau's drawing, client/SandboxMapData.luau's world, shared/SandboxMapRules.luau's
-- maths): the rooms, the doorways, the yard's strip and the truck, you (▲ turned your way, in the middle), your party,
-- Danny and the helpers, the zombies near you, the loot you saw (its tier's colour; Epic and up pulsing) and the dangers'
-- markers. The plan is drawn once a run at a fixed scale (Mini.Scale px a stud, a touch screen's Mini.TouchScale) and
-- only moved under the square to keep you in its middle; the markers move every Mini.Every s.
--   * Where: a computer's bottom right corner (Mini.Size at the HUD's scale), a touch screen's top right under Roblox's
--     top bar (Mini.TouchSize), shrunk by Mini.Step down to Mini.Least to keep clear of the HUD (the top blocks: the
--     move's panel, Danny's line, the planning's pill; the guide's line keeps clear of it; the HUD's groups and chips, the quick chat's button, Danny's orders
--     line and 📋 button; a touch screen's buttons, its thumbstick and jump button, the first place of the 📋 / TAP
--     button: MoveLayout.tapSpots), else none. Looked at again every second and when the screen changes.
--   * Shown only in a run with its plan, with the HUD (client/SandboxHud.luau's ScreenGui shown), no window open
--     (SandboxMiniMap.covered: Main's CameraRig.windowOpen) and no grip check (client/CarryGripUi.luau active).
--   * A click or a tap on it opens the big map (client/SandboxMapUi.luau). A small "MAP · M" in its corner (the
--     device's way: M, the gamepad's L2, a tap).
--   SandboxMiniMap.start()          listens (once; nothing outside the sandbox)
--   SandboxMiniMap.step()           one look (the loop's; the checks')
--   SandboxMiniMap.frame()          its square (nil before built), SandboxMiniMap.canvas() its drawing (the checks)
--   SandboxMiniMap.covered          a hook: () -> boolean (a window open)
-- Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SandboxPad = require(Shared.SandboxPad)
local Rules = require(Shared.SandboxMapRules)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local PadGlyph = require(script.Parent.PadGlyph)
local TouchLayout = require(script.Parent.TouchLayout)
local MoveLayout = require(script.Parent.MoveLayout)
local TopBlocks = require(script.Parent.TopBlocks)
local Data = require(script.Parent.SandboxMapData)
local Draw = require(script.Parent.SandboxMapDraw)

local SandboxMiniMap = {}

SandboxMiniMap.covered = nil :: (() -> boolean)?

local C = Config.SandboxMapUi
local M = C.Mini
local K = Theme.Contract
local player = Players.LocalPlayer
-- what it keeps clear of: a ScreenGui's pieces by name ("" every piece)
local AVOID: { [string]: { string } | string } = {
	ZombieDeliveryHud = { "LeftStack", "TopStack", "HudButtons", "RightStack", "Hint", "Fire", "BottomBar", "KeyHints" },
	SandboxHud = { "MoneyBlock" },
	SandboxTasksChip = "",
	QuickChat = { "QuickChatButton" },
	DannyOrders = "",
}
local TOP = { "MovePanel", "MoveHelper", "PlanningPill" } -- (client/TopBlocks.luau's)

local started = false
local parts: { [string]: any } = {} -- gui, square, holder, caption, canvas, key, box, boxAt
local canvas: Draw.Canvas? = nil

local function ask(fn: (() -> boolean)?): boolean
	if not fn then
		return false
	end
	local ok, value = pcall(fn)
	return ok and value == true
end

local function gripOn(): boolean
	local ok, grip = pcall(function(): any
		return require(script.Parent.CarryGripUi)
	end)
	if not ok or type(grip) ~= "table" or type(grip.active) ~= "function" then
		return false
	end
	local fine, on = pcall(grip.active)
	return fine and on == true
end

local function hudShown(): boolean
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("SandboxHud")
	return hud == nil or (hud :: any).Enabled ~= false
end

-- ── Where it goes ────────────────────────────────────────────────────────────

local function boxOf(object: GuiObject, origin: Vector2): Rules.MapBox
	local at, size = object.AbsolutePosition - origin, object.AbsoluteSize
	return { x0 = at.X, y0 = at.Y, x1 = at.X + size.X, y1 = at.Y + size.Y }
end

local function avoidList(origin: Vector2, W: number, H: number, S: number, touch: boolean): { Rules.MapBox }
	local list: { Rules.MapBox } = {}
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	for guiName, pieces in AVOID do
		local holder = playerGui and playerGui:FindFirstChild(guiName)
		if holder and (holder :: any).Enabled ~= false then
			local function add(object: Instance?)
				if object and object:IsA("GuiObject") and object.Visible and object.AbsoluteSize.X > 1 and object.AbsoluteSize.Y > 1 then
					table.insert(list, boxOf(object, origin))
				end
			end
			if pieces == "" then
				for _, child in holder:GetChildren() do
					add(child)
				end
			else
				for _, name in pieces :: { string } do
					add(holder:FindFirstChild(name))
				end
			end
		end
	end
	-- (the top's middle blocks; not the guide's line: it keeps clear of this square itself, client/SandboxGuide.luau)
	for _, name in TOP do
		local block = TopBlocks.get(name)
		if block and block.Visible and block.AbsoluteSize.X > 1 then
			local holderGui = block:FindFirstAncestorWhichIsA("ScreenGui")
			if holderGui == nil or (holderGui :: any).Enabled ~= false then
				table.insert(list, boxOf(block, origin))
			end
		end
	end
	if touch then
		local c = TouchLayout.cluster(W, H, S)
		for _, b in TouchLayout.buttons(c) do
			table.insert(list, b)
		end
		table.insert(list, c.thumb)
		table.insert(list, c.jump)
		-- (the 📋 / TAP button's first place: client/DannyOrders.luau's, client/CarryGripUi.luau's)
		local clip = Config.MoveHelper.Clipboard
		local spot = MoveLayout.tapSpots(W, H, S, math.max(clip.ButtonMin, Ui.MinTouch, clip.Button * S))[1]
		if spot then
			table.insert(list, spot)
		end
	end
	return list
end

local function placeSquare()
	local square = parts.square
	if not square then
		return
	end
	local size = Ui.screenSize()
	local touch = Ui.touchLayout()
	local S = Ui.screenScale()
	local origin = if parts.gui then (parts.gui :: any).AbsolutePosition else Vector2.new(0, 0)
	local box = Rules.mini(size.X, size.Y, S, touch, avoidList(origin, size.X, size.Y, S, touch))
	parts.box = box
	parts.boxAt = os.clock()
	if box then
		square.Position = UDim2.fromOffset(math.floor(box.x0 + 0.5), math.floor(box.y0 + 0.5))
		square.Size = UDim2.fromOffset(math.floor(box.x1 - box.x0 + 0.5), math.floor(box.y1 - box.y0 + 0.5))
	end
end

-- ── Building ─────────────────────────────────────────────────────────────────

local function caption(): string
	local device = PadGlyph.device()
	if device == "touch" then
		return "TAP: MAP"
	end
	local word = SandboxPad.keyWord("map", device)
	return if word then `MAP · {word}` else "MAP"
end

local function build()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Ui.make("ScreenGui", { Name = "SandboxMiniMap", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 1, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	parts.gui = gui
	local square = Ui.make("TextButton", {
		Name = "MiniMap",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(C.Colors.Back[1], C.Colors.Back[2], C.Colors.Back[3]),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Visible = false,
		Size = UDim2.fromOffset(M.TouchSize, M.TouchSize),
	}, gui)
	Ui.make("UIStroke", { Color = K.line, Thickness = 1, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, square)
	square.Activated:Connect(function()
		pcall(function()
			(require(script.Parent.SandboxMapUi) :: any).open()
		end)
	end)
	parts.square = square
	local holder = Ui.make("Frame", { Name = "Holder", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1 }, square)
	parts.holder = holder
	local small = C.Text.Least
	parts.caption = Ui.make("TextLabel", {
		Name = "Caption",
		Text = caption(),
		TextSize = small,
		Font = Theme.HeadingFont,
		TextColor3 = K.text,
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(Draw.width(caption(), small, Theme.HeadingFont) + 10, small + 6),
		Position = UDim2.fromOffset(3, 3),
		ZIndex = 20,
	}, square)
	-- (follow the HUD: hidden with it)
	local hud = playerGui:FindFirstChild("SandboxHud")
	if hud then
		gui.Enabled = (hud :: any).Enabled
		hud:GetPropertyChangedSignal("Enabled"):Connect(function()
			gui.Enabled = (hud :: any).Enabled
		end)
	end
end

-- The plan at the minimap's scale, once a run (its place's key).
local function drawFor(place: Data.Place)
	local key = `{place.key}|{Ui.touchLayout()}`
	if canvas and parts.key == key then
		return
	end
	parts.key = key
	if canvas then
		canvas.root:Destroy()
		canvas = nil
	end
	local plan = place.plan
	if not plan then
		return
	end
	local box = Rules.houseBox(plan, place.yard)
	local scale = if Ui.touchLayout() then M.TouchScale else M.Scale
	local pad = 40
	local w = math.ceil((box.x1 - box.x0) * scale + 2 * pad)
	local h = math.ceil((box.z1 - box.z0) * scale + 2 * pad)
	local frame: Rules.Frame = { cx = (box.x0 + box.x1) / 2, cz = (box.z0 + box.z1) / 2, rot = 180, scale = scale, ox = w / 2, oy = h / 2 }
	canvas = Draw.house(parts.holder, frame, 1, w, h, place, true)
end

-- ── A look ───────────────────────────────────────────────────────────────────

function SandboxMiniMap.step()
	local square = parts.square
	if not square then
		return
	end
	local place = Data.place()
	local on = place.kind == "run" and place.plan ~= nil and hudShown() and not ask(SandboxMiniMap.covered) and not gripOn()
	if on and (parts.box == nil or os.clock() - (parts.boxAt or 0) > 1) then
		placeSquare()
	end
	on = on and parts.box ~= nil
	if square.Visible ~= on then
		square.Visible = on
	end
	if not on then
		return
	end
	drawFor(place)
	local drawn = canvas
	if not drawn then
		return
	end
	local people = Data.people(place)
	local loot = Data.loot(place)
	Draw.marks(drawn, people, loot, Data.dangers(place), Data.truck(place))
	-- you in the middle of the square
	for _, person in people do
		if person.kind == "you" then
			local x, y = Rules.toMap(drawn.frame, person.x, person.z)
			local size = square.AbsoluteSize
			local w, h = if size.X > 1 then size.X else M.TouchSize, if size.Y > 1 then size.Y else M.TouchSize
			drawn.root.Position = UDim2.fromOffset(math.floor(w / 2 - x + 0.5), math.floor(h / 2 - y + 0.5))
			break
		end
	end
	local text = caption()
	if parts.caption.Text ~= text then
		parts.caption.Text = text
		parts.caption.Size = UDim2.fromOffset(Draw.width(text, C.Text.Least, Theme.HeadingFont) + 10, C.Text.Least + 6)
	end
end

function SandboxMiniMap.frame(): GuiObject?
	return parts.square
end

function SandboxMiniMap.canvas(): Draw.Canvas?
	return canvas
end

function SandboxMiniMap.start()
	if started then
		return
	end
	started = true
	Data.start()
	build()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			parts.box = nil
			parts.key = nil
		end)
	end
	task.spawn(function()
		while true do
			task.wait(M.Every)
			local ok, err = pcall(SandboxMiniMap.step :: any)
			if not ok then
				warn(`[SandboxMiniMap] {err}`)
			end
		end
	end)
end

return SandboxMiniMap
