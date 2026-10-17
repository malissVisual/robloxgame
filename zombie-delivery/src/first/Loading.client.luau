--!strict
-- 10.1, the intro and the loading screen (the owner: "když zapnu tu moji hru … intro takový jenom kratší a loading
-- screen"). ReplicatedFirst runs this before anything else of the game reaches the client, so it stands alone: it
-- requires nothing, its few numbers live here (Shared and Config are not there yet), and Roblox's own loading screen
-- is taken away at once.
--   * The intro (about 2.6 s): a sunrise over green hills, the Deliveros van drives in along the road, the DELIVEROS
--     wordmark pops up (Luckiest Guy, the store logo's gold with its red edge), MOVE · FIND · GROW under it.
--   * The loading: a bar and a line under it that say what is coming (the world, your saves), and a tip.
--   * It goes once the intro has run, the game has loaded (game:IsLoaded) and the start screen is up (client/Menu.luau
--     sets the player attribute StartScreen), or after GIVE_UP s whatever happens: the van drives off to the right and
--     the screen fades into the start screen. Any key, a click or a tap skips the rest of the intro (never the loading).
-- With Reduced Motion on (Roblox's setting) nothing bounces: the pieces just fade in.
-- 10.1, its sounds (art/audio/sfx6.ogg: SoundSheet.Sfx6; while it is not uploaded, SoundSheet.Fallback's stand-ins): the
-- van driving in, the wordmark's jingle, the van driving off. Shared is not there when this starts, so it waits for
-- SoundSheet a moment (SHEET_WAIT s, in its own thread) and plays each sound at its moment, or leaves it out when its
-- asset was not ready LATE s after it (a jingle long after the logo would only confuse).

local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local INTRO = 2.6 -- s the intro runs before it may go (unless skipped)
local SKIP_FROM = 0.8 -- s before a key may skip it
local GIVE_UP = 25 -- s at most: then it goes, ready or not
local OUT = 0.55 -- s the van drives off and the screen fades
local SHEET_WAIT = 5 -- s it waits for Shared's SoundSheet (the intro's sounds)
local LATE = 0.35 -- s a sound may start after its moment, else it is left out
local VOLUME = 0.7
-- the sheets in the order client/Sounds.luau looks for a sound (each with its asset id's field)
local SHEETS = { { "Sfx", "SfxId" }, { "Sfx2", "Sfx2Id" }, { "Sfx3", "Sfx3Id" }, { "Sfx4", "Sfx4Id" }, { "Sfx5", "Sfx5Id" }, { "Sfx6", "Sfx6Id" } }
local TIPS = {
	"Every move hides 2 – 4 collectibles. Legendary ones glow gold.",
	"Put your best pieces on the stands: they earn money every minute you play.",
	"Hire Danny for a big house: he carries while you sort.",
	"Grow your warehouse from a garage to a Logistics Center.",
	"Hot kinds on the market sell for 40 % more today.",
	"Each save slot is its own game: start over any time in another one.",
}

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local reduced = false
pcall(function()
	reduced = GuiService.ReducedMotionEnabled
end)
local started = os.clock()

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance: any = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function round(parent: Instance, radius: UDim?)
	make("UICorner", { CornerRadius = radius or UDim.new(0.5, 0) }, parent)
end

local function tween(target: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(target, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local display = Enum.Font.GothamBlack
pcall(function()
	display = (Enum.Font :: any).LuckiestGuy -- (the store logo's font; Gotham Black should Roblox not have it)
end)

-- ── The scene ──────────────────────────────────────────────────────────────

local gui = make("ScreenGui", {
	Name = "Loading", DisplayOrder = 200, IgnoreGuiInset = true, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
local root = make("Frame", { Name = "Screen", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(255, 255, 255), BorderSizePixel = 0, Active = true }, gui)
make("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(58, 128, 214)),
		ColorSequenceKeypoint.new(0.55, rgb(150, 196, 236)),
		ColorSequenceKeypoint.new(1, rgb(255, 206, 150)),
	}),
}, root)
-- the sun and its glow, low over the hills
local glow = make("Frame", {
	Name = "Glow", Size = UDim2.fromScale(0.4, 0.4), Position = UDim2.fromScale(0.78, 0.6), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = rgb(255, 226, 150), BackgroundTransparency = 0.45, BorderSizePixel = 0,
}, root)
make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, glow)
round(glow)
make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }), Rotation = 90 }, glow)
local sun = make("Frame", {
	Name = "Sun", Size = UDim2.fromScale(0.16, 0.16), Position = UDim2.fromScale(0.78, 0.6), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = rgb(255, 238, 170), BorderSizePixel = 0,
}, root)
make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, sun)
round(sun)
-- the hills (far, near) and the road in front of them
local function hill(x: number, y: number, w: number, h: number, color: Color3, z: number)
	local frame = make("Frame", {
		Size = UDim2.fromScale(w, h), Position = UDim2.fromScale(x, y), AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z,
	}, root)
	round(frame)
end
hill(0.18, 0.62, 0.9, 0.7, rgb(86, 150, 84), 1)
hill(0.86, 0.6, 0.8, 0.7, rgb(78, 140, 78), 1)
hill(0.5, 0.7, 1.5, 0.8, rgb(108, 176, 86), 2)
local road = make("Frame", {
	Name = "Road", Size = UDim2.fromScale(1, 0.16), Position = UDim2.fromScale(0, 0.84), BackgroundColor3 = rgb(70, 72, 78), BorderSizePixel = 0, ZIndex = 3,
}, root)
make("Frame", { Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = rgb(196, 190, 170), BorderSizePixel = 0, ZIndex = 3 }, road)
local dashes = make("Frame", { Name = "Dashes", Size = UDim2.new(2, 0, 0, 6), Position = UDim2.fromScale(0, 0.45), BackgroundTransparency = 1, ZIndex = 4 }, road)
for i = 0, 23 do
	make("Frame", {
		Size = UDim2.new(1 / 24 * 0.55, 0, 1, 0), Position = UDim2.fromScale(i / 24, 0),
		BackgroundColor3 = rgb(238, 236, 226), BorderSizePixel = 0, ZIndex = 4,
	}, dashes)
end

-- the van (the Sprinter's shape in flat blocks: cream, the orange band, the logo's red D)
local van = make("Frame", {
	Name = "Van", Size = UDim2.fromScale(0.26, 0.15), Position = UDim2.fromScale(-0.3, 0.86), AnchorPoint = Vector2.new(0.5, 1),
	BackgroundTransparency = 1, ZIndex = 6,
}, root)
make("UIAspectRatioConstraint", { AspectRatio = 2.3 }, van)
local function part(name: string, x: number, y: number, w: number, h: number, color: Color3, z: number, corner: UDim?): any
	local frame = make("Frame", {
		Name = name, Size = UDim2.fromScale(w, h), Position = UDim2.fromScale(x, y), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z,
	}, van)
	if corner then
		round(frame, corner)
	end
	return frame
end
part("Body", 0, 0.08, 0.76, 0.72, rgb(246, 240, 226), 6, UDim.new(0.08, 0))
part("Cab", 0.7, 0.3, 0.3, 0.5, rgb(246, 240, 226), 6, UDim.new(0.2, 0))
part("Window", 0.76, 0.36, 0.16, 0.2, rgb(150, 206, 240), 7, UDim.new(0.2, 0))
part("Band", 0, 0.5, 1, 0.1, rgb(245, 124, 30), 7)
part("Badge", 0.08, 0.2, 0.12, 0.24, rgb(204, 32, 38), 7, UDim.new(0.2, 0))
make("TextLabel", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "D", Font = display, TextScaled = true,
	TextColor3 = rgb(255, 230, 90), ZIndex = 8,
}, van:FindFirstChild("Badge"))
part("Lamp", 0.96, 0.6, 0.04, 0.08, rgb(255, 236, 140), 7)
for _, x in { 0.2, 0.74 } do
	local wheel = part("Wheel", x - 0.08, 0.66, 0.16, 0.36, rgb(34, 34, 38), 8, UDim.new(0.5, 0))
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, wheel)
	local hub = make("Frame", {
		Size = UDim2.fromScale(0.45, 0.45), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = rgb(190, 192, 196), BorderSizePixel = 0, ZIndex = 9,
	}, wheel)
	round(hub)
end

-- the wordmark and the slogan
local mark = make("Frame", {
	Name = "Mark", Size = UDim2.fromScale(0.62, 0.2), Position = UDim2.fromScale(0.5, 0.3), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1, ZIndex = 10,
}, root)
local markScale = make("UIScale", { Scale = if reduced then 1 else 0.3 }, mark)
local shadow = make("TextLabel", {
	Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0.006, 0.05), BackgroundTransparency = 1, Text = "DELIVEROS", Font = display,
	TextScaled = true, TextColor3 = rgb(90, 20, 24), TextTransparency = 1, ZIndex = 10,
}, mark)
local word = make("TextLabel", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "DELIVEROS", Font = display, TextScaled = true,
	TextColor3 = rgb(255, 255, 255), TextTransparency = 1, ZIndex = 11,
}, mark)
make("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(255, 238, 80)),
		ColorSequenceKeypoint.new(0.5, rgb(255, 198, 34)),
		ColorSequenceKeypoint.new(1, rgb(248, 124, 14)),
	}),
}, word)
local edge = make("UIStroke", { Color = rgb(170, 24, 30), Thickness = 4, Transparency = 1, LineJoinMode = Enum.LineJoinMode.Round }, word)
local slogan = make("TextLabel", {
	Name = "Slogan", Size = UDim2.fromScale(0.5, 0.055), Position = UDim2.fromScale(0.5, 0.43), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1, Text = "MOVE  ·  FIND  ·  GROW", Font = display, TextScaled = true, TextColor3 = rgb(255, 255, 255),
	TextTransparency = 1, ZIndex = 10,
}, root)
local sloganEdge = make("UIStroke", { Color = rgb(40, 60, 100), Thickness = 2, Transparency = 1 }, slogan)

-- the bar, what it waits for, a tip, the skip hint
local panel = make("Frame", {
	Name = "Progress", Size = UDim2.fromScale(0.42, 0.1), Position = UDim2.fromScale(0.5, 0.6), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1, ZIndex = 10,
}, root)
make("UISizeConstraint", { MinSize = Vector2.new(260, 60) }, panel)
local track = make("Frame", {
	Size = UDim2.new(1, 0, 0.22, 0), BackgroundColor3 = rgb(30, 40, 62), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 10,
}, panel)
round(track)
local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = rgb(245, 124, 30), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 11 }, track)
round(fill)
make("UIGradient", { Color = ColorSequence.new(rgb(255, 210, 60), rgb(245, 110, 24)) }, fill)
local status = make("TextLabel", {
	Size = UDim2.new(1, 0, 0.3, 0), Position = UDim2.fromScale(0, 0.32), BackgroundTransparency = 1, Text = "Loading the countryside…",
	Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = rgb(255, 255, 255), TextTransparency = 1, ZIndex = 10,
}, panel)
make("UITextSizeConstraint", { MaxTextSize = 20 }, status)
make("UIStroke", { Color = rgb(30, 40, 62), Thickness = 1.5, Transparency = 0.3 }, status)
local tip = make("TextLabel", {
	Size = UDim2.new(1.3, 0, 0.26, 0), Position = UDim2.fromScale(-0.15, 0.7), BackgroundTransparency = 1, Text = TIPS[math.random(1, #TIPS)],
	Font = Enum.Font.GothamMedium, TextScaled = true, TextColor3 = rgb(255, 255, 255), TextTransparency = 1, ZIndex = 10,
}, panel)
make("UITextSizeConstraint", { MaxTextSize = 16 }, tip)
make("UIStroke", { Color = rgb(30, 40, 62), Thickness = 1, Transparency = 0.4 }, tip)
local skip = make("TextLabel", {
	Size = UDim2.fromScale(0.4, 0.03), Position = UDim2.new(0.98, 0, 0.98, 0), AnchorPoint = Vector2.new(1, 1), BackgroundTransparency = 1,
	Text = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Tap to skip" else "Press any key to skip",
	Font = Enum.Font.GothamMedium, TextScaled = true, TextColor3 = rgb(230, 230, 226), TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 12,
}, root)
make("UITextSizeConstraint", { MaxTextSize = 14 }, skip)
local veil = make("Frame", { Name = "Veil", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(12, 14, 18), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 50 }, gui)

-- ── The sounds ─────────────────────────────────────────────────────────────

local sounds: { [string]: Sound } = {}

-- A sound's asset and region: the first sheet that has it and is uploaded, else its stand-in's (as client/Sounds.luau).
local function find(sheet: any, name: string, depth: number): (string?, NumberRange?)
	for _, pair in SHEETS do
		local list, id = sheet[pair[1]], sheet[pair[2]]
		local r = if type(list) == "table" then list[name] else nil
		if type(r) == "table" and type(id) == "string" and id ~= "" then
			return id, NumberRange.new(r[1], r[1] + r[2])
		end
	end
	local standIn = if type(sheet.Fallback) == "table" then sheet.Fallback[name] else nil
	if type(standIn) == "string" and depth < 4 then
		return find(sheet, standIn, depth + 1)
	end
	return nil, nil
end

task.spawn(function()
	local shared = ReplicatedStorage:WaitForChild("Shared", SHEET_WAIT)
	local module = if shared then shared:WaitForChild("SoundSheet", SHEET_WAIT) else nil
	if not module or not module:IsA("ModuleScript") then
		return
	end
	local ok, sheet = pcall(require, module)
	if not ok or type(sheet) ~= "table" then
		return
	end
	local made: { Instance } = {}
	for _, name in { "intro_drive", "intro_logo", "intro_leave" } do
		local asset, range = find(sheet, name, 0)
		if asset and range then
			local sound = make("Sound", {
				Name = name, SoundId = asset, PlaybackRegionsEnabled = true, PlaybackRegion = range, Volume = VOLUME,
			}, SoundService)
			sounds[name] = sound
			table.insert(made, sound)
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(made)
	end)
end)

-- `name` at `at` s after the start (waiting LATE s at most for its asset), else not at all.
local function cue(name: string, at: number)
	task.spawn(function()
		local wait = started + at - os.clock()
		if wait > 0 then
			task.wait(wait)
		end
		local deadline = math.max(started + at, os.clock()) + LATE
		while os.clock() < deadline and not (sounds[name] and sounds[name].IsLoaded) do
			task.wait(0.05)
		end
		local sound = sounds[name]
		if sound and sound.IsLoaded then
			sound.TimePosition = sound.PlaybackRegion.Min
			sound:Play()
		end
	end)
end

-- ── The intro ──────────────────────────────────────────────────────────────

local skipped = false
tween(veil, 0.35, { BackgroundTransparency = 1 })
task.delay(0.1, function()
	tween(van, if reduced then 0.01 else 1.2, { Position = UDim2.fromScale(0.3, 0.86) }, Enum.EasingStyle.Quint)
end)
cue("intro_drive", 0.1)
cue("intro_logo", 0.55)
task.delay(0.55, function()
	tween(word, 0.3, { TextTransparency = 0 })
	tween(edge, 0.3, { Transparency = 0 })
	tween(shadow, 0.3, { TextTransparency = 0.35 })
	if not reduced then
		tween(markScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end)
task.delay(1.2, function()
	tween(slogan, 0.45, { TextTransparency = 0 })
	tween(sloganEdge, 0.45, { Transparency = 0.2 })
end)
task.delay(1.0, function()
	tween(track, 0.4, { BackgroundTransparency = 0.35 })
	tween(fill, 0.4, { BackgroundTransparency = 0 })
	tween(status, 0.4, { TextTransparency = 0 })
	tween(tip, 0.4, { TextTransparency = 0.1 })
end)
task.delay(SKIP_FROM, function()
	tween(skip, 0.4, { TextTransparency = 0.25 })
end)
local inputConnection = UserInputService.InputBegan:Connect(function(input: InputObject)
	if os.clock() - started < SKIP_FROM then
		return
	end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.Keyboard or kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
		or kind == Enum.UserInputType.Gamepad1 then
		skipped = true
	end
end)

-- ── The loading ────────────────────────────────────────────────────────────

local shown = 0
local tipAt = os.clock()
local bob = 0
local scroll = 0
local stepConnection = RunService.RenderStepped:Connect(function(dt: number)
	local loaded = game:IsLoaded()
	local menu = player:GetAttribute("StartScreen") == true
	local introDone = skipped or os.clock() - started >= INTRO
	local target = 0.12 + (if loaded then 0.38 else math.min(0.3, (os.clock() - started) * 0.06)) + (if menu then 0.35 else 0) + (if introDone then 0.15 else 0)
	shown += (math.min(target, 1) - shown) * math.min(1, dt * 4)
	fill.Size = UDim2.fromScale(shown, 1)
	status.Text = if not loaded then "Loading the countryside…" elseif not menu then "Opening your saves…" else "Ready!"
	if os.clock() - tipAt > 3.2 then
		tipAt = os.clock()
		tip.Text = TIPS[math.random(1, #TIPS)]
	end
	if not reduced then
		bob += dt
		scroll = (scroll + dt * 0.25) % 0.5 -- (half a road: six dashes, so the loop is seamless)
		dashes.Position = UDim2.fromScale(-scroll, 0.45)
		van.Rotation = math.sin(bob * 9) * 0.6
	end
end)

local function ready(): boolean
	return (skipped or os.clock() - started >= INTRO) and game:IsLoaded() and player:GetAttribute("StartScreen") == true
end
while not ready() and os.clock() - started < GIVE_UP do
	task.wait(0.1)
end

-- ── Off it goes ────────────────────────────────────────────────────────────

inputConnection:Disconnect()
cue("intro_leave", os.clock() - started)
tween(van, OUT, { Position = UDim2.fromScale(1.35, 0.86) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
task.wait(OUT * 0.5)
tween(root, OUT, { BackgroundTransparency = 1 })
for _, obj in root:GetDescendants() do
	if obj:IsA("TextLabel") then
		tween(obj, OUT, { TextTransparency = 1 })
	elseif obj:IsA("Frame") then
		tween(obj, OUT, { BackgroundTransparency = 1 })
	elseif obj:IsA("UIStroke") then
		tween(obj, OUT, { Transparency = 1 })
	end
end
task.wait(OUT + 0.05)
stepConnection:Disconnect()
gui:Destroy()
task.delay(2, function() -- (the van's sound rings out)
	for _, sound in sounds do
		sound:Destroy()
	end
	script:Destroy()
end)
