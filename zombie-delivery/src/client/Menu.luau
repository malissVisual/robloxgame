--!strict
-- The start screen: the camera drifts over the city (the zombies roam the streets), the title, your company's
-- money and deliveries, and PLAY. PLAY fades to black, gives the camera back to your character and asks the server
-- for your car.
-- 3.8 (the contract UI, design/ui-contract/): the card is a flat charcoal rectangle with a thin red rule, over a
-- charcoal scrim that fades out to the right (the city stays the main view); PLAY is the main action (a red rule
-- under it); the controls are a second card.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)

local Menu = {}

local player = Players.LocalPlayer
local gui: any = nil
local infoLabel: any = nil
local flying = false
local lastState: any = nil

-- Camera stops around the depot (close enough to be streamed in), looped.
local SHOTS = {
	{ Vector3.new(-260, 70, 300), Vector3.new(0, 10, 0) },
	{ Vector3.new(260, 50, 260), Vector3.new(100, 5, -60) },
	{ Vector3.new(560, 45, 140), Vector3.new(840, 0, 72) },
	{ Vector3.new(300, 110, -420), Vector3.new(0, 0, -150) },
	{ Vector3.new(-420, 40, -200), Vector3.new(-200, 5, 0) },
}

local function shot(n: number): CFrame
	local s = SHOTS[(n - 1) % #SHOTS + 1]
	return CFrame.lookAt(s[1], s[2])
end

local function fly()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	flying = true
	task.spawn(function()
		local n = 1
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = shot(n)
		while flying do
			camera.CameraType = Enum.CameraType.Scriptable
			local tween = TweenService:Create(camera, TweenInfo.new(9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = shot(n + 1) })
			tween:Play()
			local started = os.clock()
			while flying and os.clock() - started < 9 do
				task.wait(0.1)
			end
			tween:Cancel()
			n += 1
		end
	end)
end

-- Freezes / frees your character while the start screen is up. Never waits long (a missing PlayerModule must not
-- hold the start screen up).
local function controls(enabled: boolean)
	pcall(function()
		local scripts = player:WaitForChild("PlayerScripts", 5)
		local module = scripts and scripts:WaitForChild("PlayerModule", 5)
		if not module or not module:IsA("ModuleScript") then
			return
		end
		local playerModule = require(module) :: any
		local c = playerModule:GetControls()
		if enabled then
			c:Enable()
		else
			c:Disable()
		end
	end)
end

function Menu.setState(state: any)
	lastState = state
	if infoLabel and state then
		infoLabel.Text = `{Ui.money(state.money)}  ·  {state.deliveries} deliveries  ·  {state.kills} kills`
	end
end

function Menu.show(onPlay: () -> ())
	gui = Ui.make("ScreenGui", {
		Name = "StartScreen",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))

	local C = Theme.Colors
	local P = Theme.Postage
	if Theme.Images.menuBackground ~= "" then
		Ui.make("ImageLabel", {
			Name = "MenuArtwork", Size = UDim2.fromScale(1, 1), Image = Theme.Images.menuBackground,
			ScaleType = Enum.ScaleType.Crop, BackgroundTransparency = 1, ZIndex = 1,
		}, gui)
	end
	-- A localized charcoal scrim (opaque on the left, gone on the right) keeps the real-time city the focal point.
	local veil = Ui.make("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.lavender,
		BackgroundTransparency = 0.45, BorderSizePixel = 0, Active = false, ZIndex = 2,
	}, gui)
	Ui.make("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.8) }),
		Rotation = 0,
	}, veil)

	local center = Ui.make("Frame", {
		Name = "DispatchMenu", Size = UDim2.fromOffset(560, 500),
		Position = UDim2.new(0.08, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1, ZIndex = 5,
	}, gui)
	local menuScale = Ui.make("UIScale", {}, center)
	-- The shift card: a flat charcoal rectangle, a thin red rule down its left edge.
	local face = Ui.ticket(center, UDim2.fromScale(1, 1), UDim2.new())
	face.BackgroundColor3 = P.lavender
	face.BackgroundTransparency = 0.06
	local faceTicket = face.Parent
	faceTicket.Name = "ShiftCard"
	faceTicket.ZIndex = 5
	Ui.make("Frame", {
		Size = UDim2.new(0, 3, 1, -48), Position = UDim2.fromOffset(0, 24),
		BackgroundColor3 = C.red, BorderSizePixel = 0, ZIndex = 6,
	}, face)
	Ui.caps(face, "Dead End Dispatch   ·   delivery company", UDim2.fromOffset(510, 20), {
		Position = UDim2.fromOffset(24, 22), TextSize = 14, ZIndex = 6,
	})
	local topTitle = Ui.label(face, "ZOMBIE", UDim2.fromOffset(510, 76), {
		Position = UDim2.fromOffset(24, 60), TextSize = 64, Font = Theme.DisplayFont, ZIndex = 6,
	})
	local bottomTitle = Ui.label(face, "DELIVERY", UDim2.fromOffset(510, 76), {
		Position = UDim2.fromOffset(24, 128), TextSize = 64, TextColor3 = P.violet, Font = Theme.DisplayFont, ZIndex = 6,
	})
	if Theme.Images.logo ~= "" then
		topTitle.Visible, bottomTitle.Visible = false, false
		Ui.make("ImageLabel", {
			Size = UDim2.fromOffset(510, 158), Position = UDim2.fromOffset(24, 52),
			Image = Theme.Images.logo, ScaleType = Enum.ScaleType.Fit, BackgroundTransparency = 1, ZIndex = 6,
		}, face)
	end
	local tagline = Ui.label(face, "Deliver. Survive. Get paid.", UDim2.fromOffset(510, 30), {
		Position = UDim2.fromOffset(24, 216), TextSize = 22, Font = Theme.Font, TextColor3 = C.dim, ZIndex = 6,
	})
	local company = Ui.panel(face, UDim2.fromOffset(512, 64), UDim2.fromOffset(24, 264))
	company.BackgroundColor3 = P.lavender
	company.ZIndex = 6
	Ui.caps(company, "Your company", UDim2.fromOffset(488, 16), {
		Position = UDim2.fromOffset(12, 10), ZIndex = 7,
	})
	infoLabel = Ui.label(company, "Loading your company...", UDim2.fromOffset(488, 24), {
		Position = UDim2.fromOffset(12, 30), TextSize = 17, ZIndex = 7,
	})
	Menu.setState(lastState)
	local play = Ui.button(face, "PLAY  /  START YOUR SHIFT", UDim2.fromOffset(512, 72), C.yellow, function() end)
	play.Position = UDim2.fromOffset(24, 344)
	play.TextSize = 23
	play.ZIndex = 7

	-- Controls live on a separate card so the start screen remains readable on phones.
	local help = Ui.ticket(center, UDim2.fromScale(1, 1), UDim2.new())
	help.BackgroundColor3 = P.lavender
	help.BackgroundTransparency = 0.06
	local helpTicket = help.Parent
	helpTicket.Name = "ControlsCard"
	helpTicket.ZIndex, helpTicket.Visible = 15, false
	Ui.label(help, "Controls", UDim2.fromOffset(460, 38), {
		Position = UDim2.fromOffset(24, 22), TextSize = 28, Font = Theme.DisplayFont, ZIndex = 16,
	})
	local closeHelp = Ui.ghostButton(help, "‹  BACK", UDim2.fromOffset(116, 48), nil, function()
		helpTicket.Visible, faceTicket.Visible = false, true
	end)
	closeHelp.Position, closeHelp.ZIndex = UDim2.fromOffset(420, 20), 16
	local touchLayout = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local controlsText: { { string } } = if touchLayout then {
		{ "MOVE", "Left thumbstick    ·    SPRINT: on / off (breath)" }, { "SHOOT", "FIRE button (draws the gun first)" },
		{ "HANDS", "DRAW / PUNCH buttons left of FIRE" },
		{ "CARGO", "Tap prompts to pick up and load" }, { "PUT DOWN", "PUT DOWN / LET GO / SET DOWN button" },
		{ "WEAPONS", "Tap the weapon line: the wheel" }, { "ITEMS", "Tap the item tags" },
		{ "NAVIGATE", "MAP / CREW / MENU buttons" }, { "EXIT CAR", "EXIT button or the jump button" },
	} else {
		{ "MOVE", "WASD / arrows    ·    Shift: sprint (breath)" }, { "COMBAT", "Mouse: aim    ·    RMB: aim    ·    LMB: shoot" },
		{ "HANDS", "B: holster / draw    ·    V: punch / strike" },
		{ "CARGO", "E: pick up / load    ·    G: put down" }, { "EQUIPMENT", "Q: switch weapon    ·    1–5: items" },
		{ "WINDOWS", "J: jobs    ·    M: map    ·    I: bag" }, { "MOUSE", "Alt: free cursor" },
		{ "VEHICLE", "E: get in / get out    ·    Space: out too" }, { "ADMIN", "P: admin (when authorized)" },
	}
	local rows = {}
	for i, entry in controlsText do
		local row = Ui.make("Frame", {
			Size = UDim2.fromOffset(512, 40), Position = UDim2.fromOffset(24, 84 + (i - 1) * 42), -- 3.9: nine rows fit
			BackgroundColor3 = P.lavender, BackgroundTransparency = if i % 2 == 0 then 1 else 0.2,
			BorderSizePixel = 0, ZIndex = 16,
		}, help)
		Ui.corner(row)
		Ui.label(row, entry[1], UDim2.fromOffset(128, 40), { Position = UDim2.fromOffset(10, 0), TextSize = 14, TextColor3 = P.violet, ZIndex = 17 })
		Ui.label(row, entry[2], UDim2.fromOffset(366, 40), { Position = UDim2.fromOffset(140, 0), TextSize = 16, Font = Theme.Font, ZIndex = 17 })
		table.insert(rows, row)
	end
	local controlsButton = Ui.ghostButton(face, "CONTROLS", UDim2.fromOffset(240, 44), nil, function()
		helpTicket.Visible, faceTicket.Visible = true, false
	end)
	controlsButton.Position, controlsButton.ZIndex = UDim2.fromOffset(24, 430), 7
	local enterHint = Ui.label(face, if touchLayout then "Tap PLAY to begin" else "Press ENTER to begin", UDim2.fromOffset(244, 44), {
		Position = UDim2.fromOffset(292, 430), TextSize = 15, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 7,
	})
	-- Over the world: a compact charcoal label behind the text.
	local version = Ui.make("TextLabel", {
		Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.new(1, -12, 1, -10), AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 0, BackgroundColor3 = P.pill, Text = `version {Config.Version}`,
		TextSize = 14, Font = Theme.MonoFont, TextColor3 = C.dim, ZIndex = 6,
	}, gui)
	Ui.corner(version)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, version)

	local viewportConnection: RBXScriptConnection? = nil
	local cameraConnection: RBXScriptConnection? = nil
	local function fitMenu()
		local camera = workspace.CurrentCamera
		local v = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local compact = v.Y < 480
		local narrow = v.X < 600 and not compact
		local height = if compact then 440 elseif narrow and helpTicket.Visible then 820 elseif narrow then 650 else 500
		local factor = math.max(0.35, math.min((v.X - 32) / 560, (v.Y - 64) / height, 1.05))
		menuScale.Scale = factor
		center.Size = UDim2.fromOffset(560, height)
		center.Position = if v.X < 900 then UDim2.fromScale(0.5, 0.5) else UDim2.new(0.08, 0, 0.5, 0)
		center.AnchorPoint = if v.X < 900 then Vector2.new(0.5, 0.5) else Vector2.new(0, 0.5)
		topTitle.Position = UDim2.fromOffset(24, if compact then 48 else 60)
		bottomTitle.Position = UDim2.fromOffset(24, if compact then 110 else 128)
		tagline.Position = UDim2.fromOffset(24, if compact then 192 else 216)
		company.Position = UDim2.fromOffset(24, if compact then 234 else 264)
		company.Size = UDim2.fromOffset(512, if narrow then 112 else 64)
		infoLabel.TextSize = math.max(17, 14 / factor)
		infoLabel.Size = UDim2.fromOffset(488, if narrow then 70 else 24)
		tagline.TextSize = math.max(22, 14 / factor)
		enterHint.TextSize = math.max(15, 12 / factor)
		play.Position = UDim2.fromOffset(24, if compact then 308 elseif narrow then 392 else 344)
		play.Size = UDim2.fromOffset(512, math.max(if compact then 56 else 72, 44 / factor))
		local controlY = if compact then 374 elseif narrow then 498 else 430
		controlsButton.Position = UDim2.fromOffset(24, controlY)
		controlsButton.Size = UDim2.fromOffset(240, math.max(44, 44 / factor))
		enterHint.Position = UDim2.fromOffset(292, controlY)
		closeHelp.Size = UDim2.fromOffset(116, math.max(48, 44 / factor))
		for i, row in rows do
			local gap = if compact then 38 elseif narrow then 82 else 46 -- (3.9: nine rows still fit the card)
			local rowHeight = if narrow then 80 else 44
			row.Position = UDim2.fromOffset(24, 84 + (i - 1) * gap)
			row.Size = UDim2.fromOffset(512, rowHeight)
			for _, child in row:GetChildren() do
				if child:IsA("TextLabel") then
					child.Size = UDim2.new(child.Size.X.Scale, child.Size.X.Offset, 0, rowHeight)
					child.TextSize = math.max(16, 13 / factor)
				end
			end
		end
	end
	local function watchCamera()
		if viewportConnection then viewportConnection:Disconnect() end
		local camera = workspace.CurrentCamera
		viewportConnection = if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitMenu) else nil
		fitMenu()
	end
	cameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()
	helpTicket:GetPropertyChangedSignal("Visible"):Connect(fitMenu)

	-- The black fade only shows (and only exists in front of PLAY) after PLAY was pressed.
	local fade = Ui.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = P.veil,
		BackgroundTransparency = 1,
		Visible = false,
		Active = false,
		ZIndex = 50,
	}, gui)

	local pressed = false
	local keyConnection: RBXScriptConnection? = nil
	local function start()
		if pressed then
			return
		end
		pressed = true
		if viewportConnection then viewportConnection:Disconnect() end
		if cameraConnection then cameraConnection:Disconnect() end
		if keyConnection then
			keyConnection:Disconnect()
		end
		fade.Visible = true
		local t = TweenService:Create(fade, TweenInfo.new(0.4), { BackgroundTransparency = 0 })
		t:Play()
		task.wait(0.45)
		flying = false
		for _, child in gui:GetChildren() do
			if child ~= fade then
				child:Destroy()
			end
		end
		local cam = workspace.CurrentCamera
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if cam then
			cam.CameraType = Enum.CameraType.Custom
			if humanoid then
				cam.CameraSubject = humanoid
			end
		end
		task.spawn(controls, true)
		local ok, err = pcall(function()
			onPlay()
		end)
		if not ok then
			warn("[Menu] starting the game failed: " .. tostring(err))
		end
		task.wait(0.6)
		TweenService:Create(fade, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		task.wait(0.65)
		gui:Destroy()
		gui = nil
		infoLabel = nil
	end
	play.Activated:Connect(start)
	keyConnection = UserInputService.InputBegan:Connect(function(input, processed)
		-- (not the Enter that sends a chat line, nor a press a button already took)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter or key == Enum.KeyCode.ButtonA then
			task.spawn(start)
		end
	end)

	task.spawn(controls, false)
	fly()
end

return Menu
