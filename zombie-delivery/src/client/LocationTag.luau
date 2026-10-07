--!strict
-- 4.3, the location tag: when you come up to a building, a quiet caption names it, in the contract style
-- (design/ui-contract, the captions of design/location-looks): a small red square and the name in white caps, a fine
-- line, the kind of place under it in the secondary colour ("■ LEAD & CO." / "GUN SHOP"), on a subtle charcoal scrim
-- that fades out to the right. No box, no sound. It fades and slides in (8 px, 0.35 s) and fades out (0.5 s).
--
-- What shows and when is shared/LocationTags.luau (pure, tested): the nearest discovered landmark within ~45 studs,
-- gone farther than ~70 or after 4.5 s, each at most once per 90 s. Here a loop asks it four times a second (no
-- per-frame work). A new caption starts only on foot or in a car slower than 25 studs/s, while the HUD shows
-- (ZombieDeliveryHud enabled), no window is open (LocationTag.windowOpen, set by client/Main.client.luau) and the
-- "NEW LOCATION DISCOVERED" banner is quiet (client/Discovery.luau); a place that banner just announced waits its
-- cooldown. Its own ScreenGui (ResetOnSpawn off, the HUD's safe insets).
--
-- Where: like the captions of the preview, on the left just over the lower-left group (cash, minimap, health) on a
-- computer, or over the thumbstick's corner on a touch screen; when that would touch a HUD group or a touch button,
-- top centre, then a little lower in the centre (LocationTags.place picks the first clear spot).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LocationTags = require(Shared.LocationTags)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local Discovery = require(script.Parent.Discovery)
local TouchLayout = require(script.Parent.TouchLayout)

local LocationTag = {}

-- Is a big window open (the menu, a shop, the map ...)? client/Main.client.luau sets it; no caption meanwhile.
LocationTag.windowOpen = nil :: (() -> boolean)?

local K = Theme.Contract
local POLL = 0.25 -- seconds between two checks
local FADE_IN, FADE_OUT = 0.35, 0.5
local SLIDE = 8 -- px (unscaled) it rises while it fades in
local NAME_SIZE, SUB_SIZE = 17, 12 -- unscaled (about 19 and 13 px at 1080p)
local PAD, TAIL = 10, 36 -- the text's left inset, the scrim's fade to the right
local MARGIN, GAP = 16, 10
local HUD_GROUPS = { "LeftStack", "TopStack", "HudButtons", "RightStack", "Hint", "Fire", "BottomBar" } -- client/Hud.luau's panels (6.0.1: and client/Hotbar.luau's bar)

local player = Players.LocalPlayer
local gui: any = nil
local tag: any = nil
local scale: any = nil
local scrimGradient: any = nil
local marker: any = nil
local nameLabel: any = nil
local rule: any = nil
local subLabel: any = nil
local hudGui: Instance? = nil
local token = 0 -- the current show (a fade-out of an older one does not hide a newer one)

local LEFT_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.62, 0.15),
	NumberSequenceKeypoint.new(1, 1),
})
local BOTH_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.18, 0.1),
	NumberSequenceKeypoint.new(0.82, 0.1),
	NumberSequenceKeypoint.new(1, 1),
})

local function build()
	gui = Ui.make("ScreenGui", {
		Name = "LocationTag",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, -- the HUD's space: clear of a notch and the top bar
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1, -- with the discovery banner: over the HUD, under the windows
	}, player:WaitForChild("PlayerGui"))
	-- A CanvasGroup: the caption fades as one.
	tag = Ui.make("CanvasGroup", {
		Name = "Tag",
		Size = UDim2.fromOffset(240, 56),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
	}, gui)
	scale = Ui.make("UIScale", {}, tag)
	-- The scrim: charcoal behind the text only, fading out (to the right, or to both sides in the centre).
	local scrim = Ui.make("Frame", {
		Name = "Scrim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, tag)
	scrimGradient = Ui.make("UIGradient", { Transparency = LEFT_FADE }, scrim)
	-- Line 1: the small red square and the name.
	marker = Ui.make("Frame", {
		Name = "Marker",
		Size = UDim2.fromOffset(6, 6),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(PAD, 19),
		BackgroundColor3 = K.red,
		BorderSizePixel = 0,
	}, tag)
	nameLabel = Ui.make("TextLabel", {
		Name = "Place",
		Size = UDim2.new(1, -(PAD + 14), 0, 22),
		Position = UDim2.fromOffset(PAD + 14, 8),
		BackgroundTransparency = 1,
		Text = "",
		Font = Theme.HeadingFont,
		TextSize = NAME_SIZE,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextStrokeColor3 = K.charcoal,
		TextStrokeTransparency = 0.65,
	}, tag)
	-- The fine line under it.
	rule = Ui.make("Frame", {
		Name = "Rule",
		Size = UDim2.new(1, -(PAD + TAIL), 0, 1),
		Position = UDim2.fromOffset(PAD, 34),
		BackgroundColor3 = K.line,
		BackgroundTransparency = K.lineAlpha,
		BorderSizePixel = 0,
	}, tag)
	-- Line 2: what the place is.
	subLabel = Ui.make("TextLabel", {
		Name = "Kind",
		Size = UDim2.new(1, -PAD, 0, 16),
		Position = UDim2.fromOffset(PAD, 38),
		BackgroundTransparency = 1,
		Text = "",
		Font = Theme.HeadingFont,
		TextSize = SUB_SIZE,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextStrokeColor3 = K.charcoal,
		TextStrokeTransparency = 0.75,
	}, tag)
end

-- ── Where ──────────────────────────────────────────────────────────────────

local function rectOf(object: GuiObject, origin: Vector2): LocationTags.Rect
	local p, s = object.AbsolutePosition - origin, object.AbsoluteSize
	return { x0 = p.X, y0 = p.Y, x1 = p.X + s.X, y1 = p.Y + s.Y }
end

-- The caption's top left corner (px in its ScreenGui) for a caption w × h px on the left or wc × h px in the centre
-- (already scaled), and whether it sits in the centre (its scrim then fades to both sides).
local function placeFor(w: number, wc: number, h: number, S: number): (number, number, boolean)
	local size: Vector2 = gui.AbsoluteSize
	local W, H = size.X, size.Y
	local origin: Vector2 = gui.AbsolutePosition
	local obstacles: { LocationTags.Rect } = {}
	local leftTop = H - MARGIN - 270 * S -- (no HUD found: about where its lower-left group's top is)
	local hud = hudGui
	if hud then
		for _, name in HUD_GROUPS do
			local group = hud:FindFirstChild(name)
			if group and group:IsA("GuiObject") and group.Visible and group.AbsoluteSize.X > 1 then
				table.insert(obstacles, rectOf(group, origin))
			end
		end
	end
	local candidates: { LocationTags.Rect } = {}
	local function add(x: number, bottom: number, width: number)
		table.insert(candidates, { x0 = x, y0 = bottom - h, x1 = x + width, y1 = bottom })
	end
	if Ui.touchLayout() then
		-- The thumbstick's corner and the touch buttons (client/TouchLayout.luau) are not to be covered.
		local c = TouchLayout.cluster(W, H, Ui.scaleFor(size))
		for _, b in TouchLayout.buttons(c) do
			table.insert(obstacles, b)
		end
		table.insert(obstacles, c.thumb)
		table.insert(obstacles, c.jump)
		add(MARGIN, c.thumb.y0 - GAP, w)
	else
		local left = hud and hud:FindFirstChild("LeftStack")
		if left and left:IsA("GuiObject") and left.Visible then
			leftTop = left.AbsolutePosition.Y - origin.Y
		end
		add(MARGIN, leftTop - GAP, w)
	end
	add((W - wc) / 2, MARGIN + h, wc) -- top centre
	add((W - wc) / 2, H * 0.2 + h, wc) -- a little lower in the centre
	local chosen = candidates[LocationTags.place(candidates, obstacles, W, H)]
	return chosen.x0, chosen.y0, chosen ~= candidates[1]
end

-- ── Show and hide ──────────────────────────────────────────────────────────

local function textWidth(text: string, size: number): number
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(text, size, Theme.HeadingFont, Vector2.new(1000, 100))
	end)
	return if ok then bounds.X else #text * size * 0.65
end

local function show(t: LocationTags.Tag)
	token += 1
	local name = string.upper(t.name)
	local sub = t.sub
	nameLabel.Text = name
	subLabel.Text = sub or ""
	subLabel.Visible = sub ~= nil
	local w = math.clamp(math.max(PAD + 14 + textWidth(name, NAME_SIZE), PAD + (if sub then textWidth(sub, SUB_SIZE) else 0)) + TAIL, 180, 440)
	local h = if sub then 58 else 42
	local S = Ui.screenScale()
	scale.Scale = S
	-- In the centre the text moves in from the left by as much as the scrim fades on the right.
	local inset = TAIL - PAD
	local x, y, centred = placeFor(w * S, (w + inset) * S, h * S, S)
	if not centred then
		inset = 0
	end
	tag.Size = UDim2.fromOffset(w + inset, h)
	marker.Position = UDim2.fromOffset(PAD + inset, 19)
	nameLabel.Position = UDim2.fromOffset(PAD + inset + 14, 8)
	nameLabel.Size = UDim2.new(1, -(PAD + inset + 14), 0, 22)
	rule.Position = UDim2.fromOffset(PAD + inset, 34)
	rule.Size = UDim2.new(1, -(PAD + inset + TAIL), 0, 1)
	subLabel.Position = UDim2.fromOffset(PAD + inset, 38)
	subLabel.Size = UDim2.new(1, -(PAD + inset), 0, 16)
	scrimGradient.Transparency = if centred then BOTH_FADE else LEFT_FADE
	tag.Visible = true
	tag.GroupTransparency = 1
	tag.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + SLIDE * S + 0.5))
	TweenService:Create(tag, TweenInfo.new(FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
		Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5)),
	}):Play()
end

local function hide()
	if not tag or not tag.Visible then
		return
	end
	token += 1
	local mine = token
	TweenService:Create(tag, TweenInfo.new(FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		GroupTransparency = 1,
	}):Play()
	task.delay(FADE_OUT + 0.05, function()
		if token == mine then
			tag.Visible = false
		end
	end)
end

-- ── The loop ───────────────────────────────────────────────────────────────

local tags = LocationTags.build()
local state = LocationTags.new()

-- Known (discovered) places; before the map's state came, everything counts.
local function known(id: string): boolean
	return not Discovery.ready or Discovery.knows(id)
end

-- The HUD is up and nothing covers the world (no window, no discovery banner).
local function quiet(): boolean
	local hud = hudGui
	if not hud or not hud.Parent then
		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		hud = if playerGui then playerGui:FindFirstChild("ZombieDeliveryHud") else nil
		hudGui = hud
	end
	if not hud or not hud:IsA("ScreenGui") or not hud.Enabled then
		return false
	end
	local windowOpen = LocationTag.windowOpen
	if windowOpen and windowOpen() then
		return false
	end
	return not Discovery.busy()
end

local function check()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 or not quiet() then
		if LocationTags.drop(state) then
			hide()
		end
		return
	end
	-- On foot, or in a car going slowly.
	local canStart = true
	local seat = humanoid.SeatPart
	if seat then
		local v = seat.AssemblyLinearVelocity
		canStart = Vector2.new(v.X, v.Z).Magnitude < LocationTags.MAX_SPEED
	end
	local position = root.Position
	local action, t = LocationTags.step(state, tags, position.X, position.Z, os.clock(), canStart, known)
	if action == "show" and t then
		show(t)
	elseif action == "hide" then
		hide()
	end
end

function LocationTag.start()
	build()
	-- A place the discovery banner just announced (it became known while playing) waits its cooldown.
	local wasKnown: { [string]: boolean } = {}
	local function snapshot(markNew: boolean)
		local now = os.clock()
		for _, t in tags do
			local isKnown = Discovery.knows(t.id)
			if isKnown and markNew and not wasKnown[t.id] then
				LocationTags.mark(state, t.id, now)
			end
			wasKnown[t.id] = isKnown
		end
	end
	snapshot(false)
	Discovery.changed:Connect(function(cells: { number }?)
		snapshot(cells ~= nil) -- (nil: the state on joining, nothing was announced)
	end)
	task.spawn(function()
		while true do
			task.wait(POLL)
			local ok, err = pcall(function()
				check()
			end)
			if not ok then
				warn(`[LocationTag] {err}`)
				task.wait(5)
			end
		end
	end)
end

return LocationTag
