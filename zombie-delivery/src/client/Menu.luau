--!strict
-- The start screen: the camera drifts over the city (the zombies roam the streets), the title, your company's
-- money and deliveries, and PLAY. PLAY fades to black, gives the camera back to your character and asks the server
-- for your car.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)

local Menu = {}

local player = Players.LocalPlayer
local gui: any = nil
local infoLabel: any = nil
local flying = false

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

local function controls(enabled: boolean)
	pcall(function()
		local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
		local c = playerModule:GetControls()
		if enabled then
			c:Enable()
		else
			c:Disable()
		end
	end)
end

function Menu.setState(state: any)
	if infoLabel and state then
		infoLabel.Text = `Your company: {Ui.money(state.money)}  ·  {state.deliveries} deliveries  ·  {state.kills} zombies`
	end
end

function Menu.show(onPlay: () -> ())
	gui = Ui.make("ScreenGui", {
		Name = "StartScreen",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))

	-- Dark edges.
	for _, info in { { 0, 0 }, { 1, 180 } } do
		local band = Ui.make("Frame", {
			Size = UDim2.fromScale(1, 0.45),
			Position = UDim2.fromScale(0, if info[1] == 0 then 0 else 0.55),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
		}, gui)
		Ui.make("UIGradient", {
			Rotation = 90 + info[2],
			Transparency = NumberSequence.new(0.1, 1),
		}, band)
	end

	local center = Ui.make("Frame", {
		Size = UDim2.fromOffset(760, 420),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
	}, gui)
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	Ui.make("UIScale", { Scale = math.clamp(math.min(viewport.X / 900, viewport.Y / 560), 0.5, 1.2) }, center)

	local function title(text: string, y: number, size: number, color: Color3)
		local label = Ui.make("TextLabel", {
			Size = UDim2.new(1, 0, 0, size + 10),
			Position = UDim2.fromOffset(0, y),
			BackgroundTransparency = 1,
			Text = text,
			TextSize = size,
			Font = Enum.Font.GothamBlack,
			TextColor3 = color,
		}, center)
		Ui.make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 4 }, label)
		return label
	end
	title("ZOMBIE", 0, 96, Color3.fromRGB(150, 230, 90))
	title("DELIVERY", 92, 96, Color3.fromRGB(255, 196, 50))
	title("Deliver. Survive. Get paid.", 200, 26, Color3.fromRGB(240, 240, 235))

	local play = Ui.button(center, "PLAY", UDim2.fromOffset(300, 84), Color3.fromRGB(70, 190, 90), function() end)
	play.Position = UDim2.fromOffset(230, 262)
	play.TextSize = 46
	-- A slow pulse.
	TweenService:Create(play, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundColor3 = Color3.fromRGB(100, 225, 120) }):Play()

	infoLabel = title("Loading your company...", 360, 20, Color3.fromRGB(220, 220, 210))
	Ui.make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 1, -34),
		BackgroundTransparency = 1,
		Text = "WASD drive · hold left mouse shoot · F auto-aim · 1-5 items · M map · J jobs · B backpack",
		TextSize = 16,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(200, 200, 200),
		TextStrokeTransparency = 0.4,
	}, gui)

	local fade = Ui.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 50,
	}, gui)

	controls(false)
	fly()

	local pressed = false
	play.Activated:Connect(function()
		if pressed then
			return
		end
		pressed = true
		local t = TweenService:Create(fade, TweenInfo.new(0.4), { BackgroundTransparency = 0 })
		t:Play()
		t.Completed:Wait()
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
		controls(true)
		onPlay()
		task.wait(0.6)
		local out = TweenService:Create(fade, TweenInfo.new(0.6), { BackgroundTransparency = 1 })
		out:Play()
		out.Completed:Wait()
		gui:Destroy()
		gui = nil
		infoLabel = nil
	end)
end

return Menu
