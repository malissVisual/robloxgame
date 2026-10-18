--!strict
-- 10.4 the ride (the owner: "there is no driving the car any more, so every time you go to a place, an animation of
-- you driving there"); 10.6 the floating islands (the owner: travel by a fade only): when a run takes you to its house,
-- and when it takes you back to the lobby, a clean card over the jump's fade (server/Runs.luau sends { kind = "ride",
-- to, back, difficulty?, party?, seconds, round? (10.5: how many ride to the round) } on the Runs remote just before it;
-- Config.Runs.Ride). A dark card in the intro's look (src/first/Loading.client.luau): "ON THE WAY TO" ("BACK TO" on
-- the way home) over "→ THE POND CABIN" (the place's name, the lobby's on the way back: Config.Runs.Ride.Home), under
-- it the run's difficulty in its colour, who comes along, a round's movers; a thin line fills while it shows (the
-- island streams in behind it). Your controls are off while it shows; it fades into the place (Out s). Reduced Motion:
-- the name does not slide in.
--   RideUi.start()            listens to the Runs remote
--   RideUi.show(message)      the card now (a card already showing goes first)
--   RideUi.isShowing() -> boolean

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local PhoneMotion = require(script.Parent.PhoneMotion)

local RideUi = {}

local player = Players.LocalPlayer
local R = Config.Runs.Ride
local current: any = nil -- the card showing: { gui, started }

local display = Enum.Font.GothamBlack
pcall(function()
	display = (Enum.Font :: any).LuckiestGuy -- (the store logo's font, as the intro's)
end)

local INK = Color3.fromRGB(12, 16, 30) -- the card's dark
local DEEP = Color3.fromRGB(28, 40, 74) -- … its glow in the middle
local ORANGE = Color3.fromRGB(245, 124, 30)

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	return Ui.make(className, props, parent)
end

-- Freezes / frees your character (never waits long: a missing PlayerModule must not hold the card up).
local function controls(enabled: boolean)
	pcall(function()
		local scripts = player:FindFirstChild("PlayerScripts")
		local module = scripts and scripts:FindFirstChild("PlayerModule")
		if not module or not module:IsA("ModuleScript") then
			return
		end
		local c = (require(module) :: any):GetControls()
		if enabled then
			c:Enable()
		else
			c:Disable()
		end
	end)
end

function RideUi.isShowing(): boolean
	return current ~= nil
end

local function close(ride: any)
	if current == ride then
		current = nil
	end
	if ride.gui then
		ride.gui:Destroy()
	end
end

-- The card's line: the difficulty, who rides along (three names at most, "+2"), a round's movers.
local function lineOf(message: any, def: any): string
	local bits: { string } = {}
	if def then
		table.insert(bits, string.upper(def.name))
	end
	local party = if type(message.party) == "table" then message.party else {}
	if #party > 0 then
		local names: { string } = {}
		for i, name in party do
			if i <= 3 and type(name) == "string" then
				table.insert(names, name)
			end
		end
		table.insert(bits, "with " .. table.concat(names, ", ") .. (if #party > 3 then ` +{#party - 3}` else ""))
	end
	local movers = tonumber(message.round) -- 10.5 rounds: everybody in the game rides there (how many)
	if movers then
		table.insert(bits, if movers > 1 then `ROUND · {movers} MOVERS` else "ROUND")
	end
	return table.concat(bits, "   ·   ")
end

function RideUi.show(message: any)
	if current then
		close(current)
	end
	local back = message.back == true
	local seconds = if type(message.seconds) == "number" then math.clamp(message.seconds, 1, 8) else (if back then R.Back else R.To)
	local difficulty = if type(message.difficulty) == "string" then message.difficulty else nil
	local def: any = nil
	for _, d in Config.Runs.Difficulties do
		if d.id == difficulty then
			def = d
		end
	end
	local to = if type(message.to) == "string" then message.to else "the house"
	local tint = if def then rgb(def.color) else ORANGE
	local reduced = PhoneMotion.reducedMotion()
	local ride: any = { started = os.clock() }
	current = ride

	local gui = make("ScreenGui", {
		Name = "Ride", DisplayOrder = 150, IgnoreGuiInset = true, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	ride.gui = gui
	local root = make("CanvasGroup", { Name = "Card", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = 1 }, gui)
	local shade = make("Frame", { Name = "Fade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 0 }, root)
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, INK),
			ColorSequenceKeypoint.new(0.5, DEEP),
			ColorSequenceKeypoint.new(1, INK),
		}),
	}, shade) -- (on a frame of its own: a gradient on the CanvasGroup would tint all of it)

	-- where you are going, in the middle
	local card = make("Frame", {
		Name = "Where", Size = UDim2.fromScale(0.7, 0.24), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1, ZIndex = 2,
	}, root)
	make("UISizeConstraint", { MinSize = Vector2.new(280, 110) }, card)
	local lead = make("TextLabel", {
		Name = "Lead", Size = UDim2.fromScale(1, 0.18), BackgroundTransparency = 1, Text = if back then "BACK TO" else "ON THE WAY TO",
		Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), TextTransparency = 0.25, ZIndex = 2,
	}, card)
	make("UITextSizeConstraint", { MaxTextSize = 18 }, lead)
	local slide = if reduced then 0 else 24
	local title = make("TextLabel", {
		Name = "Title", Size = UDim2.fromScale(1, 0.46), Position = UDim2.new(0, slide, 0.2, 0), BackgroundTransparency = 1,
		Text = "→ " .. string.upper(to), Font = display, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), ZIndex = 2,
	}, card)
	make("UITextSizeConstraint", { MaxTextSize = 56 }, title)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 238, 80), Color3.fromRGB(248, 136, 20)) }, title)
	make("UIStroke", { Color = Color3.fromRGB(150, 22, 28), Thickness = 3, LineJoinMode = Enum.LineJoinMode.Round }, title)
	local line = make("TextLabel", {
		Name = "Line", Size = UDim2.fromScale(1, 0.18), Position = UDim2.fromScale(0, 0.7), BackgroundTransparency = 1, Text = lineOf(message, def),
		Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = if def then tint else Color3.new(1, 1, 1), ZIndex = 2,
	}, card)
	make("UITextSizeConstraint", { MaxTextSize = 20 }, line)
	make("UIStroke", { Color = Color3.fromRGB(8, 10, 20), Thickness = 1.5, Transparency = 0.2 }, line)
	-- the thin line that fills while it shows
	local bar = make("Frame", {
		Name = "Bar", Size = UDim2.new(0.36, 0, 0, 4), Position = UDim2.new(0.5, 0, 1, 18), AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 2,
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, bar)
	local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = tint, BorderSizePixel = 0, ZIndex = 3 }, bar)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, fill)

	-- in over the jump's fade, the name sliding in, the line filling; then it fades into the place
	controls(false)
	TweenService:Create(root, TweenInfo.new(0.25), { GroupTransparency = 0 }):Play()
	if slide ~= 0 then
		TweenService:Create(title, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 0.2) }):Play()
	end
	TweenService:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Size = UDim2.fromScale(1, 1) }):Play()
	task.delay(seconds, function()
		if current ~= ride then
			return
		end
		controls(true)
		local fade = TweenService:Create(root, TweenInfo.new(R.Out), { GroupTransparency = 1 })
		fade:Play()
		fade.Completed:Once(function()
			close(ride)
		end)
	end)
end

function RideUi.start()
	Net.get("Runs").OnClientEvent:Connect(function(message: any)
		if type(message) == "table" and message.kind == "ride" then
			RideUi.show(message)
		end
	end)
end

return RideUi
