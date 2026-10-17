--!strict
-- 10.4 the ride (the owner: "there is no driving the car any more, so every time you go to a place, an animation of
-- you driving there"): when a run takes you to its house, and when it takes you back to the lobby, the Deliveros van
-- drives across the screen over the jump's fade (server/Runs.luau sends { kind = "ride", to, back, difficulty?, party?,
-- seconds, round? (10.5: how many ride to the round) } on the Runs remote just before it; Config.Runs.Ride). A short flat scene in the intro's look
-- (src/first/Loading.client.luau): the sky of the run's difficulty (a fresh morning for Easy … a night with the moon
-- and the van's lamps for Nightmare; a warm evening on the way back), hills, trees and fence posts going by at their
-- own speeds, the road's dashes, the van bouncing along with its wheels turning; at the top where you are going ("ON
-- THE WAY TO" the house, its difficulty in its colour, who rides along) and under it the route from the depot to the
-- house with the van moving along it. The van's engine pulls away as it starts and slows as it arrives
-- (art/audio/sfx6.ogg: intro_leave, intro_drive). Your controls are off while it plays; it fades into the place.
-- Reduced Motion: no bounce, the scenery slower.
--   RideUi.start()            listens to the Runs remote
--   RideUi.show(message)      the ride now (a ride already showing goes first)
--   RideUi.isShowing() -> boolean

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Sounds = require(script.Parent.Sounds)
local PhoneMotion = require(script.Parent.PhoneMotion)

local RideUi = {}

local player = Players.LocalPlayer
local R = Config.Runs.Ride
local current: any = nil -- the ride showing: { gui, connection, token }

local display = Enum.Font.GothamBlack
pcall(function()
	display = (Enum.Font :: any).LuckiestGuy -- (the store logo's font, as the intro's)
end)

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The scene's colours: the sky (top, middle, horizon), the far and the near hills, the trees, the road; night: the
-- moon, the stars and the van's lamps.
type Mood = { sky: { { number } }, far: { number }, near: { number }, tree: { number }, sun: { number }, night: boolean }
local MOODS: { [string]: Mood } = {
	easy = { sky = { { 92, 170, 242 }, { 168, 214, 246 }, { 232, 242, 222 } }, far = { 104, 168, 96 }, near = { 122, 188, 92 }, tree = { 64, 132, 62 }, sun = { 255, 244, 190 }, night = false },
	normal = { sky = { { 70, 145, 225 }, { 150, 200, 240 }, { 255, 222, 172 } }, far = { 92, 152, 86 }, near = { 112, 178, 88 }, tree = { 58, 122, 58 }, sun = { 255, 236, 170 }, night = false },
	hard = { sky = { { 64, 112, 196 }, { 238, 182, 112 }, { 255, 204, 124 } }, far = { 104, 132, 72 }, near = { 132, 156, 76 }, tree = { 74, 104, 50 }, sun = { 255, 214, 120 }, night = false },
	insane = { sky = { { 62, 52, 112 }, { 214, 102, 74 }, { 255, 164, 92 } }, far = { 70, 72, 70 }, near = { 88, 96, 66 }, tree = { 48, 60, 44 }, sun = { 255, 150, 90 }, night = false },
	nightmare = { sky = { { 10, 12, 30 }, { 30, 30, 72 }, { 72, 52, 92 } }, far = { 28, 34, 46 }, near = { 34, 44, 46 }, tree = { 20, 28, 30 }, sun = { 236, 232, 210 }, night = true },
	back = { sky = { { 82, 122, 202 }, { 230, 170, 132 }, { 255, 210, 160 } }, far = { 96, 140, 84 }, near = { 116, 162, 82 }, tree = { 62, 110, 56 }, sun = { 255, 210, 140 }, night = false },
}

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	return Ui.make(className, props, parent)
end

local function round(parent: Instance, radius: UDim?)
	make("UICorner", { CornerRadius = radius or UDim.new(0.5, 0) }, parent)
end

-- Freezes / frees your character (never waits long: a missing PlayerModule must not hold the ride up).
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

-- A layer twice the screen wide whose things repeat every screen width: moved by `offset` (0 … 1) it never shows a seam.
-- (Its things' sizes and places are in the layer's scale: half a screen's.)
local function layer(parent: Instance, name: string, z: number): any
	return make("Frame", { Name = name, Size = UDim2.fromScale(2, 1), BackgroundTransparency = 1, ZIndex = z }, parent)
end

-- The same thing at x and at x + 1 (in screen widths) on a layer.
local function twice(parent: Instance, build: (x: number) -> ())
	local _ = parent
	build(0)
	build(1)
end

-- A random generator of the scenery, the same for the same place (the same trip looks the same).
local function seeded(text: string): Random
	local seed = 0
	for i = 1, #text do
		seed = (seed * 31 + string.byte(text, i)) % 2147483647
	end
	return Random.new(seed)
end

function RideUi.isShowing(): boolean
	return current ~= nil
end

local function close(ride: any)
	if current == ride then
		current = nil
	end
	if ride.connection then
		ride.connection:Disconnect()
	end
	if ride.gui then
		ride.gui:Destroy()
	end
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
	local mood = MOODS[if back then "back" else (difficulty or "normal")] or MOODS.normal
	local to = if type(message.to) == "string" then message.to else "the house"
	local reduced = PhoneMotion.reducedMotion()
	local rng = seeded(to)
	local ride: any = { started = os.clock() }
	current = ride

	local gui = make("ScreenGui", {
		Name = "Ride", DisplayOrder = 150, IgnoreGuiInset = true, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	ride.gui = gui
	local root = make("CanvasGroup", { Name = "Scene", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = 1 }, gui)
	local sky = make("Frame", { Name = "Sky", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 0 }, root)
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(mood.sky[1])),
			ColorSequenceKeypoint.new(0.55, rgb(mood.sky[2])),
			ColorSequenceKeypoint.new(1, rgb(mood.sky[3])),
		}),
	}, sky) -- (on a frame of its own: a gradient on the CanvasGroup would tint all of it)

	-- the sun (the moon at night) and, at night, the stars
	local sun = make("Frame", {
		Size = UDim2.fromScale(0.11, 0.11), Position = UDim2.fromScale(if mood.night then 0.8 else 0.82, if mood.night then 0.2 else 0.57), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = rgb(mood.sun), BorderSizePixel = 0, ZIndex = 1,
	}, root)
	make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, sun)
	round(sun)
	if mood.night then
		for _ = 1, 40 do
			local star = make("Frame", {
				Size = UDim2.fromOffset(2, 2), Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber() * 0.5),
				BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = rng:NextNumber(0.1, 0.6), BorderSizePixel = 0, ZIndex = 1,
			}, root)
			round(star)
		end
	end

	-- the far hills, the near hills with their trees, the fence posts, the road and its dashes (back to front)
	local far = layer(root, "FarHills", 2)
	local farAt: { { number } } = {} -- (drawn once for both copies: each screen width the same, never a seam)
	for i = 0, 3 do
		table.insert(farAt, { i * 0.25 + rng:NextNumber(0, 0.05), 0.5 + rng:NextNumber(0, 0.06) })
	end
	twice(far, function(x: number)
		for _, spot in farAt do
			local hill = make("Frame", {
				Size = UDim2.fromScale(0.16, 0.5), Position = UDim2.fromScale((x + spot[1]) / 2, spot[2]),
				BackgroundColor3 = rgb(mood.far), BorderSizePixel = 0, ZIndex = 2,
			}, far)
			round(hill)
		end
	end)
	local near = layer(root, "NearHills", 3)
	twice(near, function(x: number)
		for i = 0, 2 do
			local hill = make("Frame", {
				Size = UDim2.fromScale(0.25, 0.5), Position = UDim2.fromScale((x + i * 0.34) / 2, 0.6),
				BackgroundColor3 = rgb(mood.near), BorderSizePixel = 0, ZIndex = 3,
			}, near)
			round(hill)
		end
	end)
	local trees = layer(root, "Trees", 4)
	local treeAt: { { number } } = {}
	for _ = 1, 7 do
		table.insert(treeAt, { rng:NextNumber(), rng:NextNumber(0.75, 1.25) })
	end
	twice(trees, function(x: number)
		for _, spot in treeAt do
			local size = 0.12 * spot[2]
			local trunk = make("Frame", {
				Size = UDim2.fromScale(0.004, size * 0.5), Position = UDim2.fromScale((x + spot[1]) / 2, 0.82), AnchorPoint = Vector2.new(0.5, 1),
				BackgroundColor3 = Color3.fromRGB(92, 64, 44), BorderSizePixel = 0, ZIndex = 4,
			}, trees)
			local crown = make("Frame", {
				Size = UDim2.fromScale(0.022 * spot[2], size), Position = UDim2.fromScale((x + spot[1]) / 2, 0.82 - size * 0.38), AnchorPoint = Vector2.new(0.5, 1),
				BackgroundColor3 = rgb(mood.tree), BorderSizePixel = 0, ZIndex = 4,
			}, trees)
			round(crown)
			local _ = trunk
		end
	end)
	local posts = layer(root, "Posts", 5)
	twice(posts, function(x: number)
		for i = 0, 9 do
			make("Frame", {
				Size = UDim2.fromScale(0.002, 0.05), Position = UDim2.fromScale((x + i / 10) / 2, 0.84), AnchorPoint = Vector2.new(0.5, 1),
				BackgroundColor3 = Color3.fromRGB(120, 96, 70), BorderSizePixel = 0, ZIndex = 5,
			}, posts)
		end
		make("Frame", {
			Size = UDim2.new(0.5, 0, 0, 2), Position = UDim2.fromScale(x / 2, 0.81), BackgroundColor3 = Color3.fromRGB(120, 96, 70), BorderSizePixel = 0, ZIndex = 5,
		}, posts)
	end)
	local road = make("Frame", {
		Name = "Road", Size = UDim2.fromScale(1, 0.16), Position = UDim2.fromScale(0, 0.84), BackgroundColor3 = Color3.fromRGB(64, 66, 72), BorderSizePixel = 0, ZIndex = 6,
	}, root)
	make("Frame", { Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = Color3.fromRGB(190, 184, 166), BorderSizePixel = 0, ZIndex = 6 }, road)
	local dashes = layer(road, "Dashes", 7)
	dashes.Size = UDim2.new(2, 0, 0, 6)
	dashes.Position = UDim2.fromScale(0, 0.45)
	twice(dashes, function(x: number)
		for i = 0, 7 do
			make("Frame", {
				Size = UDim2.fromScale(0.02, 1), Position = UDim2.fromScale((x + i / 8) / 2, 0), BackgroundColor3 = Color3.fromRGB(238, 236, 226), BorderSizePixel = 0, ZIndex = 7,
			}, dashes)
		end
	end)

	-- the van (its side, driving right: the cab at the front), its lamps lit at night
	local van = make("Frame", {
		Name = "Van", Size = UDim2.fromScale(0.24, 0.14), Position = UDim2.fromScale(0.44, 0.87), AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1, ZIndex = 8,
	}, root)
	make("UIAspectRatioConstraint", { AspectRatio = 2.3 }, van)
	local function part(x: number, y: number, w: number, h: number, color: Color3, z: number, corner: UDim?): any
		local frame = make("Frame", { Size = UDim2.fromScale(w, h), Position = UDim2.fromScale(x, y), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z }, van)
		if corner then
			round(frame, corner)
		end
		return frame
	end
	local cream = Color3.fromRGB(246, 240, 226)
	part(0, 0.08, 0.76, 0.72, cream, 8, UDim.new(0.08, 0))
	part(0.7, 0.3, 0.3, 0.5, cream, 8, UDim.new(0.2, 0))
	part(0.76, 0.36, 0.16, 0.2, Color3.fromRGB(150, 206, 240), 9, UDim.new(0.2, 0))
	part(0, 0.5, 1, 0.1, Color3.fromRGB(245, 124, 30), 9)
	local badge = part(0.08, 0.2, 0.12, 0.24, Color3.fromRGB(204, 32, 38), 9, UDim.new(0.2, 0))
	make("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "D", Font = display, TextScaled = true, TextColor3 = Color3.fromRGB(255, 230, 90), ZIndex = 10 }, badge)
	part(0.96, 0.6, 0.04, 0.08, Color3.fromRGB(255, 236, 140), 9)
	if mood.night then
		local beam = part(1, 0.42, 0.9, 0.42, Color3.fromRGB(255, 240, 180), 7)
		make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }) }, beam)
	end
	local hubs: { Frame } = {}
	for _, x in { 0.2, 0.74 } do
		local wheel = part(x - 0.08, 0.66, 0.16, 0.36, Color3.fromRGB(34, 34, 38), 10, UDim.new(0.5, 0))
		make("UIAspectRatioConstraint", { AspectRatio = 1 }, wheel)
		local hub = make("Frame", {
			Size = UDim2.fromScale(0.55, 0.12), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(190, 192, 196), BorderSizePixel = 0, ZIndex = 11,
		}, wheel)
		table.insert(hubs, hub)
	end

	-- where you are going: the card at the top and the route under it
	local card = make("Frame", {
		Name = "Card", Size = UDim2.fromScale(0.6, 0.2), Position = UDim2.fromScale(0.5, 0.1), AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1, ZIndex = 12,
	}, root)
	make("UISizeConstraint", { MinSize = Vector2.new(280, 90) }, card)
	local lead = make("TextLabel", {
		Size = UDim2.fromScale(1, 0.2), BackgroundTransparency = 1, Text = if back then "BACK TO" else "ON THE WAY TO", Font = Enum.Font.GothamBold,
		TextScaled = true, TextColor3 = Color3.new(1, 1, 1), ZIndex = 12,
	}, card)
	make("UITextSizeConstraint", { MaxTextSize = 18 }, lead)
	make("UIStroke", { Color = Color3.fromRGB(30, 40, 62), Thickness = 1.5, Transparency = 0.3 }, lead)
	local title = make("TextLabel", {
		Size = UDim2.fromScale(1, 0.48), Position = UDim2.fromScale(0, 0.2), BackgroundTransparency = 1, Text = string.upper(to), Font = display,
		TextScaled = true, TextColor3 = Color3.new(1, 1, 1), ZIndex = 12,
	}, card)
	make("UITextSizeConstraint", { MaxTextSize = 56 }, title)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 238, 80), Color3.fromRGB(248, 136, 20)) }, title)
	make("UIStroke", { Color = Color3.fromRGB(150, 22, 28), Thickness = 3, LineJoinMode = Enum.LineJoinMode.Round }, title)
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
	local line = make("TextLabel", {
		Size = UDim2.fromScale(1, 0.2), Position = UDim2.fromScale(0, 0.72), BackgroundTransparency = 1, Text = table.concat(bits, "   ·   "), Font = Enum.Font.GothamBold,
		TextScaled = true, TextColor3 = if def then rgb(def.color) else Color3.new(1, 1, 1), ZIndex = 12,
	}, card)
	make("UITextSizeConstraint", { MaxTextSize = 20 }, line)
	make("UIStroke", { Color = Color3.fromRGB(20, 24, 36), Thickness = 1.5, Transparency = 0.2 }, line)
	-- the route: the depot ● ────🚐──── ● the house (on the way back, the other way round)
	local route = make("Frame", {
		Name = "Route", Size = UDim2.fromScale(0.42, 0.05), Position = UDim2.fromScale(0.5, 0.34), AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1, ZIndex = 12,
	}, root)
	make("UISizeConstraint", { MinSize = Vector2.new(220, 26) }, route)
	make("Frame", {
		Size = UDim2.new(1, 0, 0, 4), Position = UDim2.fromScale(0, 0.5), AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 12,
	}, route)
	for i, x in { 0, 1 } do
		local dot = make("Frame", {
			Size = UDim2.fromOffset(14, 14), Position = UDim2.fromScale(x, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = if i == 2 then (if def then rgb(def.color) else Color3.fromRGB(245, 124, 30)) else Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 13,
		}, route)
		round(dot)
		make("UIStroke", { Color = Color3.fromRGB(30, 40, 62), Thickness = 2 }, dot)
	end
	make("TextLabel", {
		Size = UDim2.fromOffset(120, 18), Position = UDim2.new(0, 0, 1, 4), BackgroundTransparency = 1, Text = if back then "THE HOUSE" else "DEPOT",
		Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12,
	}, route)
	make("TextLabel", {
		Size = UDim2.fromOffset(120, 18), Position = UDim2.new(1, -120, 1, 4), BackgroundTransparency = 1, Text = if back then "DEPOT" else "THE HOUSE",
		Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 12,
	}, route)
	local marker = make("TextLabel", {
		Size = UDim2.fromOffset(30, 30), Position = UDim2.fromScale(0, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1,
		Text = "🚐", TextSize = 24, ZIndex = 14,
	}, route)

	-- off it goes: the scene fades in over the jump's fade, the scenery goes by, the engine pulls away and slows
	controls(false)
	TweenService:Create(root, TweenInfo.new(0.25), { GroupTransparency = 0 }):Play()
	Sounds.play("intro_leave", 0.8)
	if seconds > 2 then
		task.delay(seconds - 1.6, function()
			if current == ride then
				Sounds.play("intro_drive", 0.8)
			end
		end)
	end
	local speed = if reduced then 0.5 else 1
	local travelled = 0
	ride.connection = RunService.RenderStepped:Connect(function(dt: number)
		local elapsed = os.clock() - ride.started
		local u = math.clamp(elapsed / seconds, 0, 1)
		-- fast on the open road, slowing at the end (the van arrives)
		local pace = (if u < 0.75 then 1 else 1 - (u - 0.75) / 0.25 * 0.8) * speed
		travelled += dt * pace
		far.Position = UDim2.fromScale(-((travelled * 0.03) % 1), 0)
		near.Position = UDim2.fromScale(-((travelled * 0.07) % 1), 0)
		trees.Position = UDim2.fromScale(-((travelled * 0.16) % 1), 0)
		posts.Position = UDim2.fromScale(-((travelled * 0.35) % 1), 0)
		dashes.Position = UDim2.fromScale(-((travelled * 0.9) % 1), 0.45)
		for _, hub in hubs do
			hub.Rotation = (travelled * 720) % 360
		end
		if not reduced then
			van.Position = UDim2.new(0.44, 0, 0.87, -math.abs(math.sin(travelled * 14)) * 3 * pace)
			van.Rotation = math.sin(travelled * 9) * 0.5 * pace
		end
		marker.Position = UDim2.fromScale(u, 0.5)
	end)
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
