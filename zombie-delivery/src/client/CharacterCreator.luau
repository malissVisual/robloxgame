--!strict
-- 9.6, the character creator (the owner: "každý hráč … si dělá charaktera"): the start screen's window where you make
-- the courier of a save slot (client/Menu.luau opens it for NEW GAME, START OVER and a slot's LOOK). On the left your
-- courier turns slowly in a 3D preview (drag it to turn it yourself); on the right its name and every choice of
-- Config.Characters (shared/CharacterLooks.luau): your own Roblox avatar or a made courier, the skin, the hair and its
-- colour, a hat and its colour, the top and its colour, the trousers, something on the face; 🎲 RANDOM rolls a made
-- one. The preview builds the pieces with the server's own builder (shared/StyleBuild.luau StyleBuild.character) on the
-- classic block body (client/StylePreview.luau's mannequin), so what you pick is what everybody sees once you play.
-- Nothing is sent from here: Menu sends the look with the pick (the Slots remote), the server checks it
-- (CharacterLooks.clean) and filters the name.
--
--   CharacterCreator.open(gui, options)   over the start screen (gui: its ScreenGui). options: { title, action (the
--       main button's text), look? (where it starts: the slot's courier; nil: the default), onDone(look), onBack() }
--   CharacterCreator.close()
--   CharacterCreator.isOpen() -> boolean
-- ESC (a gamepad's B) is BACK; ENTER on the name box is nothing (the main button starts).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CharacterLooks = require(Shared.CharacterLooks)
local StyleBuild = require(Shared.StyleBuild)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local StylePreview = require(script.Parent.StylePreview)

local CharacterCreator = {}

export type Options = {
	title: string,
	action: string,
	look: CharacterLooks.Look?,
	onDone: (CharacterLooks.Look) -> (),
	onBack: () -> (),
}

local K = Theme.Contract
local W, H = 900, 540 -- the window at scale 1
local PREVIEW_W = 330
local FACE = "rbxasset://textures/face.png" -- the classic face (the made courier's head: shared/CharacterLooks.luau)
local SPIN = math.rad(18) -- the preview's turn a second while nobody drags it
local LABELS: { [string]: string } = {
	base = "Who you play",
	skin = "Skin",
	hair = "Hair",
	hairColor = "Hair colour",
	hat = "Hat",
	hatColor = "Hat colour",
	top = "Top",
	topColor = "Top colour",
	pants = "Trousers",
	extra = "Face",
}

local state: any = nil -- the open window: { frame, look, options, connections, refresh, preview … }

local function rgb(c: { number }?): Color3
	local v = c or { 128, 128, 128 }
	return Color3.fromRGB(v[1], v[2], v[3])
end

-- ── The preview ────────────────────────────────────────────────────────────

-- Your character, copied still (characters are not Archivable: allowed for the copy only); nil without one.
local function ownCopy(): Model?
	local character = Players.LocalPlayer.Character
	if not character or not character:FindFirstChild("UpperTorso") then
		return nil
	end
	local was = character.Archivable
	character.Archivable = true
	local ok, copy = pcall(function()
		return character:Clone()
	end)
	character.Archivable = was
	if not ok or not copy then
		return nil
	end
	local model = (copy :: any) :: Model
	for _, obj in model:GetDescendants() do
		if obj:IsA("BasePart") then
			obj.Anchored, obj.CanCollide, obj.CanQuery, obj.CanTouch = true, false, false, false
		elseif obj:IsA("LuaSourceContainer") or obj:IsA("JointInstance") or obj:IsA("Constraint") or obj:IsA("BillboardGui") or obj:IsA("Sound") or obj:IsA("ProximityPrompt") then
			obj:Destroy()
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local old = model:FindFirstChild(StyleBuild.Look)
	if old then
		old:Destroy() -- (a made courier's pieces from before: your own avatar shows without them)
	end
	return model
end

-- A made courier on the classic block body: its colours, the classic head and face, its pieces.
local function madeCopy(look: CharacterLooks.Look): Model
	local model = StylePreview.mannequin()
	local colors = CharacterLooks.colors(look)
	for name, field in CharacterLooks.Groups do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = rgb(colors[field])
		end
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		Ui.make("SpecialMesh", { MeshType = Enum.MeshType.Head, Scale = Vector3.new(1.2, 1.2, 1.2) }, head)
		Ui.make("Decal", { Texture = FACE, Face = Enum.NormalId.Front }, head)
	end
	StyleBuild.character(model, look, true)
	return model
end

local function showPreview()
	local s = state
	if not s then
		return
	end
	if s.model then
		s.model:Destroy()
		s.model = nil
	end
	local model: Model? = nil
	if CharacterLooks.custom(s.look) then
		model = madeCopy(s.look)
		s.note.Text = ""
	else
		model = ownCopy()
		s.note.Text = if model then "Your own Roblox avatar, as everybody sees it." else "Your own Roblox avatar (it shows once you are in the world)."
		if not model then
			model = StylePreview.mannequin()
		end
	end
	local shown = model :: Model
	-- turned round its own middle, its face to the camera (a copied body by its root's heading): its pivot at the
	-- origin, then the yaw (RenderStepped below)
	local cf = shown:GetBoundingBox()
	local root = shown:FindFirstChild("HumanoidRootPart")
	local heading = if root and root:IsA("BasePart") then root.CFrame.Rotation else CFrame.new()
	shown.WorldPivot = CFrame.new(cf.Position) * heading
	shown:PivotTo(CFrame.new(0, 0, 0))
	s.pivot = shown:GetPivot()
	shown.Parent = s.world
	s.model = shown
	shown:PivotTo(s.pivot * CFrame.Angles(0, s.yaw, 0))
end

-- ── The rows ───────────────────────────────────────────────────────────────

-- A row: its caps label, then a frame for what it holds (h px high).
local function row(parent: Instance, order: number, title: string, h: number): (any, any)
	local holder = Ui.make("Frame", {
		Name = "Row" .. order, LayoutOrder = order, Size = UDim2.new(1, -12, 0, h + 22), BackgroundTransparency = 1,
	}, parent)
	Ui.caps(holder, title, UDim2.new(1, 0, 0, 16), { Position = UDim2.fromOffset(0, 0) })
	local body = Ui.make("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, h), Position = UDim2.fromOffset(0, 20), BackgroundTransparency = 1 }, holder)
	return holder, body
end

-- The swatches of a colour list; returns a refresh (the chosen one ringed).
local function swatches(body: any, field: string, list: { Config.LookOption }, size: number, pick: (string, string) -> ()): () -> ()
	Ui.make("UIGridLayout", { CellSize = UDim2.fromOffset(size, size), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, body)
	local rings: { [string]: UIStroke } = {}
	for i, option in list do
		local swatch = Ui.make("TextButton", {
			Name = option.id, LayoutOrder = i, Size = UDim2.fromOffset(size, size), Text = "", AutoButtonColor = false,
			BackgroundColor3 = rgb(option.rgb), BorderSizePixel = 0,
		}, body)
		Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, swatch)
		rings[option.id] = Ui.make("UIStroke", { Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, swatch)
		swatch.Activated:Connect(function()
			pick(field, option.id)
		end)
	end
	return function()
		local chosen = state and state.look[field]
		for id, ring in rings do
			ring.Color = if id == chosen then K.text else K.line
			ring.Transparency = if id == chosen then 0 else 0.55
			ring.Thickness = if id == chosen then 3 else 1
		end
	end
end

-- ‹ name › through a list of styles; returns a refresh.
local function stepper(body: any, field: string, list: { Config.LookOption }, pick: (string, string) -> ()): () -> ()
	local label = Ui.label(body, "", UDim2.new(1, -112, 1, 0), {
		Position = UDim2.fromOffset(56, 0), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.HeadingFont,
	})
	local function step(by: number)
		local at = 1
		for i, option in list do
			if option.id == state.look[field] then
				at = i
			end
		end
		pick(field, list[(at - 1 + by) % #list + 1].id)
	end
	local back = Ui.button(body, "‹", UDim2.fromOffset(48, 40), Theme.Postage.paper, function() step(-1) end)
	back.TextSize = 24
	local fwd = Ui.button(body, "›", UDim2.fromOffset(48, 40), Theme.Postage.paper, function() step(1) end)
	fwd.TextSize = 24
	fwd.AnchorPoint, fwd.Position = Vector2.new(1, 0), UDim2.fromScale(1, 0)
	return function()
		local id = state and state.look[field]
		for i, option in list do
			if option.id == id then
				label.Text = `{option.name}   ·   {i} / {#list}`
			end
		end
	end
end

-- ── The window ─────────────────────────────────────────────────────────────

function CharacterCreator.isOpen(): boolean
	return state ~= nil
end

function CharacterCreator.close()
	local s = state
	if not s then
		return
	end
	state = nil
	for _, connection in s.connections do
		connection:Disconnect()
	end
	s.frame:Destroy()
end

function CharacterCreator.open(gui: Instance, options: Options)
	CharacterCreator.close()
	local look = CharacterLooks.clean(options.look or CharacterLooks.default())
	look.name = look.name or Players.LocalPlayer.DisplayName
	local touch = Ui.touchLayout()
	local s: any = { look = look, options = options, connections = {}, yaw = math.rad(-20), dragging = false, idleAt = 0 }
	state = s

	local shade = Ui.make("Frame", {
		Name = "CharacterCreator", Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.charcoal, BackgroundTransparency = 0.35,
		Active = true, ZIndex = 30,
	}, gui)
	s.frame = shade
	local card = Ui.make("Frame", {
		Name = "Card", Size = UDim2.fromOffset(W, H), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = K.charcoal, BackgroundTransparency = 0.02, BorderSizePixel = 0, ZIndex = 31,
	}, shade)
	Ui.stroke(card, K.line, 1).Transparency = 0.5
	local scale = Ui.make("UIScale", {}, card)
	local brand = Ui.brand(card, 20, { Position = UDim2.fromOffset(24, 18) })
	local title = Ui.label(card, string.upper(options.title), UDim2.fromOffset(W - 260, 30), {
		Position = UDim2.fromOffset(24 + brand.Size.X.Offset + 16, 14), TextSize = 22, Font = Theme.DisplayFont,
	})
	title.TextTruncate = Enum.TextTruncate.AtEnd

	-- the preview (left): a ViewportFrame, the name under it, 🎲 RANDOM
	local stage = Ui.make("Frame", {
		Name = "Stage", Size = UDim2.fromOffset(PREVIEW_W, H - 150), Position = UDim2.fromOffset(24, 62),
		BackgroundColor3 = K.recessed, BorderSizePixel = 0,
	}, card)
	Ui.make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(46, 54, 66), K.recessed),
	}, stage)
	local viewport = Ui.make("ViewportFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Ambient = Color3.fromRGB(150, 158, 170),
		LightColor = Color3.fromRGB(255, 244, 228), LightDirection = Vector3.new(-0.6, -1, -0.8), Active = true,
	}, stage)
	local world = Ui.make("WorldModel", {}, viewport)
	s.world = world
	local camera = Ui.make("Camera", { FieldOfView = 30 }, viewport)
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.9, -13.4), Vector3.new(0, 0.2, 0))
	viewport.CurrentCamera = camera
	s.note = Ui.label(stage, "", UDim2.new(1, -20, 0, 36), {
		Position = UDim2.new(0, 10, 1, -40), TextSize = 13, Font = Theme.Font, TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Ui.label(stage, "Drag to turn", UDim2.new(1, -20, 0, 18), {
		Position = UDim2.fromOffset(10, 8), TextSize = 12, Font = Theme.Font, TextColor3 = K.secondary, TextXAlignment = Enum.TextXAlignment.Right,
	})
	local random = Ui.button(card, "🎲  RANDOM", UDim2.fromOffset(PREVIEW_W, 44), Theme.Postage.paper, function()
		local name = s.look.name
		s.look = CharacterLooks.random(function(n: number): number
			return math.random(1, n)
		end)
		s.look.name = name
		s.refresh()
	end)
	random.Position = UDim2.fromOffset(24, H - 80)

	-- the choices (right): the name, then the rows in a scrolling list
	local right = 24 + PREVIEW_W + 24
	local rightW = W - right - 24
	Ui.caps(card, "Name", UDim2.fromOffset(rightW, 16), { Position = UDim2.fromOffset(right, 62) })
	local nameBox = Ui.make("TextBox", {
		Name = "NameBox", Size = UDim2.fromOffset(rightW, 40), Position = UDim2.fromOffset(right, 82),
		BackgroundColor3 = K.row, BorderSizePixel = 0, Text = look.name or "", PlaceholderText = "Your courier's name",
		ClearTextOnFocus = false, TextColor3 = K.text, PlaceholderColor3 = K.line, Font = Theme.HeadingFont, TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, nameBox)
	Ui.stroke(nameBox, K.line, 1).Transparency = 0.5
	table.insert(s.connections, nameBox:GetPropertyChangedSignal("Text"):Connect(function()
		local text = nameBox.Text
		if (utf8.len(text) or 0) > Config.SaveSlots.NameMax then
			nameBox.Text = string.sub(text, 1, (utf8.offset(text, Config.SaveSlots.NameMax + 1) or (#text + 1)) - 1)
			return
		end
		s.look.name = text
	end))
	local list = Ui.make("ScrollingFrame", {
		Name = "Choices", Size = UDim2.fromOffset(rightW, H - 222), Position = UDim2.fromOffset(right, 134),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, ScrollBarImageColor3 = K.line,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
	}, card)
	Ui.make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)

	local refreshers: { () -> () } = {}
	local customRows: { GuiObject } = {}
	local function pick(field: string, id: string)
		s.look[field] = id
		s.refresh()
	end
	local swatch = if touch then 40 else 30
	for order, entry in CharacterLooks.Fields do
		local field = entry.field
		if field == "base" then
			local _, body = row(list, order, LABELS[field], 40)
			local buttons: { [string]: any } = {}
			for i, option in entry.list do
				local button = Ui.button(body, option.name, UDim2.new(0.5, -5, 1, 0), Theme.Postage.paper, function()
					pick(field, option.id)
				end)
				button.Position = UDim2.new((i - 1) * 0.5, if i > 1 then 5 else 0, 0, 0)
				button.TextSize = 15
				buttons[option.id] = button
			end
			table.insert(refreshers, function()
				for id, button in buttons do
					button.BackgroundColor3 = if id == s.look.base then K.red else Theme.Postage.paper
				end
			end)
			continue
		end
		local colour = entry.list[1].rgb ~= nil
		local perRow = math.max(1, math.floor((rightW - 4) / (swatch + 8)))
		local lines = math.ceil(#entry.list / perRow)
		local holder, body = row(list, order, LABELS[field] or field, if colour then lines * (swatch + 8) - 4 else 40)
		table.insert(customRows, holder)
		table.insert(refreshers, if colour then swatches(body, field, entry.list, swatch, pick) else stepper(body, field, entry.list, pick))
	end
	local ownNote = Ui.label(list, "You play as your own Roblox avatar: its head, face, clothes and accessories, on the courier's body. Pick MAKE A COURIER to make one here.", UDim2.new(1, -12, 0, 60), {
		LayoutOrder = 99, TextSize = 14, Font = Theme.Font, TextColor3 = K.secondary, Visible = false,
	})

	-- the actions (bottom right)
	local back = Ui.ghostButton(card, "‹  BACK", UDim2.fromOffset(140, 48), nil, function()
		local onBack = s.options.onBack
		CharacterCreator.close()
		onBack()
	end)
	back.Position = UDim2.fromOffset(right, H - 80)
	local done = Ui.button(card, options.action, UDim2.fromOffset(rightW - 156, 48), K.red, function()
		local chosen = CharacterLooks.clean(s.look)
		chosen.name = CharacterLooks.name(nameBox.Text)
		local onDone = s.options.onDone
		CharacterCreator.close()
		onDone(chosen)
	end)
	done.Position = UDim2.fromOffset(right + 156, H - 80)
	done.TextSize = 20

	s.refresh = function()
		for _, refresh in refreshers do
			refresh()
		end
		local custom = CharacterLooks.custom(s.look)
		for _, holder in customRows do
			holder.Visible = custom
		end
		ownNote.Visible = not custom
		random.Visible = true
		showPreview()
	end
	s.refresh()

	-- the window follows the screen
	local function fit()
		local cam = workspace.CurrentCamera
		local v = if cam then cam.ViewportSize else Vector2.new(1280, 720)
		scale.Scale = math.max(0.4, math.min((v.X - 24) / W, (v.Y - 24) / H, 1.1))
	end
	fit()
	local cam = workspace.CurrentCamera
	if cam then
		table.insert(s.connections, cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit))
	end

	-- the turn: slow by itself, by hand while you drag (a moment after you let go it turns by itself again)
	local lastX = 0
	table.insert(s.connections, viewport.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			s.dragging, lastX = true, input.Position.X
		end
	end))
	table.insert(s.connections, UserInputService.InputChanged:Connect(function(input: InputObject)
		if s.dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			s.yaw += (input.Position.X - lastX) * 0.012
			lastX = input.Position.X
			s.idleAt = os.clock()
		end
	end))
	table.insert(s.connections, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			s.dragging = false
			s.idleAt = os.clock()
		end
	end))
	table.insert(s.connections, RunService.RenderStepped:Connect(function(dt: number)
		if not s.dragging and os.clock() - s.idleAt > 2 then
			s.yaw += SPIN * dt
		end
		local model = s.model
		if model and s.pivot then
			model:PivotTo(s.pivot * CFrame.Angles(0, s.yaw, 0))
		end
	end))
	-- ESC / B: BACK
	table.insert(s.connections, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			local onBack = s.options.onBack
			CharacterCreator.close()
			onBack()
		end
	end))
end

return CharacterCreator
